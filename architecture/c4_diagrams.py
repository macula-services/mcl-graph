"""Generate mcl-graph's C4 diagrams: assets/c4-context.svg, assets/c4-containers.svg
and assets/c4-components.svg.

Run:  python3 architecture/c4_diagrams.py

The style block is the house one (mcl-fovea's): plain classes with literal
colours and a prefers-color-scheme: dark block, and no CSS custom properties,
because rsvg-convert renders those black. After a change, render each one
(rsvg-convert -w 1400 assets/c4-context.svg -o /tmp/c.png) and look at it;
keep architecture/README.md's tables in step.
"""
import os
from xml.sax.saxutils import escape

ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")

SANS = '"Atkinson Hyperlegible", "Segoe UI", system-ui, -apple-system, Helvetica, Arial, sans-serif'
MONO = '"JetBrains Mono", ui-monospace, Menlo, Consolas, monospace'

STYLE = f"""<style>
.t-name {{ font-family: {SANS}; font-size: 15px; font-weight: 700; }}
.t-desc {{ font-family: {SANS}; font-size: 12.5px; }}
.t-rel {{ font-family: {SANS}; font-size: 11.5px; paint-order: stroke; stroke-width: 4px; stroke-linejoin: round; }}
.t-code {{ font-family: {MONO}; font-size: 13px; font-weight: 600; }}
.t-small {{ font-size: 12px; }}
.t-type {{ font-family: {MONO}; font-size: 11.5px; }}
.t-bound {{ font-family: {MONO}; font-size: 12px; font-weight: 600; }}
.edge {{ fill: none; stroke-width: 1.25; }}
.edge-later {{ fill: none; stroke-width: 1.25; stroke-dasharray: 5 4; }}
.bg {{ fill: #FFFFFF; }}
.b-sys {{ fill: #F5E9CC; stroke: #A56F0A; stroke-width: 2; }}
.b-ext {{ fill: #ECEFED; stroke: #8A9791; stroke-width: 1.25; }}
.b-per {{ fill: #E3EBF2; stroke: #3B5B7A; stroke-width: 1.25; }}
.b-cmp {{ fill: #FFFFFF; stroke: #8A9791; stroke-width: 1.25; }}
.b-later {{ fill: none; stroke: #8A9791; stroke-width: 1.25; stroke-dasharray: 5 4; }}
.bound {{ fill: none; stroke: #66736E; stroke-width: 1.25; stroke-dasharray: 7 5; }}
.bound-in {{ fill: none; stroke: #D9DFDC; stroke-width: 1.5; stroke-dasharray: 4 4; }}
.head {{ fill: #3B5B7A; }}
.t-name {{ fill: #16201D; }}
.t-code {{ fill: #16201D; }}
.t-type {{ fill: #66736E; }}
.t-desc {{ fill: #34413C; }}
.t-bound {{ fill: #66736E; }}
.t-rel {{ fill: #66736E; stroke: #FFFFFF; }}
.edge, .edge-later {{ stroke: #8A9791; }}
.arrowhead {{ fill: #8A9791; }}
@media (prefers-color-scheme: dark) {{
.bg {{ fill: #171F1C; }}
.b-sys {{ fill: #3A2E13; stroke: #E3AA3C; stroke-width: 2; }}
.b-ext {{ fill: #1C2421; stroke: #7D8B85; stroke-width: 1.25; }}
.b-per {{ fill: #1D2A36; stroke: #8EB4D8; stroke-width: 1.25; }}
.b-cmp {{ fill: #171F1C; stroke: #7D8B85; stroke-width: 1.25; }}
.b-later {{ fill: none; stroke: #7D8B85; stroke-width: 1.25; stroke-dasharray: 5 4; }}
.bound {{ fill: none; stroke: #93A09A; stroke-width: 1.25; stroke-dasharray: 7 5; }}
.bound-in {{ fill: none; stroke: #2A3431; stroke-width: 1.5; stroke-dasharray: 4 4; }}
.head {{ fill: #8EB4D8; }}
.t-name {{ fill: #E6ECE9; }}
.t-code {{ fill: #E6ECE9; }}
.t-type {{ fill: #93A09A; }}
.t-desc {{ fill: #C3CDC8; }}
.t-bound {{ fill: #93A09A; }}
.t-rel {{ fill: #93A09A; stroke: #171F1C; }}
.edge, .edge-later {{ stroke: #7D8B85; }}
.arrowhead {{ fill: #7D8B85; }}
}}
</style>"""

DEFS = ('<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
        'markerHeight="7" orient="auto-start-reverse"><path class="arrowhead" '
        'd="M0 0L10 5L0 10z"/></marker></defs>')


class Svg:
    def __init__(self, w, h, label):
        self.w, self.h, self.label = w, h, label
        self.parts = []

    def text(self, cls, x, y, s, anchor=None, rotate=None):
        a = f' text-anchor="{anchor}"' if anchor else ""
        r = f' transform="rotate({rotate} {x} {y})"' if rotate is not None else ""
        self.parts.append(f'<text class="{cls}" x="{x}" y="{y}"{a}{r}>{escape(s)}</text>')

    def rect(self, cls, x, y, w, h, rx=10):
        self.parts.append(f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}"/>')

    def element(self, cls, x, y, w, h, name, kind, desc, person=False):
        """A context or container element: name, [kind], description lines."""
        self.rect(cls, x, y, w, h)
        tx = x + 16
        if person:
            self.parts.append(f'<circle class="head" cx="{x + 26}" cy="{y + 24}" r="9"/>')
            tx = x + 44
        self.text("t-name", tx, y + 28, name)
        self.text("t-type", tx, y + 46, kind)
        for i, line in enumerate(desc):
            self.text("t-desc", x + 16, y + 70 + 16 * i, line)

    def component(self, cls, x, y, w, h, name, kind, desc, small=False):
        """A component: code name, [kind] right-aligned (or below when small)."""
        self.rect(cls, x, y, w, h, rx=8)
        self.text("t-code t-small" if small else "t-code", x + 14, y + 24, name)
        if small:
            self.text("t-type", x + 14, y + 42, kind)
            y0 = y + 62
        else:
            self.text("t-type", x + w - 12, y + 24, kind, anchor="end")
            y0 = y + 46
        for i, line in enumerate(desc):
            self.text("t-desc", x + 14, y0 + 16 * i, line)

    def row(self, cls, x, y, w, name, desc):
        """A one-line desk: name on the left, what it does on the right."""
        self.rect(cls, x, y, w, 34, rx=8)
        self.text("t-code t-small", x + 12, y + 22, name)
        self.text("t-desc", x + w - 12, y + 22, desc, anchor="end")

    def bound(self, cls, x, y, w, h, label):
        self.rect(cls, x, y, w, h, rx=12 if cls == "bound" else 10)
        self.text("t-bound", x + 16, y + 22, label)

    def edge(self, d, later=False):
        c = "edge-later" if later else "edge"
        self.parts.append(f'<path class="{c}" d="{d}" marker-end="url(#a)"/>')

    def write(self, name):
        head = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" role="img" '
                f'aria-label="{escape(self.label)}">',
                f"<title>{escape(self.label)}</title>", STYLE, DEFS,
                f'<rect class="bg" x="0" y="0" width="{self.w}" height="{self.h}"/>', ""]
        with open(os.path.join(ASSETS, name), "w") as f:
            f.write("\n".join(head + self.parts + ["</svg>", ""]))


# ---------------------------------------------------------------------------
# Level 1: system context
# ---------------------------------------------------------------------------
def context():
    s = Svg(1000, 600, "mcl-graph system context")

    # Edges first, so boxes and labels sit on top.
    s.edge("M135 130V200")                      # agent -> macula-mcp
    s.edge("M250 262H370")                      # macula-mcp -> mcl-graph
    s.edge("M750 262H630")                      # realm members -> mcl-graph
    s.edge("M500 130V200")                      # truth producers -> mcl-graph
    s.edge("M630 215H690V80H750")               # mcl-graph -> graph consumers
    s.edge("M420 340V440")                      # mcl-graph -> station
    s.edge("M580 340V440")                      # mcl-graph -> realm

    s.element("b-per", 20, 30, 230, 100, "Agent", "[Person or AI agent]",
              ["Asks and teaches the graph", "through MCP tools"], person=True)
    s.element("b-ext", 390, 30, 220, 100, "Truth producers", "[External: realm members]",
              ["Publish truth_asserted_v1", "for the graph to learn"])
    s.element("b-ext", 750, 30, 230, 110, "Graph consumers", "[External system]",
              ["Compose one graph from many", "instances: resolve_link on", "each, or the facts"])

    s.element("b-ext", 20, 200, 230, 130, "macula-mcp", "[External: MCP server]",
              ["Outside the fleet. mesh_call;", "prove_ownership: 1 adds an", "asserted_by proof v2"])
    s.element("b-sys", 370, 200, 260, 140, "mcl-graph", "[Software system, mcl-om service]",
              ["One instance's graph (CozoDB):", "resolves, learns with", "provenance, narrates, and",
               "publishes what it learns"])
    s.element("b-ext", 750, 200, 230, 130, "Any realm member", "[External: mesh callers]",
              ["Every procedure is open;", "the verified caller is", "recorded as provenance"])

    s.element("b-ext", 230, 440, 250, 110, "macula-station", "[External system]",
              ["Pinned home station(s);", "carries every call and fact", "to and from this node"])
    s.element("b-ext", 520, 440, 250, 110, "macula-realm", "[External system]",
              ["Boot identity claim; a D25", "provider grant per procedure;", "the realm key is the anchor"])

    s.text("t-rel", 143, 170, "uses")
    s.text("t-rel", 310, 238, "learn_link,", anchor="middle")
    s.text("t-rel", 310, 252, "resolve_*, narrate_*", anchor="middle")
    s.text("t-rel", 310, 282, "(over the mesh,", anchor="middle")
    s.text("t-rel", 310, 296, "optional asserted_by)", anchor="middle")
    s.text("t-rel", 690, 252, "resolve, learn,", anchor="middle")
    s.text("t-rel", 690, 282, "narrate, info", anchor="middle")
    s.text("t-rel", 492, 160, "publish", anchor="end")
    s.text("t-rel", 492, 174, "truth_asserted_v1", anchor="end")
    s.text("t-rel", 684, 150, "publishes", anchor="end")
    s.text("t-rel", 684, 164, "entity_learned_v1,", anchor="end")
    s.text("t-rel", 684, 178, "link_learned_v1", anchor="end")
    s.text("t-rel", 412, 386, "dials out,", anchor="end")
    s.text("t-rel", 412, 400, "pinned (QUIC, pq_hybrid)", anchor="end")
    s.text("t-rel", 588, 386, "claims its identity,")
    s.text("t-rel", 588, 400, "gets provider grants")
    s.text("t-rel", 20, 585, "Every call and fact travels over the mesh, through the station.")
    s.write("c4-context.svg")


# ---------------------------------------------------------------------------
# Level 2: containers
# ---------------------------------------------------------------------------
def containers():
    s = Svg(1000, 640, "mcl-graph containers")

    s.bound("bound", 220, 40, 560, 560, "beam01.lab [planned: beam lab box, host networking]")
    s.bound("bound-in", 236, 72, 528, 500, "mcl-graph [Software system, mcl-om service]")

    # Edges
    s.edge("M200 136H260")                     # macula-mcp
    s.edge("M200 226H260")                     # realm members
    s.edge("M200 316H260")                     # truth producers
    s.edge("M740 134H810")                     # station
    s.edge("M740 228H810")                     # realm
    s.edge("M740 310H810")                     # graph consumers
    s.edge("M372 320V350")                     # graph data
    s.edge("M627 320V350")                     # identity key

    s.element("b-sys", 260, 100, 480, 220, "mcl-graph service",
              "[Container: OCI image, OTP 28.4.3 release, mcl_om 0.33.3]",
              ["Five open procedures as mcl-graph/<name> v1, and mcl-om's",
               "mcl-graph/info (macula 13.0.1). Publishes entity_learned_v1,",
               "link_learned_v1; subscribes to truth_asserted_v1. From mcl-om:",
               "node identity, pinned station dial, realm claim, provider",
               "grants, /health on 8482. Rust NIF mcl_graph_nif: CozoDB 0.7",
               "(rustler 0.38), built for baseline x86-64 (no AVX2).",
               "Storeless for mcl-om: no reckon-db is started."])

    s.element("b-cmp", 260, 350, 225, 120, "Graph data", "[bind mount]",
              ["/bulk0/mcl-graph at /data:", "CozoDB's RocksDB files,", "entities and links"])
    s.element("b-cmp", 515, 350, 225, 120, "Identity key", "[mcl-graph-secrets]",
              ["/etc/mcl/secrets:", "identity.key, the node id", "that signs every fact"])
    s.rect("b-later", 260, 490, 480, 44)
    s.text("t-desc", 276, 517, "reckon-db event store: offered by mcl-om (store_id/0), not used here")

    s.element("b-ext", 10, 96, 190, 80, "macula-mcp", "[MCP server]",
              ["outside the fleet"])
    s.element("b-ext", 10, 190, 190, 72, "Any realm member", "[mesh callers]", [])
    s.element("b-ext", 10, 276, 190, 80, "Truth producers", "[realm members]",
              ["truth_asserted_v1"])

    s.element("b-ext", 810, 96, 180, 76, "macula-station", "[pinned seed(s)]", [])
    s.element("b-ext", 810, 190, 180, 76, "macula-realm", "[trust anchor]", [])
    s.element("b-ext", 810, 280, 180, 90, "Graph consumers", "[subscribers]",
              ["compose many graphs"])

    s.text("t-rel", 230, 128, "calls", anchor="middle")
    s.text("t-rel", 230, 218, "calls", anchor="middle")
    s.text("t-rel", 230, 308, "publish", anchor="middle")
    s.text("t-rel", 10, 390, "all over the mesh, via the station")
    s.text("t-rel", 775, 126, "dials", anchor="middle")
    s.text("t-rel", 775, 220, "claims", anchor="middle")
    s.text("t-rel", 775, 302, "facts", anchor="middle")
    s.text("t-rel", 380, 340, "CozoDB (NIF)")
    s.text("t-rel", 635, 340, "loads")
    s.write("c4-containers.svg")


# ---------------------------------------------------------------------------
# Level 3: components of the service
# ---------------------------------------------------------------------------
def components():
    s = Svg(1240, 1190, "mcl-graph components")
    s.bound("bound", 16, 40, 960, 1016, "mcl-graph service [Container]")

    s.component("b-sys", 32, 76, 928, 84, "apps/mcl_graph: mcl_graph_service", "[mcl_om_service behaviour]",
                ["Six callbacks. capabilities/0: the five desks as mcl-graph/<desk> v1, handler {Desk, []}, auth => open.",
                 "identity_spec/0: scope mcl-graph, actions resolve, learn, narrate; 30 days. No store_id/0: storeless."])

    # What mcl-om provides
    s.bound("bound-in", 32, 180, 928, 112, "mcl_om 0.33.3 [library: what every mcl-om service gets]")
    om = [("b-cmp", "identity key", ["/etc/mcl/secrets;", "survives recreate"]),
          ("b-cmp", "station dial", ["pinned seeds + ids;", "{mesh, required}"]),
          ("b-cmp", "realm claim", ["boot claim; a D25", "grant per procedure"]),
          ("b-cmp", "info, /health", ["mcl-graph/info;", "/health on 8482"]),
          ("b-cmp", "ownership proof", ["v2 verify, used", "by learn_link"]),
          ("b-later", "event store", ["store_id/0: not", "used by mcl-graph"])]
    for i, (cls, name, desc) in enumerate(om):
        x = 48 + i * 150
        s.rect(cls, x, 208, 144, 68, rx=8)
        s.text("t-code t-small", x + 12, 228, name)
        s.text("t-desc", x + 12, 248, desc[0])
        s.text("t-desc", x + 12, 264, desc[1])

    # The service's own processes (mcl_graph_sup)
    s.bound("bound-in", 32, 312, 928, 148, "apps/mcl_graph [processes, under mcl_graph_sup, one_for_one]")
    s.component("b-cmp", 48, 344, 440, 100, "mcl_graph_store", "[gen_server]",
                ["Opens CozoDB at data_dir through the NIF; creates",
                 "entities and links, one statement per script. run/2:",
                 "every query, one at a time, with :timeout 10."])
    s.component("b-cmp", 504, 344, 440, 100, "learn_truths_from_mesh", "[gen_server]",
                ["Subscribes to truth_asserted_v1. A verified publisher's",
                 "fact goes through learn_link:learn/2 at confidence 0.7.",
                 "Resubscribes when gone or the pool dies."])

    # Desks
    s.bound("bound-in", 32, 480, 928, 250, "apps/mcl_graph [desks: macula_response handlers, one per procedure]")
    desks = [("resolve_link", "links out, in or both; up to 8 hops; at most 1000 rows"),
             ("resolve_entity", "attributes, first_seen, source; out and in degree; predicates"),
             ("learn_link", "insert entities, put the link, publish; caller linked asserted"),
             ("narrate_entity", "resolve_entity:resolve/1, then one sentence"),
             ("narrate_link", "resolve_link:resolve/1, then a sentence per link")]
    for i, (n, d) in enumerate(desks):
        s.row("b-cmp", 48, 512 + 42 * i, 896, n, d)

    # Shared modules
    s.bound("bound-in", 32, 750, 928, 142, "apps/mcl_graph [shared modules]")
    shared = [("mcl_graph_facts", "[topics, publish]", ["app_fact topics; publish", "via mcl_om_pubsub"]),
              ("mcl_graph_wire", "[reply shape]", ["text as {text, _}, 1/0;", "store_error to callers"]),
              ("narrate_template", "[sentences]", ["fixed templates; no", "model, no network"]),
              ("mcl_graph_nif", "[NIF stub]", ["loads priv/*.so on_load;", "no fallback"])]
    for i, (n, k, d) in enumerate(shared):
        s.component("b-cmp", 48 + i * 226, 782, 218, 96, n, k, d, small=True)

    # The native crate
    s.bound("bound-in", 32, 912, 928, 128, "native/mcl_graph_nif [Rust crate, cdylib, rustler 0.38]")
    s.component("b-cmp", 48, 944, 896, 80, "mcl_graph_nif.so", "[CozoDB 0.7 over RocksDB, DirtyIo]",
                ["One cozo::DbInstance behind a mutex: open, run_query, run_script, close. Errors are returned,",
                 "never raised. Built with -C target-cpu=x86-64: the beam boxes' Celeron J4105 has no AVX2."])

    # External to the container
    s.element("b-ext", 1000, 196, 224, 90, "macula-realm", "[trust anchor]",
              ["claim, grants, realm key"])
    s.element("b-ext", 1000, 344, 224, 100, "Truth producers", "[realm members]",
              ["publish truth_asserted_v1"])
    s.element("b-ext", 1000, 560, 224, 104, "macula-station", "[pinned]",
              ["carries the procedures,", "info and every fact"])
    s.element("b-ext", 48, 1100, 440, 64, "Graph data", "[/data, bind mount /bulk0/mcl-graph]", [])

    # Edges and labels
    s.edge("M960 242H1000"); s.text("t-rel", 980, 234, "claims", anchor="middle")
    s.edge("M1000 394H944"); s.text("t-rel", 971, 386, "hears", anchor="middle")
    s.edge("M1000 612H944"); s.text("t-rel", 971, 604, "calls", anchor="middle")
    s.edge("M268 480V444"); s.text("t-rel", 276, 470, "every desk: mcl_graph_store:run/2")
    s.edge("M724 444V480"); s.text("t-rel", 732, 470, "learn_link:learn/2")
    s.edge("M960 766H1112V664")
    s.text("t-rel", 1120, 686, "mcl_graph_facts")
    s.text("t-rel", 1120, 700, "publishes")
    s.text("t-rel", 1120, 714, "entity_learned_v1,")
    s.text("t-rel", 1120, 728, "link_learned_v1")
    s.edge("M835 878V944"); s.text("t-rel", 843, 915, "load_nif")
    s.edge("M268 1024V1100"); s.text("t-rel", 276, 1080, "entities and links (RocksDB)")
    s.write("c4-components.svg")


if __name__ == "__main__":
    os.makedirs(ASSETS, exist_ok=True)
    context()
    containers()
    components()
