# Diablo II debug GUIDs (PDB / symbol identifiers)

Per-version CodeView **RSDS** debug GUIDs for the Diablo II binaries, plus the modern
live-service binaries. These are the identifiers a symbol server keys a PDB on: the
**symsrv key** is the GUID with the dashes removed followed by the age
(e.g. `4A206F288F5D4842B2A073B37F649ED8` + age `1` = `4A206F288F5D4842B2A073B37F649ED81`).

Extracted with no debugger/IDE - see [Method](#method). Nothing here is a binary; these
are just the public identifiers Blizzard embedded in the shipped executables.

## Game versions (from the retail patch MPQs)

The **1.11 - 1.14d retail** line carries a CodeView **RSDS** record, which is what the
table below lists. Everything from **Classic 1.04b / LoD 1.07 through 1.10** carries an
older VC6 **NB10** record instead - a 32-bit signature rather than a GUID, but the same
kind of symbol-server key. Those are in [NB10 records](#nb10-records-classic-104b--lod-110)
below and in `PDB-NB10.tsv`. Only **1.00 - 1.03** is genuinely debug-stripped.

| version | channel | module | pdb | guid | age |
|-|-|-|-|-|-|
| 1.11 | LoD | D2Game | `D2Game.pdb` | `D9D62110-5BF1-4E99-8D04-285C9228DD39` | 1 |
| 1.11 | LoD | D2Common | `D2Common.pdb` | `FADF79A7-091C-4E66-A6F0-0EB2DC160B31` | 1 |
| 1.11 | LoD | D2Client | `D2Client.pdb` | `86EA0019-E02D-4BB0-BFC1-7C705B3F1480` | 1 |
| 1.11 | LoD | D2VidTst | `D2VideoTest.pdb` | `CE4E6664-4A7E-4020-9541-98C398402908` | 1 |
| 1.11 | LoD | Storm | `Storm.pdb` | `8ABB9143-CBA1-40DB-84B4-99B85DBD0EA1` | 1 |
| 1.11b | LoD | D2Game | `D2Game.pdb` | `E6FE10E5-4A40-4542-9759-77DFA688C854` | 1 |
| 1.11b | LoD | D2Common | `D2Common.pdb` | `216D34FD-1F1F-4060-82FA-FBAAD4FC6093` | 1 |
| 1.11b | LoD | D2Client | `D2Client.pdb` | `39B800B6-50F4-4DF4-9CF0-DF3FCF61BAF7` | 1 |
| 1.11b | LoD | D2VidTst | `D2VideoTest.pdb` | `4C1CA9C6-CDDF-41EC-B098-C7FBBB7A36E5` | 1 |
| 1.11b | LoD | Storm | `Storm.pdb` | `57605458-22E0-4CF3-B10A-1F21F774BD53` | 1 |
| 1.12a | LoD | D2Game | `D2Game.pdb` | `8CB3BBBF-4604-46F3-98AD-5687C97C41C8` | 1 |
| 1.12a | LoD | D2Common | `D2Common.pdb` | `A14625E0-CB39-4411-9FF8-C2FB710A603A` | 1 |
| 1.12a | LoD | D2Client | `D2Client.pdb` | `1E8B46C5-A54F-4D69-8CA4-A91470CA003B` | 1 |
| 1.12a | LoD | D2VidTst | `D2VideoTest.pdb` | `A831218D-B748-4F0B-BDA1-DBAC410CD118` | 1 |
| 1.12a | LoD | Storm | `Storm.pdb` | `8C3171B2-07BB-4D25-A5DD-E2BA5911E24F` | 1 |
| 1.13c | LoD | D2Game | `D2Game.pdb` | `1FB8F927-1C31-4C2C-9D4E-3381A074B8AE` | 1 |
| 1.13c | LoD | D2Common | `D2Common.pdb` | `AE08FBF0-756C-40F6-80BD-235AC08600BC` | 1 |
| 1.13c | LoD | D2Client | `D2Client.pdb` | `D9324789-E125-4DF6-8E4F-FEEF92FA0495` | 1 |
| 1.13c | LoD | D2VidTst | `D2VideoTest.pdb` | `48DB461F-B17F-4AC6-94CE-AE5CA5CB575B` | 1 |
| 1.13c | LoD | Storm | `Storm.pdb` | `91C1C36E-A2D5-42D6-9AB5-BC2FB02F558E` | 1 |
| 1.13d | LoD | D2Game | `D2Game.pdb` | `C0486A10-DE80-4D9E-8B3D-55CD73B3DCFE` | 1 |
| 1.13d | LoD | D2Common | `D2Common.pdb` | `6ED6F6DD-ED95-4926-A45A-94E579E38923` | 1 |
| 1.13d | LoD | D2Client | `D2Client.pdb` | `159A0357-22E1-440E-A9A1-D9FFC4C0C209` | 1 |
| 1.13d | LoD | D2VidTst | `D2VideoTest.pdb` | `56EA285F-D492-4911-B9C3-C4ABFD4A589C` | 1 |
| 1.13d | LoD | Storm | `Storm.pdb` | `30977DDC-E236-40D6-AB6F-2742AB7C309B` | 1 |
| 1.14a | LoD | Game | `Game.pdb` | `2FC1ACE5-FE88-43D9-85CC-324A7753F9BD` | 1 |
| 1.14b | LoD | Game | `Game.pdb` | `782B6B6C-A3B7-4719-851C-AD0C1AC6FC32` | 1 |
| 1.14c | LoD | Game | `Game.pdb` | `AD0F8C69-690B-4CDE-8A92-5368AFA617F3` | 1 |
| 1.14d | LoD | Game | `Game.pdb` | `4A206F28-8F5D-4842-B2A0-73B37F649ED8` | 1 |
| 1.14d | LoD | BlizzardError | `BlizzardError.pdb` | `0FBB4E71-0922-46E3-98F4-0776A7668130` | 1 |
| 1.14d | LoD | SystemSurvey | `SystemSurvey.pdb` | `E2313632-FB73-46EA-A07F-913701EB8F5A` | 1 |
| 1.14d | Classic | Game | `GameD2.pdb` | `333AEFA3-458E-4BE6-85C3-139100C60794` | 1 |

Notable: the **Classic** (`D2DV`) 1.14d `Game.exe` uses **`GameD2.pdb`**, while the
**LoD** (`D2XP`) build uses `Game.pdb` - two distinct binaries at the same version.

## Live service / tooling binaries

| binary | guid | age | build tree |
|-|-|-|-|
| D2R.exe 2.4.0 (debug) | `DCC257CB-DDFD-4211-89AC-F3D49F2A9818` | 1 | `D:\jenkins\workspace\diablo2_pipeline` |
| CheckRevision.dll (2020) | `C52227F8-D058-4D0B-A817-FA7DC8105AE6` | 2 | `D:\git\service-cpp-bnet-legacy` |
| d2staged.exe | `714EA741-F12A-4E1E-9364-DCB7F6CA750E` | 2 | `D:\git\service-cpp-classic2` |
| d2stagea.dll | `1B971FE4-4A6E-44A9-A9AD-2962797B7DA2` | 2 | `D:\git\service-cpp-classic2` |
| d2stageb.dll | `B951A869-064C-4FEC-9E48-B4F2EC173910` | 2 | `D:\git\service-cpp-classic2` |
| d2stagec.dll | `8D46AE05-7858-4BE8-A12C-BB7D2D2F780F` | 2 | `D:\git\service-cpp-classic2` |
| DiabloII (Mac 1.14d) | `EFC9C6C5-8BB4-3FBA-8803-7DAB041CCD20` | - | `/Users/bclemetson/dev/diablo2` |

## Build-path provenance

The embedded build paths track how the project moved over time:

- 1.11 `C:\Projects\Diablo2` -> 1.11b `C:\Src\Diablo2` -> 1.12a `C:\Projects\Diablo2\trunk`
  -> 1.13c `X:\trunk\Diablo2` -> 1.13d `C:\projects\diablo2\trunk` -> 1.14a-c
  `c:\Users\cgenova\...` -> 1.14d `d:\diablo2\Diablo2`.
- Dev home dirs that leaked: **cgenova** (1.14a-c Game), **jtouton** (SystemSurvey),
  **bclemetson** (the entire Mac 1.14d build).
- Modern services build from **`service-cpp-classic2`** (the `d2stage*` IX86ExtraWork set)
  and **`service-cpp-bnet-legacy`** (CheckRevision); D2R from a Jenkins CI tree.

## Method

No Ghidra/IDA needed for the patch set:

1. Each `LODPatch_<ver>.exe` / `D2Patch_<ver>.exe` is a stub PE with a real **MPQ appended
   at `0x29000`** (`0x23000` for 1.08). Find the `MPQ\x1a` whose headerSize is 32 and slice
   `archiveSize` bytes.
2. Open with StormLib (it decrypts the `(listfile)`); the game files are `ENCRYPTED+FIX_KEY`,
   so extract the module set **by name** (`Game.exe`, `D2Game.dll`, `D2Common.dll`,
   `D2Client.dll`, `D2VidTst.exe`, `Storm.dll`, ...). Older patches ship a near-empty
   listfile, but the files are still present as unnamed-but-decryptable-by-name blocks.
3. In each extracted PE, walk the **debug data directory** (entry 6) and read every
   `IMAGE_DEBUG_TYPE_CODEVIEW` record. Two encodings appear, and looking for only one is
   how the pre-1.11 line got mis-recorded as stripped for so long:
   - `52 53 44 53` (`RSDS`, VC7+) + 16-byte GUID (mixed-endian) + 4-byte age + `.pdb` path.
   - `4E 42 31 30` (`NB10`, VC6) + 4-byte offset + 4-byte **signature** + 4-byte age +
     `.pdb` path. The symsrv key is the signature and age in hex, e.g. signature
     `0x3AF879CA` age `1` -> `3AF879CA1`.

   Grepping the file for the literal string `RSDS` finds the first kind and silently misses
   the second; the debug directory finds both, and finds them at their real offsets rather
   than wherever those four bytes happen to occur.

The live binaries' GUIDs were read the same way from their in-memory RSDS records; the Mac
build carries a Mach-O `LC_UUID` load command instead.


## Additions from the Classic `D2Patch` installers

The Classic (`D2DV`) installers yielded `Fog.pdb` (not in the LoD extract) and a distinct
`GameD2.pdb` per 1.14 build. The other DLLs are byte-identical to LoD (same GUID) - only the
launcher `Game.exe` differs between Classic (`GameD2.pdb`) and LoD (`Game.pdb`).

| version | module | pdb | guid |
|-|-|-|-|
| 1.11 | Fog | `Fog.pdb` | `189D172D-A8F2-4D2E-9148-95FFE61CD683` |
| 1.11b | Fog | `Fog.pdb` | `8149173F-BC0B-463C-AA13-C944E6D9E7F1` |
| 1.12a | Fog | `Fog.pdb` | `4D404599-F315-4B89-9E05-757597DB0D25` |
| 1.13c | Fog | `Fog.pdb` | `382F7679-A0A4-4023-B4FF-9A71AE0804D1` |
| 1.13d | Fog | `Fog.pdb` | `9B527A84-4CF8-48CE-8DF8-6B5CD450B9BE` |
| 1.13c | D2Lang | `D2Lang.pdb` | `A534DF18-82E5-4839-9637-259F4107C029` |
| 1.14a | Game (Classic) | `GameD2.pdb` | `138DAC7D-82F9-43D7-A65C-120D90DA93F6` |
| 1.14b | Game (Classic) | `GameD2.pdb` | `B82E0D2D-8CB0-4D96-A328-DCAA5EB5AD4D` |
| 1.14c | Game (Classic) | `GameD2.pdb` | `345B5CC5-B5EE-4CF1-8D58-CD8EB7062C48` |


## NB10 records (Classic 1.04b - LoD 1.10)

383 records across 20 builds, one per shipped module. The full set is in
[`PDB-NB10.tsv`](PDB-NB10.tsv); this is the index. `symsrv key` is the signature and age
concatenated in hex, which is the directory a symbol server keys the PDB on:
`Fog.pdb/3AF6E1D91/Fog.pdb`.

The count is 19 per build almost everywhere, because that is how many modules a D2 install
of that era had. LoD 1.09d is 18: `D2Net.dll` in that build alone has no debug directory.
Every module changed between 1.09b and 1.09d, so it is not a matter of one file being left
untouched - that single link dropped the record and no other did.

| edition | version | modules | build tree(s) |
|-|-|-|-|
| Classic | 1.04b | 19 | `C:\D2\Release` |
| Classic | 1.04c | 19 | `C:\D2\Release` |
| Classic | 1.05 | 19 | `C:\D2\Release` |
| Classic | 1.05b | 19 | `C:\D2\Release` |
| Classic | 1.06 | 19 | `C:\D2\Release` |
| Classic | 1.06b | 19 | `C:\Projects\D2106\Release`, `C:\D2\Release` |
| Classic | 1.08 | 19 | `C:\Projects\Diablo2\Release` |
| Classic | 1.09 | 19 | `C:\Projects\Diablo2\Release` |
| Classic | 1.09b | 19 | `C:\Projects\D2109r-pin\Diablo2\Release`, `C:\Projects\Diablo2\Release` |
| Classic | 1.09d | 19 | `C:\Src\Diablo2\Release`, `C:\Projects\Diablo2\Release` |
| Classic | 1.10 | 19 | `C:\projects\D2\head\Diablo2\Release` |
| LoD | 1.07 | 19 | `C:\Projects\Diablo2\Release`, `D:\D2\Release` |
| LoD | 1.07_Beta | 23 | `D:\D2\Release`, `C:\Projects\Diablo2\Release`, + three debug trees |
| LoD | 1.08 | 19 | `C:\Projects\Diablo2\Release` |
| LoD | 1.09 | 19 | `C:\Projects\Diablo2\Release` |
| LoD | 1.09b | 19 | `C:\Projects\D2109r-pin\Diablo2\Release`, `C:\Projects\Diablo2\Release` |
| LoD | 1.09d | 18 | `C:\Src\Diablo2\Release`, `C:\Projects\Diablo2\Release` |
| LoD | 1.10b_Beta_1 | 19 | `C:\Src\Diablo2\Release` |
| LoD | 1.10f | 19 | `C:\projects\D2\head\Diablo2\Release` |
| LoD | 1.10s_Beta_2 | 19 | `C:\Src\Diablo2\Release` |

### What the build trees say

The provenance chain now starts seven years earlier than the RSDS section could show it:

- **`C:\D2\Release`** builds everything from 1.04b to 1.06 - one flat tree, no branch in
  the path, which is what a small team shipping patches off trunk looks like.
- **`C:\Projects\D2106\Release`** appears in 1.06b for a subset of modules: a
  version-named branch cut for that patch while trunk moved on. `C:\Projects\D2109r-pin`
  in 1.09b is the same pattern with the branch name saying so out loud - **pin**.
- **`C:\Projects\Diablo2\Release`** takes over from 1.08 and is still the tree 1.11 ships
  from, so the RSDS-era `C:\Projects\Diablo2` in the table above is not a new tree; it is
  this one, six years old by then.
- **`C:\projects\D2\head\Diablo2\Release`** is 1.10 in both editions - the only place a
  literal `head` shows up, on both sides of the Classic/LoD split at once.
- LoD 1.07 splits: 18 modules from `C:\Projects\Diablo2\Release` and **Storm alone** from
  `D:\D2\Release`. Storm was a shared library built elsewhere and dropped in, which is
  exactly how `\D2\3rdParty\STORM\SOURCE\*.CPP` in the beta's debug build describes it.

### The LoD beta (2001-04) shipped its debug DLLs

The 2001 Lord of Destruction beta CD (`D2XBETA.iso`) installs three modules built from
debug trees, alongside the release set:

| module | symsrv key | pdb path |
|-|-|-|
| `Stormd.dll` | `3AD88D071` | `C:\D2\Debug\StormD.pdb` |
| `D2CMPd.dll` | `3ADB2A338` | `D:\D2\Obj\Debug-Expansion\D2Cmp\D2CMPd.pdb` |
| `TelnetD.dll` | `3AC3AE5E2` | `D:\D2\Obj\Debug-Expansion\TelnetD\TelnetD.pdb` |

`Obj\Debug-Expansion` names the configuration: an expansion-only debug target, distinct
from the plain `Debug` that Storm used. Nothing in the release set imports any of the
three; `D2CMPd` and `TelnetD` both link `StormD.dll`, and `D2CMPd` additionally links the
**release** `Fog.dll`. So they are a debug set meant to be swapped in over their release
namesakes, left on the disc by accident.

`TelnetD` imports `WS2_32` and `MSWSOCK` and exports exactly `TelnetStart`, `TelnetStop`
and `TelnetSendString`. It registers a window class `TELNETDCLASS`, runs a worker thread
("Telnet worker thread startup"), stamps itself `STARTUP version(Apr 13 2001 17:04:01)`,
and logs to `telnetd.log` under `c:\temp`. It is a real listening TCP console for the
running game - the debug channel the developers watched a build on - and no shipped D2
binary references it.

Because they are debug builds they carry `__FILE__` assert strings, which name the source
files the release binaries only hint at:

- `\D2\source\D2CMP\SRC\` - `CelCmp` `Codec` `FastCmp` `FindTiles` `LRUCache` `PalShift`
  `Palette` `Raw` `SubTile` `TileCache` `TileProjects` `Tilecmp` `CelDataHash` `Count`
  `DrwCntxt` `GfxHash` `SpriteCache` `TileLib` (18 translation units)
- `\D2\3rdParty\STORM\SOURCE\` - `SBLT` `SBMP` `SBig` `SCMD` `SCODE` `SCOMP` `SDLG`
  `SDRAW` `SERR` `SEVT` `SFILE` `SGDI` `SLOG` `SMEM` `SMSG` `SNET` `SREG` `SRGN` `SSTR`
  `STORM` `STRANS` `SVID` (22 translation units)
- `\D2\source\TelnetD\` - `TelnetD.cpp`, `TND_IO.CPP`
- one more that belongs to neither: `\d2\source\d2hell\src\archive.cpp`, referenced from
  `D2CMPd`. **`D2Hell`** is a source directory no shipped module names.

### The beta D2Game.dll is retail 1.07 minus 21 bytes

`lod/1.07_Beta/D2Game.dll` and `lod/1.07/D2Game.dll` are both 999,479 bytes and carry the
**same** symsrv key `3AF879CA1` - the same PDB, so the same compile. They differ in 21
bytes total, scattered between `0x1919` and `0x7da88`. The beta build is a hand-patched
1.07 rather than a separate branch.

Both also carry `C:\Projects\Diablo2\Release\D2Game.pdb` while every other module in the
beta says `D:\D2\Release` - D2Game came from the retail tree and the rest did not.
