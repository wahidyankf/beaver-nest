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

- [Commit authorization](commit-authorization.md) defines when commits and pushes may be performed.
- [Documentation architecture](documentation-architecture.md) organizes general non-rule documentation under `docs/` with Diátaxis.
- [GitHub polling](github-polling.md) limits repeated status requests to GitHub to avoid rate-limit pressure.
- [Governance directory maps](directory-maps.md) keep every governance directory self-describing and navigable.
- [Integration path](integration-path.md) makes direct pushes from local `main` the default and requires isolated, disposable worktrees for pull requests.
- [Last-resort questions](last-resort-questions.md) require exhausting safe ways to proceed before asking the user.
- [Markdown visualizations](markdown-visualizations.md) prefer useful Mermaid diagrams and require accessible color, contrast, and non-color cues.
- [Project READMEs](project-readmes.md) make every application and library independently understandable and operable.
- [Public repository data safety](public-repository-data-safety.md) prevents secrets and machine-local identifiers from entering public history.
- [Push-hook verification](push-hook-verification.md) requires root-cause repair and prevents unauthorized bypass of push-time safeguards.
- [Rule definition](rules.md) establishes what counts as a repository rule and how its strength, scope, and authority are interpreted.
- [Task tracking](task-tracking.md) requires granular task lists whose status stays synchronized with the work.
- [Thematic commits](thematic-commits.md) keep each commit focused on one coherent purpose.
