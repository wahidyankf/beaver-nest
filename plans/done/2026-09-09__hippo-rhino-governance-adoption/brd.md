# Business Requirements

## Goal

Make HIPPO and RHINO governable the way this repository is governable — addressable rules with a stated precedence, one integration path that the server enforces rather than the maintainer remembers, and the same instructions reaching all three coding harnesses — while keeping every rule those repositories already wrote and refusing every rule that describes a service neither of them is.

The failure this prevents is specific and has already happened once in this family of repositories: a rule that lives only as a bullet in a flat file gets re-decided by whoever is in front of it, and the same contract ends up implemented three times in three places. Here the same risk appears as a `main` branch that accepts a direct push, a pull request opened from a checkout whose hooks never ran, and two harnesses that never see the rules the third one does.

## Roles

- **Maintainer:** the sole owner of both repositories, with admin rights, who is also the only person who can merge and cannot approve their own pull request. Wants the rules to hold when they are tired, which means server-side, not conventional.
- **HIPPO (repository):** a Go CLI that arbitrates local compute. Adopts the governance layer additively; it has no validator to retire and no service to keep alive. Its one structural peculiarity is that it cannot run under its own guard.
- **RHINO (repository):** a Rust CLI that validates repository hygiene from declared configuration. Adopts the same layer, and additionally becomes the first repository to exercise its own harness-parity engine against a non-empty roster — from a source build, before anything is released.
- **This repository:** the source the rules are extracted from and the place planning continues to live. It is not a runtime dependency of either adoption and is not modified by this plan beyond the plan's own records.
- **Coding harnesses (Claude Code, Codex, OpenCode):** each must reach the same canonical rules, skills, and agent through its own native adapter, with no harness receiving an extra always-on instruction and none receiving a weakened permission.

## Required Outcomes

- Each repository carries a `repo-governance/` tree with `vision/`, `principles/`, `conventions/`, `development/`, and `workflows/` levels, a stated precedence in which a lower level may not contradict a higher one, and a `README.md` with a complete `## Directory Map` in every directory. Its `AGENTS.md` is a link index; every rule it holds today survives inside the hierarchy, and none is lost in the move.
- The `workflows/` level is populated, not nominal. A maintainer can open one document and execute worktree-to-pull-request, a harness-contract change, a harness-parity verification, a Gherkin-implementation review, a red-green-refactor cycle, a rules propagation, or that repository's release cut.
- Every adopted document was adopted for a reason recorded against it, and every rejected document was rejected for a reason recorded against it. No document describing a service, a database, a browser, an Nx workspace, or a plan lifecycle neither repository has enters either tree.
- Each repository has an in-repository `worktrees/` tree, ignored except for its placeholder, excluded from RHINO's scan, and excluded from every language toolchain's file discovery. A worktree present on disk changes no gate's result, and `hippo-worktrees/` is retired.
- Each repository declares a three-harness roster in `repo-config.yml` with canonical skills authored for that repository, one canonical agent, adapters for Claude Code, Codex, and OpenCode, prohibited instruction sources, and prohibited instruction fields — with no Nx skill, no Nx MCP capability, and no `required-mcp` at all. HIPPO's current prohibition on `**/CLAUDE.md` is replaced by a declared instruction adapter.
- Each repository has exactly one merge-blocking status check, produced by `pr-quality-gate.yml`, which runs everything that repository's `ci.yml` runs today plus a mirror of `pre-commit`, `commit-msg`, and `pre-push`. `ci.yml` is deleted in the same change, so no contract has two homes.
- Each `main` carries a ruleset that refuses direct pushes, force pushes, and branch deletion for every actor including the owner, requires linear history, requires the aggregate quality-gate check, and requires zero approving reviews. No bypass actor is configured.
- The ruleset is proved, not assumed: a direct push to `main` in each repository is attempted and observed to be refused, and the refusal is recorded.
- Each repository's `README.md` and `docs/` describe the world after this change: the hierarchy, the integration path, the gate, and the ruleset. A document that still describes direct pushes to `main` or a retired workflow is a defect, and each repository's own rule that documentation stays true to the built binary and does not contradict `specs/` continues to hold.
- Each repository's own specifications are assessed for impact before its changes land, and either updated in the same change or recorded as an evidenced no-op. Both repositories mandate this assessment before every repository change; this plan is not an exception to it.
- Every change this plan makes to either repository is itself delivered through a worktree and a pull request, including the changes made before the ruleset exists. The workflow is exercised before it is mandatory.
- All three repositories carry this work under one name: worktree directory `worktrees/repo-rules-adoption/` and branch `worktree/repo-rules-adoption`, matching the worktree this plan is authored in. A single `git branch` or `ls worktrees/` in any of the three answers "is this repository mid-adoption, and where".

## Non-goals

- **A shared governance package, submodule, or vendored kit.** The decision is to accept wording drift between three copies and converge only on the machine-checked layer — `repo-config.yml` and RHINO. Each repository's `repo-governance/README.md` states that this is a policy rather than an oversight, so a future reader does not mistake divergence for decay. Building a fourth released product to prevent prose drift is out of proportion to the harm.
- **A `plans/` lifecycle in either repository.** No `ideas/`, `backlogs/`, `in-progress/`, `done/`, no BRD, PRD, `delivery.md`, or plan quality gate. Planning for both CLIs continues in this repository.
- **Changing what either CLI does.** No product behaviour, command surface, exit code, configuration compatibility, or release artifact changes. Coverage floors, the `#![forbid(unsafe_code)]` rule, the exit-code contract, and the no-defaults rule are carried into the hierarchy unchanged.
- **Weakening any existing check to make the restructure land.** If a governed document exceeds the word budget the repository adopts, it is split; the budget is not raised to fit it, and the document is not trimmed of substance to fit the budget.
- **Adopting this repository's Nx-shaped quality-gate mechanics.** `nx affected`, project graphs, and Nx task routing do not enter either repository. The gate-routing idea survives; the tool does not.
- **Adopting `ose-public`, the private operations repository, `grind-in-public`, or any other sibling.** This plan covers two repositories.
- **Retiring or rewriting either repository's existing `ci.yml` checks.** They are absorbed intact into the new gate; the change is where they live and what blocks merge, not what they verify.

## Risks and Controls

- **Restructuring loses a rule.** Control: the move is proved by inventory, not by reading — every bullet in each current `AGENTS.md` is enumerated before the move and each is mapped to its destination document afterwards, with the mapping recorded in `learnings.md`. A bullet with no destination blocks the phase.
- **The governance tree becomes ceremony nobody reads.** Control: the adoption matrix requires a reason per document, and a document whose only justification is "this repository has one" is rejected. The word budget each repository adopts forces splitting rather than accretion.
- **RHINO's schema refuses a shape this plan needs** — for example a harness carrying a skill adapter without an agent adapter. Control: RHINO is sequenced first and validates itself from a source build, so the refusal surfaces before HIPPO is committed to anything. If a RHINO change is required it becomes a release and a HIPPO pin bump, both already routine.
- **The ruleset is created before the gate reports, and no pull request can ever merge.** Control: the required check name is taken from an observed successful run on a real pull request, never from the workflow file. The ruleset is the last step in each repository.
- **No bypass means a broken gate makes `main` unwritable.** Accepted deliberately. The control is that the gate is proved green on a real pull request in each repository before the ruleset is created, and that the gate's own definition is inside the repository, so the fix path is a pull request rather than an escalation.
- **An in-repository worktree contaminates a gate.** Control: exclusion is verified by creating a real worktree and re-running every gate to an identical result, not by reasoning about globs. This applies to RHINO's scan, Go package discovery, Cargo, Prettier, and the shell linters.
- **HIPPO's gate cannot run under HIPPO.** Control: stated as a governed exception in HIPPO's own `resource-aware-development` document rather than silently omitted, so a reader who knows the family rule finds its exception where they look for it.
