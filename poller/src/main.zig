//! d2-bnftp-poller: the fetch-and-stage half of a multi-source BNFTP comparison
//! poller. It fetches files from several Battle.net sources and stages the bytes
//! on a shared volume; the compare / placement / divergence-report / commit step
//! is the pod-0 coordinator in entrypoint.sh.
//!
//! Reads a fetch-list (env FETCH_LIST, default "fetch-list"). Each non-blank,
//! non-comment line is "<class> <filename>":
//!   - class "d2":      fetched from all 5 d2 sources (useast/uswest/asia/europe/vegas)
//!   - class "forever": fetched from the "forever" source only
//! Each (source, filename) pair is one unit of work. The full pair list is sharded
//! by env SHARD_INDEX / SHARD_TOTAL (pair index % SHARD_TOTAL == SHARD_INDEX). For
//! each assigned pair bnftp.fetch() is called (retried up to 3x on an empty reply;
//! BNFTP occasionally RSTs) and the bytes are written to
//! <STAGE_DIR>/<source>/<filename>. A 0-byte result is never written. Exit is
//! nonzero if any pair in this shard failed all retries.
//!
//! std.fs is reworked under the 0.16 Io interface (needs an event loop); the
//! clientless package it links already uses libc directly for file I/O, so this
//! poller does the same for env and file writes.

const std = @import("std");
const bnftp = @import("bnftp");

const max_retries = 3;
const bnftp_port: u16 = 6112;

// libc bits (libc is linked because the bnftp module uses libc sockets).
extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
extern "c" fn write(fd: c_int, buf: [*]const u8, n: usize) isize;
extern "c" fn read(fd: c_int, buf: [*]u8, n: usize) isize;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
extern "c" fn usleep(usec: c_uint) c_int;

// A source is a logical origin. A named gateway resolves to a single host; the
// "vegas" pool has several raw IPs tried in order (first non-empty wins).
const Source = struct {
    name: []const u8,
    hosts: []const []const u8,
    product: []const u8,
};

// The same five gateways answer for every classic product; only the request's
// product 4CC changes, so each product-class reuses this gateway list.
fn gateways(comptime product: []const u8) [5]Source {
    return .{
        .{ .name = "useast", .hosts = &.{"useast.battle.net"}, .product = product },
        .{ .name = "uswest", .hosts = &.{"uswest.battle.net"}, .product = product },
        .{ .name = "asia", .hosts = &.{"asia.battle.net"}, .product = product },
        .{ .name = "europe", .hosts = &.{"europe.battle.net"}, .product = product },
        .{ .name = "vegas", .hosts = &.{ "158.115.218.65", "158.115.218.77", "158.115.218.106" }, .product = product },
    };
}

const d2_sources = gateways("D2XP");
const star_sources = gateways("STAR"); // StarCraft
const bw_sources = gateways("SEXP"); // Brood War
const war2_sources = gateways("W2BN"); // WarCraft II BNE
const war3_sources = gateways("WAR3"); // WarCraft III RoC
const w3xp_sources = gateways("W3XP"); // WarCraft III Frozen Throne

// fetch-list classes that fetch a filename from the 5 gateways under one product.
const ProductClass = struct { name: []const u8, sources: []const Source };
const product_classes = [_]ProductClass{
    .{ .name = "d2", .sources = &d2_sources },
    .{ .name = "star", .sources = &star_sources },
    .{ .name = "bw", .sources = &bw_sources },
    .{ .name = "war2", .sources = &war2_sources },
    .{ .name = "war3", .sources = &war3_sources },
    .{ .name = "w3xp", .sources = &w3xp_sources },
};

const forever_source = Source{
    .name = "forever",
    .hosts = &.{"connect-forever.classic.blizzard.com"},
    .product = "D2XP",
};

const Pair = struct {
    source: *const Source,
    filename: []const u8,
    attempts: usize,
    is_probe: bool,
};

fn out(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}

fn envOr(env: std.process.Environ, key: []const u8, dflt: []const u8) []const u8 {
    return std.process.Environ.getPosix(env, key) orelse dflt;
}

fn envUsize(env: std.process.Environ, key: []const u8, dflt: usize) usize {
    const v = std.process.Environ.getPosix(env, key) orelse return dflt;
    return std.fmt.parseInt(usize, std.mem.trim(u8, v, " \t\r\n"), 10) catch dflt;
}

fn writeFileZ(path: [*:0]const u8, data: []const u8) !void {
    const flags: c_int = @bitCast(std.posix.O{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true });
    const fd = open(path, flags, @as(c_uint, 0o644));
    if (fd < 0) return error.OpenFailed;
    defer _ = close(fd);
    var sent: usize = 0;
    while (sent < data.len) {
        const n = write(fd, data.ptr + sent, data.len - sent);
        if (n <= 0) return error.WriteFailed;
        sent += @intCast(n);
    }
}

fn readWholeFile(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    const cpath = try gpa.dupeZ(u8, path);
    const o_rdonly: c_int = @bitCast(std.posix.O{ .ACCMODE = .RDONLY });
    const fd = open(cpath.ptr, o_rdonly);
    if (fd < 0) return error.OpenFailed;
    defer _ = close(fd);
    var buf: std.ArrayList(u8) = .empty;
    var chunk: [64 * 1024]u8 = undefined;
    while (true) {
        const n = read(fd, &chunk, chunk.len);
        if (n < 0) return error.ReadFailed;
        if (n == 0) break;
        try buf.appendSlice(gpa, chunk[0..@intCast(n)]);
    }
    return buf.items;
}

// Fetch one (source, filename) with retry-on-empty. For a multi-host source the
// hosts are tried in order; the first that returns non-empty wins. Returns an
// empty slice if every host/attempt failed.
fn fetchPair(gpa: std.mem.Allocator, src: *const Source, filename: []const u8, attempts: usize, filetime_out: *u64) []u8 {
    var attempt: usize = 0;
    while (attempt < attempts) : (attempt += 1) {
        for (src.hosts) |host| {
            const bytes = bnftp.fetch(gpa, host, bnftp_port, src.product, filename, .{}, filetime_out) catch |err| {
                if (attempts > 1)
                    out("  {s}/{s} try {d}/{d} via {s}: error {s}\n", .{ src.name, filename, attempt + 1, attempts, host, @errorName(err) });
                continue;
            };
            if (bytes.len > 0) return bytes;
        }
        if (attempts > 1)
            out("  {s}/{s} try {d}/{d}: 0 bytes\n", .{ src.name, filename, attempt + 1, attempts });
    }
    return &.{};
}

pub fn main(init: std.process.Init.Minimal) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const env = init.environ;

    const list_path = envOr(env, "FETCH_LIST", "fetch-list");
    const stage_dir = envOr(env, "STAGE_DIR", "stage");
    const shard_index = envUsize(env, "SHARD_INDEX", 0);
    const shard_total = envUsize(env, "SHARD_TOTAL", 1);
    // Gentle pacing between fetches so a shard (especially the ~4k probe checks,
    // all against useast) never hammers a gateway into rate-limiting us. Slower is
    // fine. Tunable via FETCH_DELAY_MS; 0 disables.
    const delay_ms = envUsize(env, "FETCH_DELAY_MS", 200);

    if (shard_total == 0 or shard_index >= shard_total) {
        out("bad shard config: SHARD_INDEX={d} SHARD_TOTAL={d}\n", .{ shard_index, shard_total });
        std.process.exit(2);
    }

    out("d2-bnftp-poller: list={s} stage={s} shard={d}/{d}\n", .{ list_path, stage_dir, shard_index, shard_total });

    const text = readWholeFile(gpa, list_path) catch |e| {
        out("failed to read fetch-list {s}: {s}\n", .{ list_path, @errorName(e) });
        std.process.exit(2);
    };

    // Expand every "<class> <filename>" line into its (source, filename) pairs.
    // The flat pair order is stable (list order x source order), so the shard
    // split is deterministic across pods.
    var pairs: std.ArrayList(Pair) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        var it = std.mem.tokenizeAny(u8, line, " \t");
        const class = it.next() orelse continue;
        // filename is the remainder after the class token; BNFTP names can contain
        // spaces (e.g. "Diablo II.pdb"), so take the rest of the line, not one token.
        const rest = std.mem.trim(u8, line[class.len..], " \t");
        if (rest.len == 0) continue;
        const fname = try gpa.dupe(u8, rest);
        var matched = false;
        for (product_classes) |pc| {
            if (std.mem.eql(u8, class, pc.name)) {
                for (pc.sources) |*s| try pairs.append(gpa, .{ .source = s, .filename = fname, .attempts = max_retries, .is_probe = false });
                matched = true;
                break;
            }
        }
        if (matched) {
            // handled above
        } else if (std.mem.eql(u8, class, "forever")) {
            try pairs.append(gpa, .{ .source = &forever_source, .filename = fname, .attempts = max_retries, .is_probe = false });
        } else if (std.mem.eql(u8, class, "probe")) {
            // Speculative existence check across all five gateways, single try each:
            // most probes miss (0 bytes) so no retry. A hit flows through the same
            // compare/placement as a d2 file and is surfaced by collect as a find.
            for (&d2_sources) |*s| try pairs.append(gpa, .{ .source = s, .filename = fname, .attempts = 1, .is_probe = true });
        } else {
            out("skipping unknown class \"{s}\" for {s}\n", .{ class, fname });
        }
    }

    // Pre-create the per-source staging dirs this shard may touch.
    const cstage = try gpa.dupeZ(u8, stage_dir);
    _ = mkdir(cstage.ptr, 0o755);

    var processed: usize = 0; // real (d2/forever) pairs attempted by this shard
    var failed: usize = 0; // real pairs that produced no bytes (source not serving)
    var probe_checked: usize = 0;
    var probe_hit: usize = 0;

    // Per-file scratch: the fetched bytes (up to ~11MB per MPQ) and the path
    // strings live here and are released after each pair, so at most one file is
    // resident at a time. Without this, everything piles up in the run arena and
    // the shard's total bytes OOM the container.
    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();

    for (pairs.items, 0..) |p, idx| {
        if (idx % shard_total != shard_index) continue;
        if (p.is_probe) probe_checked += 1 else processed += 1;
        if (delay_ms > 0) _ = usleep(@intCast(delay_ms * 1000)); // pace every fetch, hit or miss
        defer _ = scratch.reset(.retain_capacity);
        const sa = scratch.allocator();

        var filetime: u64 = 0;
        const bytes = fetchPair(sa, p.source, p.filename, p.attempts, &filetime);
        if (bytes.len == 0) {
            // A probe miss is the expected case - stay quiet. A real 0-byte means the
            // source does not serve that file.
            if (!p.is_probe) {
                failed += 1;
                out("FAILED {s}/{s} 0 bytes\n", .{ p.source.name, p.filename });
            }
            continue;
        }

        const srcdir = try std.fmt.allocPrintSentinel(sa, "{s}/{s}", .{ stage_dir, p.source.name }, 0);
        _ = mkdir(srcdir.ptr, 0o755);
        const dst = try std.fmt.allocPrintSentinel(sa, "{s}/{s}/{s}", .{ stage_dir, p.source.name, p.filename }, 0);
        writeFileZ(dst.ptr, bytes) catch |werr| {
            if (!p.is_probe) failed += 1;
            out("FAILED {s}/{s}: write error {s}\n", .{ p.source.name, p.filename, @errorName(werr) });
            continue;
        };
        // Record Blizzard's last-write time in a sidecar so collect can build the
        // committed FILETIMES manifest (git does not preserve on-disk mtimes).
        const ftp = try std.fmt.allocPrintSentinel(sa, "{s}/{s}/{s}.ft", .{ stage_dir, p.source.name, p.filename }, 0);
        var ftbuf: [24]u8 = undefined;
        const fts = std.fmt.bufPrint(&ftbuf, "{d}", .{filetime}) catch "0";
        writeFileZ(ftp.ptr, fts) catch {};
        if (p.is_probe) {
            probe_hit += 1;
            out("PROBE HIT {s}/{s} {d} bytes\n", .{ p.source.name, p.filename, bytes.len });
        } else {
            out("ok {s}/{s} {d} bytes\n", .{ p.source.name, p.filename, bytes.len });
        }
    }

    // A 0-byte BNFTP reply means the source does not host that file (the classic
    // gateways each omit a different subset - Mac ver stubs, icons_STAR, per-region
    // bnserver.ini, the forever set, etc.). That is expected, not a shard failure:
    // collect only places sources that produced bytes. Only fail the shard if it
    // staged nothing at all, which signals a real connectivity/DNS problem.
    const staged = processed - failed;
    out("shard {d}/{d} done: {d} staged, {d} not served (of {d} real pairs); probes: {d} checked, {d} hit\n", .{ shard_index, shard_total, staged, failed, processed, probe_checked, probe_hit });
    // Only a total wipeout of the REAL fetches signals a connectivity/DNS problem;
    // probe misses are expected and never fail the shard.
    if (processed > 0 and staged == 0) std.process.exit(1);
}
