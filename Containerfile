# mcl-graph
#
# An embeddable relational-graph database (CozoDB) as a mesh service. Each
# instance keeps its own graph in RocksDB on the /data volume.

# ⚠ THE FLEET'S ROCKSDB PAIR, PINNED BY DATED TAG AND DIGEST, AND THE PAIR MOVES
# TOGETHER. macula-ci-otp-rocksdb carries OTP 28.4.3 on an OpenSSL with ML-DSA,
# rebar3, Rust, cmake and a C++ toolchain: everything the CozoDB NIF and
# macula's own NIFs build with. macula-pq-runtime-rocksdb is the same Debian
# with what the release loads (OpenSSL, ncurses, libstdc++, libgcc_s) and curl
# for the health check, so the ERTS and the NIFs built here match the libc they
# run on. lint-and-test.yml builds in the same image, and
# mcl_graph_service_tests guards all three pins. (cozorocks compiles its own
# vendored RocksDB, lz4 and zstd; it does not use the image's librocksdb.)
FROM ghcr.io/macula-io/macula-ci-otp-rocksdb:20260928-1642@sha256:57e3929c45976fbc1d216bddfde831cad7b7e276d8197b099dfbac0cd731a8c9 AS builder

# ⚠ THE OTP RELEASE, ASSERTED HERE because the image tag names a date, not a
# release. The same check as lint-and-test.yml's toolchain step; the service
# tests read this line and compare it with .tool-versions and lint's.
RUN erl -noshell -eval ' \
    Otp = string:trim(element(2, file:read_file(filename:join([code:root_dir(), "releases", erlang:system_info(otp_release), "OTP_VERSION"])))), \
    Mldsa = lists:member(mldsa87, crypto:supports(public_keys)), \
    io:format("OTP ~s, mldsa87 ~p~n", [Otp, Mldsa]), \
    case {Otp, Mldsa} of \
        {<<"28.4.3">>, true} -> halt(0); \
        _                    -> halt(1) \
    end.'

WORKDIR /build

# Parallelism of the NIF's vendored RocksDB build, for a shared build host:
# `--build-arg CARGO_BUILD_JOBS=4'. Unset, it takes every core.
ARG CARGO_BUILD_JOBS

# Dependencies resolve from rebar.config alone, so this layer survives changes
# to config/, apps/ and native/.
COPY rebar.config ./
RUN rebar3 get-deps

COPY config ./config
COPY native ./native
COPY apps ./apps
# ⚠ THE RELEASE MUST CARRY THE NIF. Without it the node boots, mcl_graph_nif
# fails to load, and mcl_graph_store crash-loops on the fleet; the predecessor
# shipped exactly that once. Fail here instead. The compile hook builds it
# through native/build-nif.sh, for the baseline x86-64 CPU (the beam boxes have
# no AVX2).
RUN rebar3 as prod release \
    && ls _build/prod/rel/mcl_graph/lib/mcl_graph-*/priv/mcl_graph_nif.so

FROM ghcr.io/macula-io/macula-pq-runtime-rocksdb:20260928-1642@sha256:e382299fc2ae563371cd4bc61b1f2acc9e27e715fbf7a87db54e2e88285cf54e
# LINKS THE PACKAGE TO THE REPOSITORY, so ghcr shows it there and it inherits
# the repository's visibility.
LABEL org.opencontainers.image.source="https://github.com/macula-services/mcl-graph"
# THIS image's commit (build-push passes github.sha). Without it the image
# inherited its base image's label, which names macula-ci-images' commit.
ARG REVISION=unknown
LABEL org.opencontainers.image.revision="${REVISION}"
# Nothing is installed here: the runtime image carries what the release loads,
# the CozoDB NIF's libstdc++ and libgcc_s among it, and curl for the health check.
WORKDIR /app
COPY --from=builder /build/_build/prod/rel/mcl_graph ./

ENV HOME=/app
ENV RELX_REPLACE_OS_VARS=true

ENV MCL_NODE_NAME=mcl_graph
ENV MCL_NODE_HOST=127.0.0.1
ENV MCL_COOKIE=mcl_graph
ENV MCL_HEALTH_PORT=8482
# CozoDB's RocksDB directory. A bind mount on a bulk drive on a fleet node;
# without one every recreate forgets the graph.
ENV MCL_DATA_DIR=/data

VOLUME ["/etc/mcl/secrets", "/data"]

# Health, as registered in macula-fleet PORTS.md.
EXPOSE 8482
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${MCL_HEALTH_PORT}/health" || exit 1

CMD ["/app/bin/mcl_graph", "foreground"]
