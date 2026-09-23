# mcl-graph
#
# An embeddable relational-graph database (CozoDB) as a mesh service. Each
# instance keeps its own graph in RocksDB on the /data volume.
#
# ⚠ THE RUNTIME IS PINNED IN FOUR PLACES AND THEY MUST AGREE: this builder (by
# digest), `.github/workflows/lint-and-test.yml', `.tool-versions', and the VM
# the suite runs on. mcl_graph_service_tests compares all four. A floating
# `erlang:28-alpine' shipped OTP 28.5 to the fleet on 2026-09-22.
FROM docker.io/hexpm/erlang:28.4.3-alpine-3.22.6@sha256:3815b99f486c2509baf556045bca0c5fc1c3ee50fb50a80590534f22cb48736c AS builder
WORKDIR /build

# openssl-dev/zstd-dev/snappy-dev/lz4-dev: mcl_om pulls in rocksdb (via
# barrel_docdb) and khepri/ra transitively, UNCONDITIONALLY.
#
# clang-dev: the CozoDB NIF's `storage-rocksdb' feature builds cozorocks, whose
# build script runs bindgen against RocksDB's C++ headers, and bindgen needs
# libclang. Without it the build stops in a dependency's build.rs with "Unable
# to find libclang".
RUN apk add --no-cache git curl bash build-base cmake perl linux-headers \
        openssl-dev zstd-dev snappy-dev lz4-dev clang-dev

# Rust pinned to the release the CI image carries (macula-ci-otp), so the NIF
# the image ships is compiled by the compiler the suite ran against.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain 1.98.1 --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"
# A cdylib cannot be statically linked against musl.
ENV RUSTFLAGS="-C target-feature=-crt-static"
# macula's QUIC NIF: build it here rather than fetch a glibc prebuilt that
# loads on the build host and fails on alpine.
ENV MACULA_FORCE_SOURCE_BUILD=1
# cozorocks' vendored RocksDB uses uint64_t without including <cstdint>. glibc's
# headers pull it in transitively, musl's do not, so only this build needs it.
ENV CXXFLAGS="-include cstdint"

# Parallelism of the two RocksDB builds (mcl_om's and the NIF's), for a shared
# build host: `--build-arg ERLANG_ROCKSDB_BUILDOPTS=-j4 --build-arg
# CARGO_BUILD_JOBS=4'. Unset, each takes every core.
ARG ERLANG_ROCKSDB_BUILDOPTS
ARG CARGO_BUILD_JOBS

RUN curl -fsSL https://github.com/erlang/rebar3/releases/download/3.27.0/rebar3 \
        -o /usr/local/bin/rebar3 \
    && echo "af85aab41f9fd74bdd6341ebdf6fe9c88077aab9f8eac82371583fa02f2b0bdf  /usr/local/bin/rebar3" \
        | sha256sum -c - \
    && chmod +x /usr/local/bin/rebar3

# Dependencies resolve from rebar.config alone, so this layer survives changes
# to config/, apps/ and native/.
COPY rebar.config ./
RUN rebar3 get-deps

COPY config ./config
COPY native ./native
COPY apps ./apps
# ⚠ THE RELEASE MUST CARRY THE NIF. Without it the node boots, mcl_graph_nif
# fails to load, and mcl_graph_store crash-loops on the fleet; the predecessor
# shipped exactly that once. Fail here instead.
RUN rebar3 as prod release \
    && test -f _build/prod/rel/mcl_graph/lib/mcl_graph-0.1.0/priv/mcl_graph_nif.so

FROM docker.io/alpine:3.22
# LINKS THE PACKAGE TO THE REPOSITORY, so ghcr shows it there and it inherits
# the repository's visibility.
LABEL org.opencontainers.image.source="https://github.com/macula-services/mcl-graph"
# libstdc++/libgcc: the CozoDB NIF is C++ (RocksDB) underneath.
# zstd-libs/snappy/lz4-libs: the runtime halves of the rocksdb codecs the
# builder compiled against; missing, the release dies at boot loading the NIF.
RUN apk add --no-cache ncurses-libs libstdc++ libgcc openssl ca-certificates curl \
        zstd-libs snappy lz4-libs
WORKDIR /app
COPY --from=builder /build/_build/prod/rel/mcl_graph ./

ENV HOME=/app
ENV RELX_REPLACE_OS_VARS=true

ENV MCL_NODE_NAME=mcl_graph
ENV MCL_NODE_HOST=127.0.0.1
ENV MCL_COOKIE=mcl_graph
ENV MCL_HEALTH_PORT=8482
# CozoDB's RocksDB directory. A named volume or a bind mount on a bulk drive;
# without one every recreate forgets the graph.
ENV MCL_DATA_DIR=/data

VOLUME ["/etc/mcl/secrets", "/data"]

EXPOSE 8482
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${MCL_HEALTH_PORT}/health" || exit 1

CMD ["/app/bin/mcl_graph", "foreground"]
