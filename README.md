# mcl-graph

**An embeddable relational-graph database as a mesh service.** Each instance
keeps its own [CozoDB](https://github.com/cozodb/cozo) graph (Datalog over
RocksDB) on local disk. Callers query it and add to it over the
[macula](https://github.com/macula-io/macula) mesh. A consumer composes one
knowledge graph from many instances, either by calling `resolve_link` on each
one or by subscribing to the facts they publish.

It runs on macula 12 through [mcl_om](https://hex.pm/packages/mcl_om), with
post-quantum signatures on every call and fact.

## Mesh surface

Procedures, reached as `mcl-graph/<name>`. All of them are open to any member
of the realm, and the graph is a commons: nothing limits how much a member adds.
A caller becomes reachable only after the realm has admitted the `mcl-graph`
org. Until then the node is healthy and nothing can reach it.

| Procedure | Parameters | Returns |
|---|---|---|
| `resolve_link` | `subject`, and optionally `predicate`, `direction` (`out`, `in`, `both`; default `out`) and `depth` (1 to 8, default 1) | `rows`: one map per link, or per reachable entity at the fewest hops that reach it when `depth` > 1; at most 1000 |
| `resolve_entity` | `entity_id` | `id`, `attributes`, `first_seen`, `source`, `out_degree`, `in_degree`, `predicates` |
| `learn_link` | `subject`, `predicate`, `object`, and optionally `confidence` (default 1.0), `metadata` and `asserted_by` | `link_id`, `entities_new` |
| `narrate_entity` | `entity_id` | `entity_id`, `prose` |
| `narrate_link` | same as `resolve_link` | `subject`, `prose` |

Facts, on app-tier topics under the graph's org, for example
`io.macula/mcl-graph/graph/knowledge/link_learned_v1`:

| Fact | Direction | Payload |
|---|---|---|
| `entity_learned_v1` | published | `entity_id`, `attributes`, `source`, `learned_at` |
| `link_learned_v1` | published | `subject`, `predicate`, `object`, `confidence`, `source`, `learned_at` |
| `truth_asserted_v1` | heard | `subject`, `predicate`, `object`: any producer may publish one for the graph to learn |

Text arrives as text and times are milliseconds since the epoch.

## Learning and provenance

`learn_link` creates any entity it has not seen, publishing `entity_learned`
for it, then records the link and publishes `link_learned`. CozoDB's `:insert`
decides whether an entity is new in a single round trip, so two racing calls
for the same new entity publish `entity_learned` once.

The caller becomes part of the graph. By default the caller is the
wire-authenticated node id of the call. A relay calling on behalf of others
can name who it acts for in `asserted_by`, which carries an identity and an
ownership proof bound to `mcl-graph/learn_link`. If the proof is invalid, the
caller falls back to the wire caller. The caller, hex-encoded, is linked
`asserted` to both endpoints at confidence 1.0. To ask what X has told the
graph, call `resolve_link` with subject X and predicate `asserted`.

A heard `truth_asserted` fact goes through the same path, with its verified
publisher as the caller, at confidence 0.7. A fact whose publisher did not
verify is refused, and so is one that is not a map.

Every query carries CozoDB's own timeout (10 s), so no single call can hold
the store. A failure in the store reaches the caller as `store_error` and is
logged in full.

## Narration

`narrate_*` render the graph one sentence per link, from a fixed template. The
narration involves no model and no network call, so it costs nothing and
cannot fail.

## Build and test

The CozoDB NIF (`native/mcl_graph_nif`, Rust) is built from source on every
compile and needs cargo and libclang. If the NIF fails to build, the compile
fails. Nothing falls back.

```sh
scripts/ci-gate.sh                 # lint, eunit, dialyzer in the CI image, as root
FRESH=1 scripts/ci-gate.sh         # the same, with no cached _build: what CI sees
scripts/ci-gate.sh rebar3 eunit    # one command, same image
rebar3 as prod release
```

`mcl_graph_store_tests` runs against a real CozoDB. The desk tests also send
their payloads through macula's own codec, so they see what a real call
delivers.

## Configuration

| Variable | Default | What |
|---|---|---|
| `MCL_REALM` | (required) | the realm tag, 64 hex |
| `MCL_REALM_NAME` | (required) | the realm name the topics carry; its sha256 must be `MCL_REALM` |
| `MCL_REALM_KEY` | (required) | the realm's public signing key, hex |
| `MACULA_STATION_SEEDS` | (required) | `host[:port],...` |
| `MACULA_STATION_NODE_IDS` | (required) | the seeds' node ids, 64 hex each, in the same order |
| `MCL_DATA_DIR` | `/data` | CozoDB's RocksDB directory |
| `MCL_HEALTH_PORT` | `8482` | `/health` |
| `MCL_NODE_NAME`, `MCL_NODE_HOST`, `MCL_COOKIE` | `mcl_graph`, `127.0.0.1`, `mcl_graph` | Erlang distribution |

The node identity is kept at `/etc/mcl/secrets/identity.key` and must be on a
persistent volume. `deploy/docker-compose.yml` runs the service with both
volumes in place.

`/health` reports `down` when the store is not open. It reports `degraded`
when the `truth_asserted` subscription is not held: the graph still answers
calls but hears no truths.

## License

Apache-2.0
