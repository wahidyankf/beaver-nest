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
- [Integration path](integration-path.md) applies trunk-based development, routing every change through a `worktrees/` checkout and a pull request into `main`, the only persistent branch.
- [Last-resort questions](last-resort-questions.md) require exhausting safe ways to proceed before asking the user.
- [Language](language.md) makes English the repository's primary working language.
- [Markdown links](markdown-links.md) keep internal links resolvable across repository-owned Markdown.
- [Markdown visualizations](markdown-visualizations.md) prefer useful Mermaid diagrams and require accessible color, contrast, and non-color cues.
- [No destructive Git operations](no-destructive-git-operations.md) requires approval for any Git command that destroys work or history.
- [Plan lifecycle](plan-lifecycle.md) carries what this repository adds to the plans convention: idea quadrants, active-service clauses, and local delivery rules.
- [Plan migrations](plan-migrations.md) makes planned data transitions preserve sources, map compatibility, and prove recovery.
- [Plan specification changes](plan-specification-changes.md) makes behaviour, C4, test-binding, and file-impact work executable before implementation.
- [Plan UI design](plan-ui-design.md) requires lo-fi comparison and selected-direction hi-fi assets for UI-affecting formal plans.
- [Plan validator contract](plan-validator-contract.md) freezes what a plan-structure validator reads, the rule identifiers it emits, and the exits it returns.
- [Plan validator contract modules](plan-validator-contract/README.md) hold the ordered modules of that contract.
- [Plans](plans.md) defines the plan lifecycle, the six required documents, delivery, validation, evidence, and archival.
- [Plans modules](plans/README.md) hold the ordered modules that carry the complete plans rule.
- [Project READMEs](project-readmes.md) make every application and library independently understandable and operable.
- [Public repository data safety](public-repository-data-safety.md) prevents secrets and machine-local identifiers from entering public history.
- [Pull request body](pull-request-body.md) states what every description must carry and requires it to be rewritten whenever a push moves the head.
- [Pull request boundaries](pull-request-boundaries.md) map one branch to one pull request to one independently shippable delivery unit, split at natural seams.
- [Pull request merge](pull-request-merge.md) states the five preconditions and the draft lifecycle every merge into `main` must satisfy.
- [Push-hook verification](push-hook-verification.md) requires root-cause repair and prevents unauthorized bypass of push-time safeguards.
- [Rule definition](rules.md) establishes what counts as a repository rule and how its strength, scope, and authority are interpreted.
- [Runtime flat-file data](runtime-flat-file-data.md) defines the private `data/` layout and safe flat-file persistence boundaries.
- [Task tracking](task-tracking.md) requires granular task lists whose status stays synchronized with the work.
- [Thematic commits](thematic-commits.md) keep each commit focused on one coherent purpose.
