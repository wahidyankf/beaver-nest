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

Markdown files under `specs/` have no word limit. The [750-word governance budget](#word-budget) applies only to root `AGENTS.md` and Markdown under `repo-governance/`.

## Planning Trees

Every directory recursively under `plans/`, including `plans/` itself, must contain a `README.md` with a `## Directory Map` section. Each planning map must link to every direct sibling file and directory other than its own README, regardless of file type.

Use relative links, concise descriptions, and the same empty-map statement and same-change maintenance requirements defined above. A directory link may target the child directory's required `README.md`.

Markdown files under `plans/` have no word limit. Organize and split plan content according to reader needs and the [plan-lifecycle convention](plan-lifecycle.md), never an arbitrary file-length ceiling.

## Word Budget

Root `AGENTS.md` and every Markdown file under `repo-governance/` must contain no more than 750 words. The budget keeps high-visibility rules scannable; it is a maximum, not a target. Markdown under `docs/`, `specs/`, and `plans/` is exempt.

Split or redistribute governance content when one document has distinct reader tasks, ownership, or navigation needs; do not split merely to use or avoid the budget. If a complete governance README would exceed 750 words, divide it into coherent subdirectories until every governed Markdown file complies. Every new subdirectory must follow this convention. Never omit a sibling to make a map fit.

Use the normal `wc -w <path>` command to check a document while authoring. The repository validator is authoritative because it applies the repository's Unicode-aware word-counting rule to every governed Markdown file.

The `badakmini-cli` check enforces README presence and directory-map completeness under governance, documentation, specification, and planning trees, plus applicable word limits:

```sh
./hippo run --class ephemeral --disk-path . -- npm exec -- nx run -p badakmini-cli -t test:repo
```
