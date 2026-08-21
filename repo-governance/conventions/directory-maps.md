# Governance Directory Maps

Every directory in `repo-governance` must contain a `README.md` that explains the directory and provides a map of its contents.

## Requirements

- Include a `## Directory Map` section in every `README.md`.
- List every direct sibling file and subdirectory other than the `README.md` itself.
- Use relative links and give each entry a concise description.
- When the README has no siblings, state that explicitly in the map.
- Update the map in the same change that adds, removes, moves, or renames a sibling entry.

This convention applies recursively to all current and future directories under `repo-governance`. It keeps governance discoverable while supporting the [progressive-disclosure principle](../principles/progressive-disclosure.md).

## Capacity

A complete map and the 500-word limit must both be satisfied. If a complete README would exceed the limit, divide its directory into coherent subdirectories until each README complies. Every new subdirectory must follow this convention. Never omit a sibling or waive the word limit to make a map fit.

The `badakmini-cli` check enforces README presence, map completeness, valid sibling links, and the word limit:

```sh
npm exec -- nx run badakmini-cli:test:repo
```
