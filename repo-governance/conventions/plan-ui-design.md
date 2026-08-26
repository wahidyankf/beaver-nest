# Plan UI Design

Apply this convention when an explicitly requested formal plan creates or materially changes user interface behavior. The goal is to make complex UI work reviewable before implementation without turning every working plan into a repository artifact.

## Required Exploration

Store project-bound design assets under `tech-docs/assets/` and link its required `README.md` from the plan map and `tech-docs/README.md`.

Embed all nine lo-fi assets and all three selected hi-fi assets in `tech-docs/ui-design.md`. Label each alternative and image group as selected or not selected, and show the decision rationale beside the comparison. The plan README displays at least one selected hi-fi preview and links the full comparison.

Use two fidelity stages for the same representative task and content:

1. Create three distinct lo-fi alternatives on desktop, tablet, and mobile: nine assets total.
2. Compare usability, accessibility, implementation cost, and product fit; name one selected alternative and explain why.
3. Create hi-fi assets only for the selected alternative on desktop, tablet, and mobile: three assets total.

When studying another product, record which artifact or interaction disciplines are adopted and which visual/product choices are rejected. Use references as evidence, not as permission to copy an unrelated identity.

Use accessible SVG by default for deterministic, diffable wireframes and mockups. Use raster only when photographic or bitmap fidelity is material. Every SVG needs a unique `<title>` and `<desc>`; every Markdown embed needs useful alt text. Do not rely on color alone.

Name assets `ui-<option>-<fidelity>-<device>.svg`, where fidelity is `lofi` or `hifi` and device is `desktop`, `tablet`, or `mobile`.

## Plan Documentation

`tech-docs/ui-design.md` must state:

- the UI's user, job, states, and real product copy;
- the three alternatives and their device behavior;
- the selected alternative, trade-offs, palette/type/layout tokens, and reusable components;
- keyboard, focus, error, empty, loading, reduced-motion, and responsive expectations; and
- exact implementation, test, specification, and asset paths through `tech-docs/file-impact.md`.

`delivery.md` must trace exploration, selection, implementation, accessibility checks, and affected-device manual verification to PRD acceptance criteria. Never include real accounts, credentials, cookies, private identifiers, or user data in an asset.
