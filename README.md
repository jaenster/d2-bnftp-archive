# Battle.net classic BNFTP archive (Diablo / Diablo II)

A snapshot of **every file Blizzard's classic-games login servers serve over BNFTP** - the
unauthenticated Battle.net File Transfer protocol - captured by live-probing `*.battle.net:6112`
in 2026.

BNFTP is protocol selector `0x02`: you open a TCP connection to a Battle.net server, send `0x02`,
then a file request, and the server streams the file back. **No account, no CD-key, no
authentication.** It's how the classic client fetches its version-check module, anti-cheat
modules, the gateway list, channel icons, and the ToS. Everything here is what came back.

Captured with our clientless BNFTP client (`bnftp-probe`) while reverse-engineering the classic
Battle.net protocol. The protocol details - selectors, request/reply framing, the file namespace,
and what's still live vs. retired - are in [`BNETDOCS-REFERENCE.md`](BNETDOCS-REFERENCE.md).
Integrity hashes for every file are in [`SHA256SUMS`](SHA256SUMS).


## Why this exists

These files are the ground truth for anyone implementing a classic-Battle.net-compatible server
(PvPGN-style), studying the version-check / anti-cheat handshake, or preserving the classic
Battle.net platform. They're served publicly and unauthenticated by Blizzard's own servers; this
is a stable, hash-verified copy so you don't have to re-probe live infrastructure to get them.


## What's here

All files are under [`files/`](files/).

### Version-check modules

The MPQs Blizzard sends to run `CheckRevision` - the client hashes game files against a formula
and returns a checksum + version. The server names one of the `ver-*` stubs in its challenge.

| file | game |
|-|-|
| `CheckRevision.mpq` | Diablo II |
| `CheckRevisionD1.mpq` | Diablo I |
| `ver-IX86-0`...`ver-IX86-7.mpq` | version stubs, Windows (x86), indices 0-7 |
| `ver-PMAC-0.mpq` / `ver-XMAC-0.mpq` / `ver-OSXI-0.mpq` | version stubs, PowerPC / Intel Mac / OSX-Intel |

### Anti-cheat modules

Blizzard's per-session anti-cheat ("Warden"-lineage) modules - the server picks one of ~20 by
index each login. `lockdown` is the Windows family; `psistorm` is the Mac family.

| family | platform | files |
|-|-|-|
| `lockdown-IX86-00`...`19.mpq` | Windows (x86) | 20 |
| `psistorm-PMAC-00`...`19.mpq` | PowerPC Mac | 20 |
| `psistorm-XMAC-00`...`19.mpq` | Intel Mac | 20 |

### Game auto-update MPQs

The patch/update MPQs the server offers per product x platform (the `_1xx_114d` / `_108_109`
suffix is the version range they bridge).

| product | meaning | platforms present |
|-|-|-|
| `D2DV_*_1xx_114d.mpq` | Diablo II | IX86, XMAC |
| `D2XP_*_1xx_114d.mpq` | Diablo II: Lord of Destruction | IX86, XMAC |
| `DRTL_*_108_109.mpq` | Diablo I (retail) | IX86, PMAC |
| `DSHR_*_108_109.mpq` | Diablo I (shareware) | IX86, PMAC |

### Server config, icons, ToS

| file | what |
|-|-|
| `bnserver.ini`, `bnserver-D2DV.ini`, `bnserver-connect-forever.ini` | gateway/server lists (region -> hostname/zone) |
| `icons.bni`, `icons_STAR.bni`, `icons_SEXP.bni` | channel/user icon packs |
| `tos*.txt` | Terms of Service, 9 languages (USA, BRA, DEU, ESP, FRA, ITA, JPN, POL, default) |


## Verifying

```sh
cd files && shasum -a 256 -c ../SHA256SUMS
```


## What is NOT served

Product 4CCs probed - dead / no BNFTP patch:
- DIAB (Diablo 1 beta), DTST (Diablo 1 stress), D2ST (Diablo 2 stress), W3DM (WC3 demo): server holds silent / retired
- StarCraft / Brood War / WarCraft II (STAR/SEXP/W2BN): connect + auth work, but their version-check returns 0x102 = no BNFTP game patch served
- WAR3 / W3XP: NLS-auth only, so the MPQ-name oracle cannot enumerate them (not old-SID)
- No undocumented legacy 4CCs (BNET/TEST/BETA/BLIZ/ADMN/RATS/...): all dead

Filenames probed - confirmed absent (0-byte / not hosted):
- IX86ExtraWork.mpq, any Warden / scan.dll module (the 1.14 anti-cheat file the client references is not on BNFTP)
- news / ad / version text
- any .pdb or debug symbol
- path traversal (../, absolute paths): all return 0 bytes
- ToS beyond the 9 present: no KOR/CHN/TWN/GBR/RUS (exactly the official D2 localizations)

Host-specific gaps - connect-forever.classic.blizzard.com (the parked global gateway) omits: CheckRevision.mpq (D2), D2 _1xx_114d patches, psistorm-XMAC / psistorm-IX86, lockdown-XMAC/PMAC, ver-*-1..7, icons_STAR/SEXP. It serves the Diablo-1 + PowerPC-Mac set instead.

Protocol selectors probed - dead / gated:
- 0x03 Telnet chat: retired, silent
- 0x04 MCP, 0x06 interserver, 0x81: silent hold, IP-gated


## Keeping this current

The files under `files/` are re-fetched by a multi-source Kubernetes poller
(`d2-bnftp-poller`) on a weekly schedule. It builds the
[d2-clientless](https://github.com/jaenster/d2-clientless) BNFTP client and fetches every file in
[`fetch-list`](fetch-list) from several live Battle.net sources, then compares and commits any
changes. It runs as a 3-shard Indexed Job (one pod per node, so three distinct egress IPs) that
fetches `(file, source)` pairs in parallel; a coordinator then compares the results and places
them.

Each `fetch-list` line is `<class> <filename>`:

- `d2` files are fetched from all five D2 sources - the named gateways
  `useast` / `uswest` / `asia` / `europe` (product D2XP) plus `vegas`, the unnamed Las Vegas
  gateway IP pool - and compared byte for byte.
- `forever` files are fetched only from `connect-forever.classic.blizzard.com`, which serves the
  Diablo-1 + PowerPC-Mac legacy set.

Placement:

- A `d2` file that is byte-identical across all sources is written to the canonical path
  `files/<filename>`.
- A `d2` file that differs between sources is written per source to `files/<source>/<filename>`
  (for every source), and the canonical copy is removed.
- `forever` files are always written to `files/forever/<filename>`.

`SHA256SUMS` is regenerated recursively over `files/**` (a diff there is the diff of the archive).
[`REALM-DIVERGENCE.md`](REALM-DIVERGENCE.md) lists every file that is not in the canonical
`files/` - i.e. the per-source divergent files and the legacy set - with its per-source sha256.
`LAST-FETCHED.txt` records when the pipeline last ran. If nothing changed, it commits nothing. The
poller streams its progress and any divergences to a Discord webhook.


## Provenance & legal

These files are **Blizzard Entertainment's**, retrieved verbatim from Blizzard's own public,
unauthenticated BNFTP servers (`*.battle.net:6112`, protocol `0x02`). They are mirrored here for
preservation, research, and classic-Battle.net-server interoperability. No files were modified. All
trademarks and copyrights belong to Blizzard Entertainment; this archive is not affiliated with or
endorsed by Blizzard. If you are a rights holder and want something removed, open an issue.
