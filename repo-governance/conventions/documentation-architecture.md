# Documentation Architecture

Use the root `docs/` directory for general repository documentation that is not a repository rule. Keep canonical rules in `repo-governance/`, where the governance hierarchy and [rules-propagation workflow](../workflows/rules-propagation.md) apply.

Do not duplicate project READMEs, plans, governance, or other purpose-specific documents merely to populate `docs/`. Link to the existing canonical document when it already has an appropriate home.

Every Markdown file anywhere under `docs/` is exempt from the 500-word limit. That limit applies only to root `AGENTS.md` and Markdown under `repo-governance/`.

## Directory Maps

Every directory recursively under `docs/`, including `docs/` itself, must contain a `README.md`. Each README must use the same map structure as the [governance directory-map convention](directory-maps.md):

- include a `## Directory Map` section;
- list every direct sibling file and subdirectory other than the README itself;
- use relative links with concise descriptions;
- state explicitly when no siblings exist; and
- update the map in the same change as any direct sibling addition, removal, move, or rename.

The `badakmini-cli` check enforces both documentation and governance maps. Pre-push runs that check when pushed commits change Markdown anywhere or any content under `docs/`.

## Diátaxis Categories

Organize documentation in `docs/` according to the [Diátaxis framework](https://diataxis.fr/):

- `tutorials/` contains learning-oriented lessons that guide a learner through a successful experience.
- `how-to-guides/` contains goal-oriented directions for completing a practical task.
- `reference/` contains accurate, information-oriented descriptions for consultation during work.
- `explanation/` contains understanding-oriented discussions of context, relationships, reasons, and design.

Classify each document by the reader need it primarily serves. When material touches multiple categories, keep one primary document in the best-fitting category and link to complementary documents instead of blending or duplicating their purposes.

Each category `README.md` introduces its purpose and indexes the documents directly within that category.
