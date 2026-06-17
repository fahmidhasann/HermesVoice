## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

## Design Context

Strategic and visual design are documented at the project root:
- `PRODUCT.md` — register, users, purpose, brand personality, anti-references, principles.
- `DESIGN.md` — visual system (colors, type, elevation, components) extracted from `Theme.swift`.

Register: **product** (macOS power-user tool; design serves the task).

Design principles (from PRODUCT.md):
1. Speed is the feature.
2. Recede, don't perform.
3. Craft you feel, not notice.
4. Warmth is the identity, never the volume.
5. Legible over anything.

Hard constraints: one accent only (Terracotta #D4816B, no second accent); translucent
chrome, near-solid content (ADR 0001); type ceiling 15px, no display type; flat by
default, depth on state; WCAG AA, never color alone, reduce-motion always handled. All
design tokens live in `Theme.swift` — never inline a raw value.
