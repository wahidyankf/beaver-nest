# Markdown Visualizations

Use a visualization in Markdown when it makes relationships, sequence, state, hierarchy, dependencies, or another nontrivial structure materially easier to understand. Appropriate diagrams are encouraged because they can make dense documentation faster to read.

## Requirements

- Prefer a Mermaid diagram over ASCII art whenever Mermaid can express the needed visualization.
- Choose the smallest diagram type that communicates the point clearly, such as a flowchart, sequence diagram, state diagram, class diagram, timeline, or dependency graph.
- Place the diagram near the prose it supports and give nodes, edges, actors, and states meaningful labels.
- Include enough surrounding text that critical meaning remains understandable and searchable without relying on the image alone.
- Keep Mermaid source readable and compatible with the Markdown renderer used by the repository.
- Update a diagram in the same change when the documented behavior or structure it represents changes.

Use prose for a simple fact and a table for compact exact mappings. Do not add a diagram merely as decoration or duplicate information that is already clearer in another form. ASCII art may be used when Mermaid cannot represent the information adequately, the target renderer does not support Mermaid, or a plain-text fallback is specifically required.

This convention follows [progressive disclosure](../principles/progressive-disclosure.md) and [minimal sufficiency](../principles/minimal-sufficiency.md).
