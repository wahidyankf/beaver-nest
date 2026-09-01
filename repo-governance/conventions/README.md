# Conventions

Conventions define shared choices that keep the repository predictable. They cover areas such as naming, directory layout, documentation, configuration, and version-control practices.

Conventions are subordinate to the repository [vision](../vision/README.md) and [principles](../principles/README.md), and take precedence over [development standards](../development/README.md) and [workflows](../workflows/README.md). A convention must change if it conflicts with either higher level; lower-level documents must change if they conflict with a convention.

Development-specific requirements belong in development standards, while ordered procedures belong in workflows.

A convention should state:

- the rule and its scope;
- the reason for the choice;
- a concise example when useful; and
- any explicit exception.

Prefer one canonical convention over repeating the same rule in several documents.

## Directory Map

- [Coding-harness contract](coding-harness-contract.md) keeps repository-owned rules, skills, custom agents, and required capabilities equivalent across supported coding harnesses.
- [Commit authorization](commit-authorization.md) defines when commits and pushes may be performed.
- [Database audit columns](database-audit-columns.md) require creation, change, and deletion provenance on every new relational table.
- [Documentation architecture](documentation-architecture.md) organizes general non-rule documentation under `docs/` with Diátaxis.
- [GitHub polling](github-polling.md) limits repeated status requests to GitHub to avoid rate-limit pressure.
- [Directory maps](directory-maps.md) keep governance, documentation, and specification trees self-describing and navigable.
- [Integration path](integration-path.md) makes local `main` to `origin/main` the repository's only integration route and prohibits pull requests.
- [Last-resort questions](last-resort-questions.md) require exhausting safe ways to proceed before asking the user.
- [Language](language.md) makes English the repository's primary working language.
- [Markdown links](markdown-links.md) keep internal links resolvable across repository-owned Markdown.
- [Markdown visualizations](markdown-visualizations.md) prefer useful Mermaid diagrams and require accessible color, contrast, and non-color cues.
- [Plan lifecycle](plan-lifecycle.md) moves rough ideas through backlogs, active execution, and completion while keeping as-built truth in specifications.
- [Plan migrations](plan-migrations.md) makes planned data transitions preserve sources, map compatibility, and prove recovery.
- [Plan specification changes](plan-specification-changes.md) makes behavior, C4, test-binding, and file-impact work executable before implementation.
- [Plan UI design](plan-ui-design.md) requires lo-fi comparison and selected-direction hi-fi assets for UI-affecting formal plans.
- [Project READMEs](project-readmes.md) make every application and library independently understandable and operable.
- [Public repository data safety](public-repository-data-safety.md) prevents secrets and machine-local identifiers from entering public history.
- [Push-hook verification](push-hook-verification.md) requires root-cause repair and prevents unauthorized bypass of push-time safeguards.
- [Rule definition](rules.md) establishes what counts as a repository rule and how its strength, scope, and authority are interpreted.
- [Runtime flat-file data](runtime-flat-file-data.md) defines the private `data/` layout and safe flat-file persistence boundaries.
- [Task tracking](task-tracking.md) requires granular task lists whose status stays synchronized with the work.
- [Thematic commits](thematic-commits.md) keep each commit focused on one coherent purpose.
