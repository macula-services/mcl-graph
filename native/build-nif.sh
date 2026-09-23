#!/bin/sh
# Build the CozoDB NIF into apps/mcl_graph/priv/, where code:priv_dir(mcl_graph)
# finds it at runtime and relx copies it into the release.
#
# A FAILED BUILD FAILS THE COMPILE. The service has no pure-Erlang fallback for
# a graph database, so a release without the NIF boots, crash-loops in
# mcl_graph_store, and the image looks like it built. Its predecessor skipped
# the build with a warning when cargo was missing or failed, and shipped exactly
# that. Better to be red at compile time.
set -eu

ROOT="$(cd "${1:-.}" && pwd)"
NIF_DIR="${ROOT}/native/mcl_graph_nif"
# Absolute before any cd: a relative PRIV_DIR once resolved inside the crate
# directory and the .so landed in a path nothing reads.
PRIV_DIR="${ROOT}/apps/mcl_graph/priv"

command -v cargo >/dev/null 2>&1 || {
    echo "[mcl-graph] cargo not found: the CozoDB NIF cannot be built" >&2
    exit 1
}

echo "[mcl-graph] building the CozoDB NIF"
(cd "${NIF_DIR}" && cargo build --release --locked)

case "$(uname -s)" in
    Darwin) EXT=dylib ;;
    *)      EXT=so ;;
esac

mkdir -p "${PRIV_DIR}"
cp "${NIF_DIR}/target/release/libmcl_graph_nif.${EXT}" "${PRIV_DIR}/mcl_graph_nif.so"
echo "[mcl-graph] NIF installed to ${PRIV_DIR}/mcl_graph_nif.so"
