const std = @import("std");

// d2-bnftp-poller: a sharded BNFTP re-fetch poller. Depends on the public
// d2-clientless package (pinned by commit in build.zig.zon) and imports its
// "bnftp" module to call bnftp.fetch(). Uses libc sockets (via clientless), so
// the executable links libc.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const clientless = b.dependency("clientless", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "d2-bnftp-poller",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    exe.root_module.addImport("bnftp", clientless.module("bnftp"));
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run the BNFTP re-fetch poller").dependOn(&run.step);
}
