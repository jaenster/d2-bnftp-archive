# Diablo II patch installers (official download server)

Blizzard's classic-games download server still serves every **released** Diablo II patch
installer by name over HTTP - verified live. Unlike BNFTP (which only serves the *latest*
auto-update MPQ), this hosts each historical version as a standalone installer.

## Endpoints

| edition | URL pattern |
|-|-|
| Classic (Diablo II) | `http://ftp.blizzard.com/pub/diablo2/patches/PC/D2Patch_<ver>.exe` |
| Expansion (LoD) | `http://ftp.blizzard.com/pub/diablo2exp/patches/PC/LODPatch_<ver>.exe` |

`ftp.blizzard.com` -> `download.blizzard.com` -> a CloudFront distribution over S3. It is
**name-only**: you can fetch any known key, but the bucket denies `ListObjects` and there is
no directory autoindex (any dir URL returns S3 `AccessDenied` / HTTP 403). There is no real
FTP server despite the hostname - port 21 is filtered and `ftp://` fails. A browser or
headless automation gets the same 403, so the file set can only be mapped by probing known
names (HTTP `206`/`200` = present, `403` = absent).

## Available versions (probed live)

### Classic - `D2Patch_<ver>.exe`

`101`, `103`, `104b`, `105`, `105b`, `106`, `106b`, `108`, `109`, `109b`, `109d`, `110`, `111`, `111b`, `112a`, `113c`, `113d`, `114a`, `114b`, `114c`, `114d`

### Lord of Destruction - `LODPatch_<ver>.exe`

`110`, `111`, `111b`, `112a`, `113c`, `113d`, `114a`, `114b`, `114c`, `114d`

## What is NOT hosted

- **Betas / interim builds.** Only the final sub-version of each line is kept - e.g. `113c`
  and `113d` are present but `113`, `113a`, `113b` are not; `109d` but not `109a`/`109c`;
  `104b` but not `104`/`104a`/`104c`. Beta installers (`110b`, `110s`, `113a_Beta`) exist
  only in third-party archives, never on Blizzard's server.
- **Anything past `1.14d`.** `114e` / `115` / `116` / `2.0` all 403 on both directories -
  no unreleased patch is staged.
- **The LoD line only reaches back to `110`** (no `108`/`109` under `diablo2exp`).

## Related

- [`PDB-GUIDS.md`](PDB-GUIDS.md) - per-version debug GUIDs, extracted from the MPQ payload
  inside these installers.
- Each installer is a stub PE with a real **MPQ appended at `0x29000`** (`0x23000` for 1.08);
  the game binaries are `ENCRYPTED+FIX_KEY` inside, extracted with StormLib by name. That is
  how the per-version GUIDs (and the confirmation that Classic uses `GameD2.pdb` vs LoD's
  `Game.pdb`) were obtained.

## Provenance & legal

These installers are **Blizzard Entertainment's**, served from Blizzard's own public download
server. This file only documents the public URLs and which versions resolve; no binaries are
mirrored here. All trademarks and copyrights belong to Blizzard Entertainment.
