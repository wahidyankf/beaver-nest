# Markdown Visualizations

Use a visualization in Markdown when it makes relationships, sequence, state, hierarchy, dependencies, or another nontrivial structure materially easier to understand. Appropriate diagrams are encouraged because they can make dense documentation faster to read.

## Requirements

- Prefer a Mermaid diagram over ASCII art whenever Mermaid can express the needed visualization.
- Choose the smallest diagram type that communicates the point clearly, such as a flowchart, sequence diagram, state diagram, class diagram, timeline, or dependency graph.
- Place the diagram near the prose it supports and give nodes, edges, actors, and states meaningful labels.
- Include enough surrounding text that critical meaning remains understandable and searchable without relying on the image alone.
- Keep Mermaid source readable and compatible with the Markdown renderer used by the repository.
- Update a diagram in the same change when the documented behavior or structure it represents changes.

## Mermaid Accessibility

Every Mermaid diagram must remain understandable to color-blind readers and legible in both light and dark rendering modes.

- Never encode meaning through color alone. Combine color with clear labels and, when distinctions matter, different shapes, line styles, icons, or symbols.
- Use blue `#0173B2`, orange `#DE8F05`, teal `#029E73`, purple `#CC78BC`, brown `#CA9161`, or gray `#808080` for fills; black `#000000` for borders; and black or white `#FFFFFF` for text.
- Do not use red, green, yellow, bright magenta, or light red/pink as diagram colors, including for success, failure, or warning semantics.
- Define colors with `classDef` and hex values rather than CSS color names or scattered inline styles. Use black borders for shape definition, white text on dark fills, and black text on light fills.
- Meet WCAG AA contrast ratios: at least 4.5:1 for normal text and 3:1 for large text.
- Include exactly one `%%` Mermaid comment identifying the palette used by each colored diagram.
- When adding or materially changing a colored diagram, render it in light and dark modes, check its contrast, and review it with at least one color-blindness simulation before publication.

Badakmini enforces colored `classDef` declarations in `flowchart`, `graph`, `classDiagram`, `stateDiagram`, `stateDiagram-v2`, `erDiagram`, `requirementDiagram`, and `block`. Unstyled diagrams pass. Other types remain human-reviewed because their styling semantics differ or are unstable. Automated checks require 4.5:1 contrast because rendered text size cannot be proven statically.

This Mermaid-only accessibility standard aligns with [OSE Public's diagram convention](https://github.com/wahidyankf/ose-public/blob/main/repo-governance/conventions/formatting/diagrams.md).

Use prose for a simple fact and a table for compact exact mappings. Do not add a diagram merely as decoration or duplicate information that is already clearer in another form. ASCII art may be used when Mermaid cannot represent the information adequately, the target renderer does not support Mermaid, or a plain-text fallback is specifically required.

This convention follows [progressive disclosure](../principles/progressive-disclosure.md) and [minimal sufficiency](../principles/minimal-sufficiency.md).
