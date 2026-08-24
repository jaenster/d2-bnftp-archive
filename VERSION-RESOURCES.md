# What a Diablo II binary says about itself

A third identity source, alongside the RSDS and NB10 debug records in
[`PDB-GUIDS.md`](PDB-GUIDS.md): the Win32 **VS_VERSIONINFO** resource. It is authored by
Blizzard, shipped in every release, and - because nobody maintains it - it preserves names
the build long since stopped using.

Full sweep in [`VERSION-RESOURCES.tsv`](VERSION-RESOURCES.tsv); the parser that produced it
is [`tools/verinfo.py`](tools/verinfo.py). **211 of ~1,100 archived binaries carry one.**
Most D2 modules ship without it: `D2Common`, `D2Game`, `D2Net`, `Fog`, `D2Win`, `D2Lang`,
`D2gfx`, `D2Multi`, `Bnclient`, `TelnetD` and the renderers have no version resource at all.
`Game.exe` (43 builds), `BNUpdate.exe` (40), `Storm.dll` (36) and `D2Client.dll` (23) do.

Read it properly, not by grepping. Each node is
`{wLength, wValueLength, wType, szKey (UTF-16, NUL), pad, Value, Children}` with every member
4-byte aligned. A scan for the literal `InternalName` finds the key but has to guess where the
value ends, and these strings are short enough that being one character out changes the answer.

## Game.exe FileVersion is the exact build number

The one field that is maintained. It pins each release to a build and settles which beta is
which:

| version | Classic | LoD |
|-|-|-|
| 1.00 | `1, 0, 0, 1` | - |
| 1.02 / 1.03 | `1, 0, 2, 0` / `1, 0, 3, 0` | - |
| 1.04b / 1.04c | `1, 0, 4, 1` / `1, 0, 4, 2` | - |
| 1.05 / 1.05b | `1, 0, 5, 0` / `1, 0, 5, 1` | - |
| 1.06, 1.06b | `1, 0, 6, 0` (both) | - |
| 1.07 | - | `1, 0, 7, 0` |
| **1.07 Beta** | - | `1, 0, 7, 0` |
| 1.08 | `1, 0, 8, 28` | `1, 0, 8, 28` |
| 1.09 / 1.09b / 1.09d | `1, 0, 9, 19` / `20` / `22` | same |
| **1.10b Beta 1** | - | `1, 0, 10, 9` |
| **1.10s Beta 2** | - | `1, 0, 10, 10` |
| 1.10 / 1.10f | `1, 0, 10, 39` | `1, 0, 10, 39` |
| 1.11 / 1.11b | `1, 0, 11, 45` / `46` | same |
| 1.12a | `1, 0, 12, 49` | same |
| **1.13a Beta** | - | `1, 0, 13, 55` |
| 1.13c / 1.13d | `1, 0, 13, 60` / `64` | same |
| 1.14a-d | `1.14.0.64` .. `1.14.3.71` | same |

Three things fall out:

- The **1.07 beta's `Game.exe` reports the same build as retail 1.07**, which agrees with its
  `D2Game.dll` being retail 1.07's with 21 bytes changed (see PDB-GUIDS.md).
- The two 1.10 betas are builds **9** and **10**; shipping 1.10 is build **39**. Thirty builds
  between the second public beta and release.
- **1.14a is `1.14.0.64` - build 64 is 1.13d's build.** The 1.14 renumbering carried the old
  build counter straight over, so 1.14a was cut from the 1.13d tree.
- Classic and LoD share a build number at every version from 1.08 on. One tree, two products.

## Names the resource preserves that the filename lost

| version | file | InternalName | OriginalFilename |
|-|-|-|-|
| classic 1.00 (and 1.00 Beta .. 1.10s) | `D2Client.dll` | `D2` | `D2.exe` |
| classic 1.00, LoD 1.07 Beta | `D2Server.dll` | `D2SERVE` | `D2.exe` |
| classic 1.00 Beta | `Diablo II.exe` | `Diablo 2` | `Diablo 2.exe` |
| classic 1.00 Beta | `SETUP.EXE` | `Install` | `Install.exe` |
| LoD 1.07 Beta | `Stormd.dll` | *(empty)* | `Storm.dll` |
| classic/LoD 1.14a-d | `Game.exe` | `Diablo II : Lord of Destruction` | `Diablo II.exe` |

- **`D2Client.dll` says it is `D2.exe`, in all 23 builds that carry the resource** - 1.00 through
  1.10s, Classic and LoD, never updated, `FileVersion` frozen at `0.01` the whole way.
  `D2Server.dll` says `D2.exe` too. Both were cut from one project template called **D2**, and
  D2Client is the half that kept the original executable's identity: the game was one program
  before it was a launcher plus a client DLL.
- **`D2SERVE`** is the D2Server project's own name for itself. Note this establishes the project
  name only - a `D2SERVE.EXE` string also sits in the DLL's `.data`, but nothing here proves an
  executable of that name hosted it.
- **`Stormd.dll` declares `OriginalFilename: Storm.dll`** with no InternalName - it is built to be
  dropped in over the release Storm, which is how the beta's debug set was meant to be used.
- `ProductName` on `Game.exe` reads `Blizzard North Diablo II` up to 1.13d and plain `Diablo II` /
  `Diablo II : Lord of Destruction` from 1.14a. Blizzard North was gone by then.

## What to harvest from a new binary

In priority order, all from the PE itself, no debugger needed:

1. **Debug directory** (data directory 6) - every `IMAGE_DEBUG_TYPE_CODEVIEW` record. `RSDS`
   (VC7+, GUID+age) and `NB10` (VC6, signature+age). Both are symbol-server keys. See
   PDB-GUIDS.md; grepping for the string `RSDS` misses the entire pre-1.11 line.
2. **VS_VERSIONINFO** - this document.
3. **`__FILE__` assert strings** - every release D2 build carries ~370 source paths.
4. **MSVC RTTI type descriptors** (`.?AV` / `.?AU`) - real C++ class names with template
   arguments intact, 38 per build at 1.00 rising to 80 at 1.14d.
5. **Export tables** - D2 exports by ordinal, but `QueryInterface` shows up by name on the
   modules that hand back a vtable (`D2Server`, `D2Multi`), and the Mac PowerPC PEF builds
   name far more.
