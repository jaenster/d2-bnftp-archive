# d2-bnftp-poller

A sharded, multi-source BNFTP comparison poller. It re-downloads a set of
Battle.net BNFTP files from several regional sources, compares them, and commits
the result to the `jaenster/d2-bnftp-archive` repo, keeping an authentic,
up-to-date, divergence-aware copy of what the live gateways serve.

BNFTP (Battle.net File Transfer, protocol selector 0x02) is unauthenticated: no
CD-key, no login. The actual fetch logic lives in the public `d2-clientless`
package; this poller imports its `bnftp` module and calls `bnftp.fetch(...)`.

The source and container image live here (`poller/`); the image is built by
`.github/workflows/build-poller.yml` and pushed to
`ghcr.io/jaenster/d2-bnftp-poller`. The Kubernetes deployment that runs it (the
Argo `CronWorkflow`, ArgoCD apps, and the `d2-bnftp-poller` / `ghcr` secrets)
lives in a private ops repo; the manifests referenced under `gitops/...` below
are there.

## Sources

- Named regional gateways (product D2XP): `useast.battle.net`, `uswest.battle.net`,
  `asia.battle.net`, `europe.battle.net`.
- `vegas`: the unnamed Las Vegas gateway pool (raw IPs 158.115.218.65 / .77 /
  .106, product D2XP). Treated as ONE logical source; the three IPs are tried in
  order and the first non-empty reply wins.
- `forever`: `connect-forever.classic.blizzard.com` (product D2XP, unauthenticated
  BNFTP). Serves the Diablo-1 + PowerPC-Mac legacy set only.

The five D2 sources are `useast uswest asia europe vegas`.

## fetch-list format

Plain text, one entry per line: `<class> <filename>`. Blank lines and lines
starting with `#` are ignored.

- class `d2`: fetched from all 5 D2 sources and compared.
- class `forever`: fetched from the `forever` source only.

```
# class     filename
d2          CheckRevision.mpq
forever     CheckRevisionD1.mpq
```

## Placement rule (pod-0 coordinator, after the barrier)

For each `d2` file, the coordinator gathers the per-source staged bytes:

- All sources byte-identical -> write the canonical `files/<filename>` and delete
  any stale `files/<source>/<filename>`.
- Any divergence -> write `files/<source>/<filename>` for every source that
  produced bytes (useast/uswest/asia/europe/vegas) and delete the canonical
  `files/<filename>`.

For each `forever` file -> always write `files/forever/<filename>`.

Then it regenerates `SHA256SUMS` recursively over `files/**`, writes
`REALM-DIVERGENCE.md` (every file NOT in canonical `files/` with its per-source
sha256), writes `LAST-FETCHED.txt`, and commits + pushes if anything changed.

## Workflow model

The poller runs as an Argo `CronWorkflow` (weekly) whose spec is a DAG:

```
clone -> fetch(x3) -> collect
```

- `clone` - one pod does a fresh clone of `d2-bnftp-archive` into `/work/repo`.
- `fetch` - fanned out to three pods via `withItems: [0,1,2]`, each running
  `SHARD_INDEX={{item}} SHARD_TOTAL=3`. A `podAntiAffinity` on
  `kubernetes.io/hostname` (matching the `app: d2-bnftp-poller, role: fetch` pod
  labels) forces the three fetch pods onto three distinct nodes -> three distinct
  egress IPs, spreading load across the gateways.
- `collect` - one pod compares + places + regenerates `SHA256SUMS` +
  `REALM-DIVERGENCE.md` + commits + pushes.

Argo's DAG dependencies handle ordering, so there is no shared-PVC barrier; all
templates mount the same ReadWriteMany PVC at `/work` (longhorn supports RWX).

The unit of work is a `(file, source)` pair. The Zig poller (the `fetch` role)
expands the fetch-list into the flat pair list (d2 files x 5 sources, forever
files x 1), shards it by `pair index % SHARD_TOTAL == SHARD_INDEX`, and fetches
only its pairs. It writes only fetch results (never a 0-byte file) into
`/work/stage/<source>/<filename>`. The poller does ONLY fetch-and-stage; the
compare + placement is the `collect` role.

Each `bnftp.fetch` is retried up to three times because BNFTP occasionally RSTs;
the `fetch` role exits nonzero if any pair in its shard failed all retries.

`entrypoint.sh` dispatches on its first arg: `entrypoint.sh clone|fetch|collect`.

## Discord logging

Each role's stdout/stderr is piped through a batched Discord sender (`batch.sh`)
when `DISCORD_WEBHOOK_URL` is set. Lines are accumulated and flushed every ~1.5s
or ~1900 chars, POSTed as a fenced code block under the username
`d2-bnftp-poller`, honoring HTTP 429 `retry_after`. It posts each role's start
line, per-shard progress, any divergences found, and the final commit result.
Unset `DISCORD_WEBHOOK_URL` -> stdout only.

## Environment variables

- `FETCH_LIST` - path to the fetch-list (default `fetch-list`).
- `STAGE_DIR` - directory to stage downloaded files into (default `stage`).
- `SHARD_INDEX` - this fetch pod's shard index (from `withItems`).
- `SHARD_TOTAL` - number of shards (3).

The container entrypoint additionally uses `GIT_TOKEN` (clone + collect) and
`DISCORD_WEBHOOK_URL` (all roles).

## Required secret

The CronWorkflow expects a secret `d2-bnftp-poller` in the `d2-bnftp` namespace
with two keys:

- `GIT_TOKEN` - a GitHub token with push access to `d2-bnftp-archive`.
- `DISCORD_WEBHOOK_URL` - a Discord webhook URL for log streaming.

```
kubectl -n d2-bnftp create secret generic d2-bnftp-poller \
  --from-literal=GIT_TOKEN=ghp_xxx \
  --from-literal=DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
```

A `ghcr` image-pull secret is also required in the `d2-bnftp` namespace to pull
the private image.

## Deploy

Argo Workflows must be installed before the poller (its `CronWorkflow` CRD is
provided by the argo-workflows chart). ArgoCD sync-waves order this: the
`argo-workflows` app is wave 0 and the `d2-bnftp-poller` app is wave 1.

1. Sync the `argo-workflows` ArgoCD app (`gitops/apps/argo-workflows.yaml`) to
   install the workflow engine into the `argo` namespace.
2. Create the `d2-bnftp-poller` secret in the `d2-bnftp` namespace (see above),
   and the `ghcr` image-pull secret.
3. Sync the `d2-bnftp-poller` ArgoCD app (`gitops/apps/d2-bnftp-poller.yaml`).

Trigger a run out of schedule with the `argo` CLI:

```
argo submit -n d2-bnftp --from cronwf/d2-bnftp-poller
```

## Build and run locally

```
zig build -Doptimize=ReleaseSafe

printf 'd2 CheckRevision.mpq\n' > /tmp/fetch-list
FETCH_LIST=/tmp/fetch-list STAGE_DIR=/tmp/stage SHARD_INDEX=0 SHARD_TOTAL=1 \
  ./zig-out/bin/d2-bnftp-poller
```

Build the image (nodes are amd64):

```
docker buildx build --platform=linux/amd64 \
  -t ghcr.io/jaenster/d2-bnftp-poller:latest \
  -f Dockerfile --push .
```
