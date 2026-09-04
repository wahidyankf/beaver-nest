# Architecture Specifications

Every logical application corpus under `specs/apps/<product>/<surface>/` must contain a canonical `architecture.md` C4 model. Implementation and dedicated E2E projects that share a corpus also share its architecture specification.

The model describes only the current, as-built system. Keep proposed or unimplemented designs outside the canonical model.

## Required Coverage

Each model must:

- identify its scope, people, software systems, runtime or deployment containers, external interfaces, and relationships;
- show persistent and temporary data stores plus material process, network, and trust boundaries;
- include a system-context view and the useful container views;
- include component views only where they materially clarify internal responsibilities;
- provide searchable prose for constraints that cannot be understood safely from diagrams alone; and
- link to the corpus's `behaviours/` directory and from each implementing project's README.

Use English and follow the repository [Markdown visualization convention](../conventions/markdown-visualizations.md).

## Scaling the Model

Keep one `architecture.md` while a reader can move from context to the relevant container or component without scanning unrelated detail and every diagram remains legible at normal Markdown width.

Split the model when any of these conditions is present:

- independent subsystem, component, deployment, or dynamic views serve different reader needs and make the entry point difficult to scan;
- a diagram requires zooming and cannot be simplified without losing material boundaries or relationships;
- unrelated areas need separate constraints or behaviour traceability; or
- independently evolving areas repeatedly create unrelated review noise or merge conflicts.

Do not split for anticipated growth alone. When splitting:

- retain `architecture.md` as the canonical entry point containing the scope, system context, shared constraints, and an index;
- place detailed files below `architecture/`, named by view or domain, such as `architecture/containers.md` or `architecture/components/chat.md`;
- give every statement and diagram one canonical home instead of duplicating it; and
- link each detail file back to the entry point and to its relevant behaviours and implementing projects.

## Change Discipline

Before changing application production code, read the canonical architecture model, relevant Gherkin, and tests. Assess architecture impact before implementation.

Update `architecture.md` in the same change whenever the implemented system changes a documented actor, system, container, component responsibility, relationship, interface, runtime or deployment boundary, data store, data flow, or security boundary. Keep the model synchronized with the final implemented state, including all affected views and prose.

Behaviour-only changes and implementation details below the documented component level do not require diagram churn when every architectural statement remains accurate. Record the architecture impact check in the delivery report either way.

Architecture maintenance complements the repository [BDD](behaviour-driven-development.md) and [TDD](test-driven-development.md) standards; it does not replace executable specifications or tests.
