# d2-bnftp-poller image. Multi-stage: an alpine build stage fetches Zig 0.16.0
# and compiles the ReleaseSafe binary (the poller links libc via the clientless
# BNFTP module, so the musl toolchain provides it); the runtime stage is a small
# alpine with git + ca-certificates + bash for the shard-coordination entrypoint.
#
#   docker buildx build --platform=linux/amd64 \
#     -t ghcr.io/jaenster/d2-bnftp-poller:latest \
#     -f poller/Dockerfile --push poller
FROM alpine:3.20 AS build
ARG ZIG_VERSION=0.16.0
RUN apk add --no-cache curl xz tar git \
 && curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz \
 && mkdir -p /opt/zig && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
 && ln -s /opt/zig/zig /usr/local/bin/zig && zig version
WORKDIR /src
COPY build.zig build.zig.zon ./
COPY src ./src
# Populate the pinned d2-clientless dependency, then build ReleaseSafe.
RUN zig build --fetch \
 && zig build -Doptimize=ReleaseSafe

FROM alpine:3.20
RUN apk add --no-cache git ca-certificates bash curl coreutils
COPY --from=build /src/zig-out/bin/d2-bnftp-poller /usr/local/bin/d2-bnftp-poller
COPY entrypoint.sh /entrypoint.sh
COPY batch.sh /batch.sh
RUN chmod +x /entrypoint.sh /batch.sh
ENTRYPOINT ["/entrypoint.sh"]
