# Plan Specification Changes

Use this convention when a formal plan changes observable behavior, architecture, an interface, or an executable specification. It makes the specification work specific enough for a junior engineer to perform before implementation starts.

## Technical Documentation

In an unsplit plan, a `tech-docs.md` section owns planned specification work. In a naturally split technical set, use mapped `tech-docs/specification-changes.md` when specification work has a distinct reader job. For every affected C4 or Gherkin file, list its exact repository-relative path and one `[E]` update, `[N]` new, `[M]` moved, or `[D]` deleted label.

PRD Gherkin is plan-level acceptance language, not an automatic request to duplicate every scenario in canonical specifications. Before the file list, state which PRD outcomes become durable C4/Gherkin contracts and which remain plan-only. For every plan-only outcome, give its reason and exact `delivery.md` verification task; for every selected contract, name its target specification below.

Use one file heading with nested bullets instead of a wide table when several scenarios change. Put the planned delta in a fenced `diff` block: `-` remove/current behavior and `+` add/resulting behavior. Keep `= Preserve`, `→ Bindings`, and `✓ Proof` as normal Markdown bullets beneath it. Put a long scenario-scope list in a collapsed `<details>` block directly below the diff. A `[N]` file uses `+`; a `[D]` file uses `-`; a `[M]` file shows both paths; an `[E]` file shows only applicable markers.

For each Gherkin file, state:

- every existing scenario to preserve, update, move, or delete by name, and the resulting observable behavior;
- every new scenario by name, including its user, preconditions, action, and expected outcome;
- the exact unit, integration, and E2E binding/support/test file paths that change for it, or the specific incapable adapter and reason; and
- the target that proves the changed corpus and the focused journey that proves it at runtime.

For each C4 file, state the exact view, node, relationship, data store, or constraint that changes and why. Keep proposed design in plan documents; update `specs/` only with the final as-built result during execution. The relevant implementation phase in `delivery.md` must contain an `[AI]` task naming that canonical path and affected elements, with synchronized as-built content as its outcome and architecture/specification gates as proof; do not defer all C4 work to a generic documentation-cleanup task.

## File Impact

The File Impact section of `tech-docs.md`, or a mapped `tech-docs/file-impact.md` companion when that inventory benefits from a distinct reader job, must list every expected code, test, specification, documentation, configuration, and runtime path exactly. Do not use a directory, ellipsis, glob, or generic area as a substitute for a file. A runtime-instance template such as `<user-id>` is allowed only when the document defines who generates it and its fixed path shape. If an unmade human decision prevents naming a necessary file, make that decision a prerequisite and block execution; do not hide it in the tree.

Group a large File Impact tree into short area-specific blocks. Align concise annotations within each block; keep detailed behavior in the planned specification and architecture sections instead of creating an unreadable horizontal list.
