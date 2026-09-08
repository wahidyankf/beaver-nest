# HIPPO and RHINO Governance Adoption

**Status:** Done

**Created:** 2026-09-08

**Started:** 2026-09-08

**Completed:** 2026-09-09

**Scope:** Give `wahidyankf/hippo` and `wahidyankf/rhino` a governance hierarchy extracted — not copied — from this repository, an in-repository `worktrees/` tree, a three-harness contract with no Nx and no MCP server, a `main` ruleset that refuses direct pushes from every actor including the owner, and one merge-blocking pull-request gate per repository that is a superset of the local `pre-commit`, `commit-msg`, and `pre-push` contracts

## Outcome

Both repositories now carry a governance hierarchy, one merge-blocking pull-request gate, and a `main`
ruleset with no bypass actor: RHINO 49 documents at `5f7b75c`, HIPPO 51 at `065f200`. Every rule in the
two flat `AGENTS.md` files reached exactly one destination — 26 of 26 and 17 of 17 — and six documents
were authored beyond the adoption matrix because six of those rules had nowhere to land. Three
harnesses reconcile against a non-empty canonical roster in each repository, with no Nx and no
capability server. Every change landed through a pull request from `worktree/repo-rules-adoption`, and
both direct-push probes were refused by the server, by name.

Two criteria carry a stated qualification rather than a rounded-up pass, both in the
[criterion table](learnings.md#acceptance-criterion-reconciliation). **AC-04 is deliberately unmet for
HIPPO:** `go build` walks up out of a worktree and takes the outermost `.git` directory, so no ignore
rule inside the repository can reach the reader that breaks — HIPPO's worktrees stay beside the
checkout, and the reason is written where someone would otherwise undo it. **AC-05's HIPPO RED proved
three distinct refusal reasons rather than four**, because the `Test` job stopped at the first
violation it met instead of reaching the one written for it; the missing reason is evidenced locally
in the same branch.

Two defects were found by adopting the workflow rather than by testing it. A `pre-push` hook in a
linked worktree exports `GIT_DIR`, and HIPPO's fixtures inherited it — 168 empty commits reached a
live branch before anything noticed, and the repair is now held by a scenario. `go build` resolving
the wrong repository root reversed a phase mid-flight and became the recorded deviation above rather
than a silent workaround.

## Context

HIPPO and RHINO are this workstation's two shipped CLIs, and this repository depends on both: `./hippo` guards every heavy command and `./rhino` enforces the documentation contract. Both are public, both have shipped releases, and both already carry more discipline than a fresh repository would — Husky with commitlint and lint-staged, a `repo-config.yml` written against RHINO's own schema, Diátaxis `docs/`, and a `specs/` tree holding Gherkin plus a C4 model.

What neither has is the process layer this repository built around them. Their rules live in one flat `AGENTS.md` with no hierarchy, no precedence, and no navigation. Their `main` branches accept direct pushes from anybody with write access, which today is one person with admin rights and no server-side objection. Their pull-request CI is real but was never written to mirror the hooks, so a contributor whose hooks never ran can open a pull request that skips a contract the maintainer believes is enforced. Neither repository has a worktree convention, and neither is reachable by Codex or OpenCode with the same rules Claude Code receives — HIPPO's `repo-config.yml` currently prohibits `**/CLAUDE.md` outright.

The gap is not that these repositories are undisciplined. It is that their discipline is unaddressable: a rule that exists only as one bullet in a flat file cannot be linked to, cannot be superseded by an explicit precedence rule, and cannot be handed to three coding harnesses as the same instruction.

## Approach

Extract rather than transplant. This repository's governance tree contains roughly forty documents, and a large fraction of them describe a 24/7 Phoenix service behind Caddy on a Tailnet — Caddy deployment, LiveView reconnect, tailnet proxying, live-service continuity, database audit columns, runtime flat-file data, UI design, usability passes. None of that exists in a Go CLI or a Rust CLI. A second fraction is Nx-shaped, and HIPPO's own contributor rules say **never introduce Nx**. Copying either fraction would import contradictions and dead rules, and a governance tree whose documents do not apply teaches its readers to skim.

So the plan works from an explicit adoption matrix with three verdicts per document — adopt, adopt-adapted, reject — each with a stated reason, in [the governance restructure design](tech-docs/01-governance-restructure.md). Every one of this repository's fifty-four governance documents carries a verdict; thirty-eight survive per repository, plus two workflows authored here, plus a `README.md` at each level of the new tree. The `workflows/` level is part of that: the procedures are the part a maintainer actually re-reads, so worktree-to-pull-request, harness-contract change, harness-parity verification, Gherkin-implementation review, red-green-refactor, rules propagation, and a repository-specific release-cut all become workflow documents rather than prose buried in `AGENTS.md`.

Each repository ends with its own `vision/`, `principles/`, `conventions/`, `development/`, and `workflows/` tree and an `AGENTS.md` reduced to a link index. Every rule those repositories already wrote is redistributed into that hierarchy rather than discarded — this is a restructure of existing rules plus the missing process layer, not a replacement of a working policy with a borrowed one.

Three harnesses are wired without Nx and without an MCP server. RHINO's schema makes `required-mcp` optional and states plainly that a repository with harnesses may have no capability server, so the contract here is canonical skills, one canonical agent, three adapter sets, and a prohibition list — with `prohibited-instruction-fields` closing the vendor-settings route that a second `CLAUDE.md` would otherwise take in TOML or JSON syntax. The canonical roster is authored for these repositories, because all seven canonical skills in this repository are Nx skills and would be dead on arrival.

Integration moves to worktree-to-pull-request, and this plan is its own first user: every change it makes to either repository is authored in `worktrees/repo-rules-adoption/` on branch `worktree/repo-rules-adoption` — the same worktree and branch name this plan is being written under here, so one name identifies this work in all three repositories.

Each repository gains an in-repository `worktrees/` tree, ignored except for its placeholder and excluded from RHINO's scan and from every language toolchain's globs — an unexcluded worktree would double every Markdown file under the word budget, the link check, and the directory-map check, and would report findings against a copy of the repository. One `pr-quality-gate.yml` per repository becomes the sole required status check, absorbing everything today's `ci.yml` runs and adding the hook mirrors, after which `ci.yml` is deleted rather than demoted so there is one file to change when a hook changes. Then, and only then, a `main` ruleset refuses direct pushes, force pushes, and deletion for every actor with no bypass for anyone.

The ordering is the load-bearing part. RHINO goes first because it validates itself from a source build and can therefore prove a `repo-config.yml` change without a release; HIPPO can only validate through its pinned `v0.1.3` binary and would be blocked by any RHINO defect this work uncovers. Within each repository the gate must exist and report its check name on a real pull request before the ruleset can require that name, or the ruleset waits forever for a check that never runs.

## Deliberate Divergences From This Repository

Three places where copying would have been wrong, recorded here because they are the plan's least obvious choices:

- **No `./hippo` wrapper in CI.** This repository wraps every CI step in `./hippo run`. HIPPO arbitrates contention on one shared workstation; a GitHub runner is dedicated and ephemeral and has none, so the wrapper can only add a download, a checksum, and an exit-`75` failure mode that cannot occur. Local hooks keep the guard where contention is real. What CI gains instead is a bootstrap verification job that runs when a pinned consumer file changes — the thing that genuinely needs proving on a clean machine.
- **HIPPO cannot guard HIPPO.** RHINO's own `pre-push` hook already states this. HIPPO's hooks and gate therefore run unguarded, and its `resource-aware-development` document exists to explain why this one repository is the exception rather than to impose a rule it cannot follow.
- **No `plans/` tree in either repository.** The six-document formal plan shape is heavy for two single-maintainer CLIs that have shipped eight releases without it. Planning for both continues here, as this plan does. See non-goals in [the business requirements](brd.md).

## Dependencies

- RHINO `v0.1.3` is pinned by both repositories and by this one, and its harness-parity engine is already exercised here against that exact pin — so no new RHINO release is required to start. Should the schema refuse a shape this plan needs, RHINO must cut a release and HIPPO must move its pin, which is why RHINO is sequenced first.
- Admin rights on `wahidyankf/hippo` and `wahidyankf/rhino` to create the `main` rulesets. Both are public repositories, so rulesets and Actions minutes cost nothing.
- Local checkouts of both repositories and separate commit and push authorization in each; authorization does not cross a repository boundary.
- The empty the external `hippo-worktrees/` directory beside the checkout sibling directory, which this plan retires in favour of the in-repository tree.

## Navigation

- [Business requirements](brd.md)
- [Product requirements](prd.md)
- [Technical design](tech-docs/README.md)
- [Delivery checklist](delivery.md)
- [Learnings](learnings.md)

## Directory Map

- [`brd.md`](brd.md) — goal, roles, required outcomes, non-goals, and risk controls.
- [`delivery.md`](delivery.md) — ordered tasks, red-green-refactor cycles, and blocking checkpoints.
- [`learnings.md`](learnings.md) — dated evidence and decisions captured during delivery.
- [`prd.md`](prd.md) — maintainer stories and executable acceptance criteria.
- [`tech-docs/`](tech-docs/README.md) — technical entry point, the governance adoption matrix, the harness contract, the worktree and integration design, and the gate and ruleset design.
