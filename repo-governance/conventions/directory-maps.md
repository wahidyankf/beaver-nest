# Directory Maps

Every directory in `repo-governance` must contain a `README.md` that explains the directory and provides a map of its contents.

## Requirements

- Include a `## Directory Map` section in every `README.md`.
- List every direct sibling file and subdirectory other than the `README.md` itself.
- Use relative links and give each entry a concise description.
- When the README has no siblings, state that explicitly in the map.
- Update the map in the same change that adds, removes, moves, or renames a sibling entry.

This convention applies recursively to all current and future directories under `repo-governance`. It keeps governance discoverable while supporting the [progressive-disclosure principle](../principles/progressive-disclosure.md).

## Specification Trees

Every directory recursively under `specs/`, including `specs/` itself, must contain a `README.md` with a `## Directory Map` section. Each specification map must link to every direct sibling file and directory other than its own README, regardless of file type.

Use relative links, concise descriptions, and the same empty-map statement and same-change maintenance requirements defined above. A directory link may target the child directory's required `README.md`.

Markdown files under `specs/` have no word limit. The 500-word governance limit applies only to root `AGENTS.md` and Markdown under `repo-governance/`.

## Capacity

A complete map and the 500-word limit must both be satisfied. If a complete README would exceed the limit, divide its directory into coherent subdirectories until each README complies. Every new subdirectory must follow this convention. Never omit a sibling or waive the word limit to make a map fit.

The `badakmini-cli` check enforces README presence, map completeness, valid sibling links, and applicable word limits:

```sh
npm exec -- nx run -p badakmini-cli -t test:repo
```
