# Diablo II debug GUIDs (PDB / symbol identifiers)

Per-version CodeView **RSDS** debug GUIDs for the Diablo II binaries, plus the modern
live-service binaries. These are the identifiers a symbol server keys a PDB on: the
**symsrv key** is the GUID with the dashes removed followed by the age
(e.g. `4A206F288F5D4842B2A073B37F649ED8` + age `1` = `4A206F288F5D4842B2A073B37F649ED81`).

Extracted with no debugger/IDE - see [Method](#method). Nothing here is a binary; these
are just the public identifiers Blizzard embedded in the shipped executables.

## Game versions (from the retail patch MPQs)

Only the **1.11 - 1.14d retail** line shipped a debug directory. Everything earlier
(Classic 1.01-1.06, LoD 1.08-1.10, 1.00) and all betas (1.10b, 1.10s, 1.13a) are
debug-**stripped** - no GUID exists to record.

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
3. In each extracted PE, find the CodeView record: `52 53 44 53` (`RSDS`) + 16-byte GUID
   (mixed-endian) + 4-byte age + null-terminated `.pdb` path.

The live binaries' GUIDs were read the same way from their in-memory RSDS records; the Mac
build carries a Mach-O `LC_UUID` load command instead.

