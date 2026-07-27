# Battle.net classic - BNCS / BNFTP reference (live-probed 2026)

Captured while reverse-engineering the OG 1.00 `D2Server.dll` and probing live
`*.battle.net:6112` with `tools/bnftp-probe`. Files referenced here are stored
next to this doc in `realmd-data/bnftp/`.

## Connection protocol selectors (first byte sent on a 6112 TCP connection)

| byte | protocol | live? (probed useast.battle.net) |
|-|-|-|
| 0x01 | BNCS (game/client binary) | LIVE - server greets with `SID_NULL` = `FF 00 04 00` |
| 0x02 | BNFTP (file transfer, unauthenticated) | LIVE - what we enumerate below |
| 0x03 | Telnet chat (raw line-based) | **DEAD** - silence (Blizzard retired it) |
| 0x04 | MCP (realm; client->MCP after a realm token) | client-speaks-first; bare selector = silent hold; almost certainly IP-gated |
| 0x06 | interserver sync (unconfirmed guess) | silent hold; needs valid first packet + likely server-IP allowlist |
| 0x81 | unknown | silent hold |

Knock result: the server holds EVERY connection open silently and never resets
on bad input (even `0x01` + a bad msgid just holds), so there is no reset/response
oracle - `0x04/0x06/0x81` can't be probed blind. These are the same server<->server
surfaces `D2Server.dll` uses (GS<->MCP), gated by the `cs.ini` accept-list model.

## Product IDs (4CC; sent byte-reversed on the wire) + live status

From bnetdocs/document/12 + our 4CC-validity oracle (request a universal file /
read `SID_AUTH_INFO` under the 4CC: recognised -> `id=0x50` + a named ver MPQ;
unrecognised/garbage -> no reply at all).

| product | 4CC | version | verbyte | live (old-auth)? |
|-|-|-|-|-|
| Telnet/Chat | CHAT | - | 0x01 | LIVE (binary chat-bot code; serves shared files only) |
| StarCraft Shareware | SSHR | 1.12.0.0 | 0xA5 | LIVE |
| StarCraft Japanese | JSTR | 1.12.0.0 | 0xA9 | LIVE |
| StarCraft | STAR | 1.20.11.3277 | - | LIVE |
| Brood War | SEXP | 1.20.11.3277 | - | LIVE |
| Diablo Shareware | DSHR | 2001.5.11.1 | 0x2A | LIVE |
| Diablo Retail | DRTL | 2001.5.11.1 | 0x2A | LIVE |
| Diablo II | D2DV | 1.14.3.71 | 0x0E | LIVE |
| Diablo II: LoD | D2XP | 1.14.3.71 | 0x0E | LIVE |
| WarCraft II BNE | W2BN | 2.0.2.0 | 0x4F | LIVE (serves nothing unique) |
| Diablo I Beta | DIAB | - | - | **DEAD** (silent) |
| Diablo I Stress | DTST | - | - | **DEAD** |
| Diablo II Stress | D2ST | - | - | **DEAD** |
| WarCraft III Demo | W3DM | - | 0x01 | **DEAD** |
| WarCraft III | WAR3 | 1.30.0.9900 | 0x1E | NLS-auth (oracle can't see it; not old-SID) |
| WC3: Frozen Throne | W3XP | 1.30.0.9900 | 0x1E | NLS-auth |

No UNDOCUMENTED old-auth 4CCs found (BNET/TEST/BETA/BLIZ/ADMN/RATS/... all dead).

## BNCS login message trace (StarCraft) - file-check + userdata

```
C->S 0x50 SID_AUTH_INFO        S->C 0x25 SID_PING      C->S 0x25 (ping reply)
S->C 0x50 (auth info reply)    C->S 0x51 SID_AUTH_CHECK S->C 0x51 (reply)
C->S 0x2d SID_GETICONDATA
C->S 0x33 SID_GETFILETIME  ->  icons_STAR.bni      (then BNFTP-pull if stale)
C->S 0x14 SID_UDPPINGRESPONSE
C->S 0x33 SID_GETFILETIME  ->  tos_USA.txt
C->S 0x33 SID_GETFILETIME  ->  bnserver.ini
C->S 0x26 SID_READUSERDATA ->  profile\{sex,age,description},
                               Record\GAME\{0,1}\{wins,losses,disconnects,
                               rating,high rating,last game,last game result},
                               DynKey\GAME\1\rank, Record\GAME\1\high rank
C->S 0x3a SID_LOGONRESPONSE2
C->S 0x0a SID_ENTERCHAT     C->S 0x0b SID_GETCHANNELLIST
C->S 0x0c SID_JOINCHANNEL  ->  "StarCraft" / "Brood War"
```
So `0x33 SID_GETFILETIME` is the client's "do I need this file?" check; it then
BNFTP-downloads (`0x02`) any stale/missing one. The files a STAR client checks:
`icons_STAR.bni`, `tos_USA.txt`, `bnserver.ini`.

## Live BNFTP namespace (enumerated; serving is PRODUCT-SCOPED by the request 4CC)

- **Game patches** (revealed by `--find-patch`, result `0x100`): `{D2DV,D2XP}x{IX86,XMAC}_1xx_114d`, `{DRTL,DSHR}x{IX86,PMAC}_108_109` (Diablo 1 retail+shareware still served). StarCraft/WC2 return `0x102` = no BNFTP patch.
- **Version-check** (shared): `ver-IX86-0..7`, `ver-OSXI-0`, `ver-PMAC-0`. `CheckRevision.mpq` = D2-only.
- **Anti-cheat** (platform-locked, both series end at 19): `lockdown-IX86-00..19` (Win), `psistorm-XMAC-00..19` (Intel-Mac).
- **Config/UI**: `bnserver.ini` (= `bnserver-D2DV.ini`, the realm gateway list; served to realm-list games SC/D2/SSHR, NOT W2BN/Diablo1); `icons.bni` (common, all products) + `icons_STAR.bni` + `icons_SEXP.bni` (SC-specific, 6081 B).
- **ToS** (CDN-shared across all 4 gateways; region-suffixed): `tos.txt`/`tos_USA.txt` (EN 18356), `tos_DEU` (23632), `tos_FRA` (21213), `tos_ESP` (21739), `tos_ITA` (20499), `tos_POL` (26140), `tos_JPN` (11523), `tos_BRA` (12668). No KOR/CHN/TWN/GBR/RUS/etc. = exactly the official D2 localizations.

There is no hidden trove: BNFTP only carries patches + version + a few config/UI/
anti-cheat files. Game content ships in each game's local MPQs. The non-static
categories (ads via `SID_DISPLAYAD`; SC maps user-uploaded) aren't filename-discoverable.

## Gateways (from `bnserver.ini`, VER=1009)

`uswest`, `useast`, `asia`, `europe` `.battle.net` - all still up; ToS/files are
CDN-shared across them (probe round-robin to spread load).

## `connect-forever.classic.blizzard.com:6112` - the odd one (live-probed 2026)

The post-2023 "Classic Games" **global** gateway (`37.244.2.110`). Its
`bnserver.ini` is a *different file* under the same name: VER=2000, one gateway,
`ZONE=8 / ENU=Global` (saved as `bnserver-connect-forever.ini`, 156 B). It behaves
unlike the `*.battle.net` gateways in three concrete ways:

1. **BNCS login is refused - it's a parking endpoint.** `0x01` greets with
   `SID_NULL` (`ff 00 04 00`, *not* the `SID_PING` cookie real bnet sends), then
   **closes on `SID_AUTH_INFO`** - confirmed with the same `bnftp-probe` that gets
   a normal `id=0x50` reply from `useast`/`europe.battle.net`, so this is a real
   property of the host, not a bad packet. `SID_NULL`/`SID_PING` keep-alives hold
   the socket; the server emits an unsolicited `SID_NULL` about every **20 s** and
   holds open indefinitely - an original client pointed here (its hardcoded
   gateway) sits on "Connecting..." forever (hence the name) but can still pull files
   over BNFTP. So no `AUTH_INFO` MPQ-name oracle and no `--find-patch` here. Use
   `--bnftp-only`. The clients are pure binary (no TLS), so `api.classic:443` is
   not in the game path. (A wider per-message FIN map was attempted but the ad-hoc
   Python prober gave false CLOSEs - it even false-CLOSED working `useast` - so
   only the zig-tool-confirmed `AUTH_INFO`-refused result is trusted here.)

   > **`*.battle.net` is normal.** `useast` (137.221.106.68) and `europe`
   > (= `37.244.28.156`, the only *other* live `:6112` host in all of
   > `37.244.0.0/16`, Blizzard EU - full /16 swept) both still answer
   > `SID_AUTH_INFO` with `CheckRevision.mpq` - ordinary
   > working classic gateways, login intact. connect-forever is the only parked one.
2. **BNFTP is product-agnostic.** Every hosted file is served under **all** 4CCs,
   including `CHAT` - the request `product` is ignored (a flat namespace). useast
   scopes serving by product 4CC; connect-forever does not.
3. **It's the Diablo-1 + legacy-platform host.** It carries the Diablo-1
   version-check and **PowerPC-Mac** anti-cheat, and *omits* the D2 ones.

Hosted set (HEAD-swept; `--bnftp-only` required since `0x01` auth is dead):

- `bnserver.ini` (156 B, the VER=2000 global list), `tos.txt`/`tos_USA.txt`
  (18356), `icons.bni` (16379, common only - **no** `icons_STAR/SEXP`).
- Version-check: `ver-IX86-0` (11917), `ver-XMAC-0` (35892), `ver-PMAC-0`
  (36095), `ver-OSXI-0` (3374). Index `-0` only; no `-1..7`.
- `CheckRevisionD1.mpq` (377270, **Diablo-1 only**). **No** `CheckRevision.mpq`
  (the D2 one returns a 0-byte/short reply = not hosted).
- Anti-cheat: `lockdown-IX86-00..19` (Win) + `psistorm-PMAC-00..19` (PowerPC Mac).
  Contrast useast = `lockdown-IX86` + `psistorm-XMAC` (Intel Mac). **No**
  `psistorm-IX86`, no `psistorm-XMAC`, no `lockdown-XMAC/PMAC` here.
- Patches: `DRTL`/`DSHR` x `IX86`/`PMAC` `_108_109` (Diablo-1 retail+shareware).
  **No** D2 `1xx_114d` patches, no SC/W2/JSTR patches as direct files.

Not hosted (confirmed absent): `CheckRevision.mpq` (D2), D2 game patches,
product-specific icons, `IX86ExtraWork.mpq`/Warden/`scan.dll`, news/ad/version
text, any `.pdb`/debug symbol, and no path traversal (`../`, absolute paths all
0-byte). Classic BNFTP carries no debug surface - the pdb angle is a dead end.

> Probe caveat: each BNFTP HEAD is a fresh TCP connection and the server
> occasionally RSTs one, yielding a false "not hosted" 0. Re-probe (the zig
> `bnftp-probe` retries) before trusting a negative - that's how
> `CheckRevisionD1.mpq` first read as absent.

### `classic.blizzard.com` topology (DNS-swept + knocked 2026)

The relaunch is split across hosts (wildcard cert `*.classic.blizzard.com`, no
SANs leak more):

| host | IP | surface |
|-|-|-|
| `connect-forever.classic` | `37.244.2.110` | `:6112` only - the BNFTP sink above; BNCS auth disabled |
| `connect.classic` | `37.244.28.70` | nothing on common ports (client-source-gated, or placeholder) |
| `api.classic` | `37.244.28.14` | `:443` - bespoke gateway |
| `account.classic` | `137.221.106.249` | `:443` (same /16 as `useast.battle.net`) |

### ASN-wide `:6112` sweep - AS57976 (Blizzard Entertainment)

All gateway IPs belong to **AS57976**. Swept every announced IPv4 prefix (154
prefixes ~ 67k IPs) on `:6112`. Live classic BNCS hosts (`SID_NULL` greeters,
`ff 00 04 00`):

| IP | DNS | login (zig AUTH_INFO oracle) |
|-|-|-|
| `137.221.106.68` | useast.battle.net | works -> `CheckRevision.mpq` |
| `137.221.106.160` | uswest.battle.net | works |
| `37.244.28.156` | europe.battle.net | works |
| `117.52.35.63` | asia.battle.net | works |
| `37.244.2.110` | connect-forever.classic | **parked** (closes on AUTH_INFO) |
| `158.115.218.65 / .77 / .106` | **none (no PTR)** | works -> `CheckRevision.mpq` |

So `158.115.218.0/24` (a Blizzard US range) hosts an **unnamed pool of working
classic gateways** - no DNS points at them; likely LB backend nodes behind the
named gateway VIPs. The same /24 also has a few `:6112` hosts that **silently
hold** `0x01`/`0x02` (client-speaks-first - realm/MCP/game backend?) and two that
greet a non-BNCS `03 00 00` (`158.115.218.50`, `158.115.219.96`) - unidentified.
No other Blizzard prefix had a classic `:6112` listener.

### `158.115.218.0/24` is a full classic realm stack (Las Vegas)

Port-matrix scan (`:4000`, `:6112-6120`, `:6200`) of the /24 reveals the complete
production Diablo-II realm tier - the live version of what `src/d2gs.zig` rebuilds:

- **48 D2GS game servers** on `:4000`, IPs `.12`-`.124`. Each sends a fixed 2-byte
  `AF 00` (`0xAF` GS->client) on connect, then waits - it ignores unauthenticated
  input (no realm-issued game hash/token). This is the same `:4000` the engine's
  QServer listens on (`gsport.zig`); our headless GS is one of these.
- **3 BNCS chat/login gateways** on `:6112`: `.65/.77/.106` (`SID_NULL` greeters,
  AUTH_INFO works -> `CheckRevision.mpq`).
- **3 silent `:6112`** (`.30/.50/.79`) - accept TCP, no greeting, client-speaks-first
  = realm/MCP (`0x04`) backend.

So one /24 = gateway -> MCP/realm -> ~48-instance game-server fleet, all in the
Switch Las Vegas site. No `:6113-6120` (WC3 game ports) here - D2 doesn't use them
server-side. `.125`-`.255` had nothing (fleet occupies the lower half).

### Physical hosting (RTT from NL + `as57976.net` traceroute hostnames)

Blizzard runs its own backbone (`*.as57976.net`); the edge-router names encode the
datacenter. TCP-RTT from the Netherlands + final-hop names:

| gateway | RTT | edge hop | datacenter |
|-|-|-|-|
| europe.battle.net | 12 ms | `pe01-eqam3` | **Equinix AM3, Amsterdam** |
| useast.battle.net | 148 ms | `pe01-swlv10` / `las-...` | **Switch SUPERNAP, Las Vegas** |
| uswest.battle.net | 148 ms | `swlv10` | **Switch SUPERNAP, Las Vegas** |
| 158.115.218.x pool | 148 ms | `pe02-swlv10` / `las-swlv10-...` | **Switch, Las Vegas** (PE02) |
| asia.battle.net | 235 ms | (KIDC) | **LG DACOM KIDC, Korea** |
| connect-forever | 113 ms | `pe02-evch1` (via `nyk-bb5`) | **US East Coast** (~ DC/VA) |

Key facts: **"US East" and "US West" are both physically in Las Vegas** (one site,
two logical realms). The unnamed `158.115.218.x` pool sits in the *same* Las Vegas
cluster as useast/uswest but on a different PE router (`pe02` vs `pe01`) and a
different prefix (`158.115.192.0/19`, registered Blizzard/Irvine, vs useast's
`137.221.104.0/22`). connect-forever is the lone US-East-hosted node. GeoIP
(MaxMind/ip-api) is wrong for this space - it places useast/uswest in NL; ignore
it, trust RTT + backbone hostnames. The `158.115.218.x` CheckRevision.mpq filetime
(2026-01-15) is a different deployment batch from useast/uswest/asia (2026-01-09)
and europe (2026-04-23) - three distinct generations.

> Probe note: the ad-hoc Python classifier is unreliable for AUTH_INFO (it
> false-CLOSEs working gateways - see the BNCS caveat above). Login verdicts here
> are from the zig `bnftp-probe`, which got real `id=0x50` replies; trust it over
> the Python sweep's CLOSED.

`api.classic:443` is a **hand-rolled HTTP/1.0 daemon**, not nginx/envoy: reason
phrase hardcoded to `OK` regardless of code (`HTTP/1.0 404 OK`), no
`Server`/`Date`/`Content-Type`/`Content-Length`. `/health` -> `200`, body
`Ready`, and reflects `X-Client-Address: <caller-ip>:0` + an empty `X-Meta`
routing header. Rushed-looking, but no exposure found: only intended ports open,
traversal blocked, real routes unknown (they'd come from capturing a live
patched-client TLS session, not blind fuzzing prod).
