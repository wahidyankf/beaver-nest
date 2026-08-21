# Project READMEs

Every application or library project rooted under `apps/` or `libs/` must contain a `README.md` at its project root. Add the README in the same change that creates the project.

## Document Roles

The repository-root `README.md` is the front door for Beaver Nest as a whole. It explains the shared purpose, repository-wide setup, layout, workflows, privacy boundaries, and links to deeper documentation.

A project README is the front door for one app or library. It explains that project's purpose, ownership boundary, interfaces, and local development tasks. Link to repository-wide information instead of duplicating it.

## Required Content

Tailor the document to its project, covering:

- the project name, purpose, and why it exists;
- what the project owns and explicitly does not own;
- project-specific prerequisites, setup, configuration, and common usage;
- relevant resolved Nx targets, shown as commands run from the repository root with the workspace package manager;
- important source, test, configuration, and entry-point paths;
- dependencies, consumers, APIs, or integration boundaries when relevant;
- how to test the project; and
- links to the root README and canonical architecture, security, operations, or governance documents.

Put the most useful information first. Use runnable examples. Omit inapplicable sections rather than leaving empty boilerplate, and move lengthy detail into linked documents.

## Maintenance

Every change to an app or library must include a README impact check. Update its README in the same change when purpose, boundaries, public interfaces, prerequisites, configuration, targets, structure, or operating procedure changes. If none are affected, no README edit is required.

Keep commands consistent with the project's resolved Nx configuration and keep all links valid. This convention follows [progressive disclosure](../principles/progressive-disclosure.md) and [minimal sufficiency](../principles/minimal-sufficiency.md).
