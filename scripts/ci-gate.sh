#!/usr/bin/env bash
# Run what CI runs, inside the CI image, as root: the gate this repo is judged by.
#
#   scripts/ci-gate.sh                 lint, eunit, dialyzer (what CI runs)
#   scripts/ci-gate.sh rebar3 eunit    any one command, same image, same setup
#
# `podman run', never `docker run': on the workstation `docker' is the CLI over
# rootless podman with pids.max=1, where the NIF build cannot fork.
#
# The cargo registry and the NIF's target directory persist between runs (a
# named volume and the repo's own ignored target/), because a cold cozo +
# RocksDB build takes many minutes. _build persists in a named volume for
# iteration; FRESH=1 gives it a tmpfs instead, which is what CI sees, and is the
# run that counts: a cached _build outlives the source it was compiled from.
set -euo pipefail

IMAGE="ghcr.io/macula-io/macula-ci-otp:20260923-1347@sha256:b2260d084a3d3c5e0b74932c4ee052a0cadfddddb6587d5d2214873e6bb06330"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$#" -eq 0 ]; then
    set -- sh -c 'rebar3 lint && rebar3 eunit && rebar3 dialyzer'
fi

if [ "${FRESH:-0}" = 1 ]; then
    BUILD_MOUNT=(--tmpfs /src/_build:exec)
else
    BUILD_MOUNT=(-v mcl-graph-build:/src/_build)
fi

# ⚠ host00 is shared. rocksdb's build script ignores MAKEFLAGS and runs
# -j$(nproc); ERLANG_ROCKSDB_BUILDOPTS caps mcl_om's, CARGO_BUILD_JOBS caps the
# NIF's own cozorocks build. A cold build needs a rocksdb slot from the
# Supervisor first.
exec podman run --rm \
    -e ERLANG_ROCKSDB_BUILDOPTS=-j4 \
    -e CARGO_BUILD_JOBS=4 \
    -v "${ROOT}:/src" \
    -v mcl-graph-cargo-registry:/usr/local/cargo/registry \
    -w /src \
    "${BUILD_MOUNT[@]}" \
    "${IMAGE}" \
    sh -c 'apt-get update -qq >/dev/null \
        && apt-get install -y -qq --no-install-recommends libsnappy-dev liblz4-dev libzstd-dev libbz2-dev libclang-dev >/dev/null \
        && "$@"' gate "$@"
