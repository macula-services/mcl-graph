# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [SemVer](https://semver.org/).

## [0.1.0]

The macula 12 port of hecate-graph 0.5.1, on mcl_om.

### Changed

- **Names.** The application is `mcl_graph`; callers reach the desks as
  `mcl-graph/resolve_link`, `resolve_entity`, `learn_link`, `narrate_entity`
  and `narrate_link` (org-namespaced procedures, as 12 requires).
- **Topics.** The facts are app-tier topics under the graph's org:
  `<realm>/mcl-graph/graph/knowledge/entity_learned_v1`, `link_learned_v1`, and
  the heard `truth_asserted_v1`. The topic names the fact and its version, so
  the payloads no longer carry `type` and `schema_v`.
- **Text is text.** Every string in a reply or a fact leaves as CBOR text, so
  non-BEAM callers see strings rather than hex. JSON booleans leave as 1/0.
- **Heard truths.** A publication macula verified is learned at 0.7; one that
  did not verify is refused. The 0.4 "unsigned" tier is gone: in 12 every
  publication is signed.
- **The NIF** runs on dirty IO schedulers and is built with rustler 0.38. A
  failed NIF build fails the compile instead of shipping a release that cannot
  open its store.

### Removed

- **LLM narration.** narrate_* called `hecate-llm.chat`, which is not ported,
  so the narrator's LLM backend and its settings are gone and narration is the
  deterministic sentence-per-link template it used to fall back to.
- `backup/2` and `restore/2` in the NIF, which nothing called.

### Fixed

- **The `entities` relation is created.** Its schema was one CozoDB script
  with two `:create`s, and CozoDB runs only the last, so `entities` never
  existed and every learn_link failed with `relation_not_found`. Each schema
  statement is its own script now, tested against a real CozoDB, restart
  included.
- **Learning about a known entity works.** CozoDB reports an `:insert`
  collision as "key exists in database"; the code looked for "already exist",
  so every learn_link touching an entity it had seen failed.
- **Lookups by subject find their links.** CozoDB 0.7.6's secondary indexes
  answered no rows for a subject that had links. The links relation is keyed
  (subject, link_id) instead, and there are no indexes.
- **resolve_entity summarises.** Its degree queries used `n = count(l)`, which
  CozoDB rejects, and the failure was swallowed into an entity without a
  summary. The aggregates are in the head now, and a failed step is the
  caller's error.
- **narrate_link describes real rows.** The template matched atom keys, and
  resolve_link's rows are named by binary column headers, so every non-empty
  narration crashed. It reads all four row shapes now.
- **Caller metadata is stored.** A payload's nested maps arrive with
  `{text, Key}` keys, which the NIF could not turn into JSON.
- **`asserted_by` over the real wire** verifies, with mcl_om 0.26.6.
- **No single call can hold the store.** `depth` is capped at 8, a traversal
  keeps one row per entity (`min(hop)`) so a cycle cannot multiply it, reads
  return at most 1000 rows, and every query carries CozoDB's own 10 s timeout:
  a query inside the NIF cannot be interrupted any other way.
- **A `truth_asserted` fact that is not a map is refused.** Any realm member
  could publish one, and a handful crashed the subscriber often enough to stop
  the node.
- **`direction => both` with a `predicate`** answers instead of refusing.
- **Store failures reach callers as `store_error`**, with CozoDB's text logged
  in full and without its colour codes.
- **Health does not wait on the subscriber**, and a pool that dies mid-subscribe
  is retried rather than restarting it.
- **The NIF returns errors instead of raising**, so a bad binding cannot crash
  the process that owns the database handle.
- **The image build fails if the release lacks the NIF.**
