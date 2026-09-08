# Learnings

Dated evidence and decisions captured during delivery. Empty sections are placeholders for the phases they name; nothing here is written before it is observed.

## Pre-Execution Findings

These were established while writing the plan and are recorded because each one changed its shape.

**2026-09-08 — RHINO `v0.1.3` already carries the harness-parity engine.** This repository exercises the full contract — canonical roots, routes, three adapter sets, translations, prohibitions — against the exact pin both HIPPO and RHINO already hold. The expected "release RHINO before anything else can start" dependency does not exist. It survives only as a dormant recovery item, for the case where the schema refuses a shape this plan needs.

**2026-09-08 — `required-mcp` is optional, and that is what makes a no-Nx contract possible.** RHINO's configuration reference states that a repository with harnesses may have no canonical skills, no canonical agents, and no capability server, and that `required-mcp` and the per-harness `capability` block oblige each other. Both repositories therefore declare neither, and no `.mcp.json` is created in either. Without this, "three harnesses without Nx" would have required a RHINO change first.

**2026-09-08 — both repositories' existing CI is stronger than their hooks.** HIPPO's `pre-push` runs `npm run test:quick` while its CI runs `scripts/test.sh` on two operating systems; RHINO's `pre-push` runs `cargo xtask test-quick` while its CI adds `cargo deny`, coverage tooling, and `cargo xtask self-validate`. A gate built to mirror the hooks literally would have been a downgrade the day it landed. This is why the gate is specified as a superset and why `ci.yml` is deleted rather than demoted.

**2026-09-08 — HIPPO's `repo-config.yml` prohibits `**/CLAUDE.md` today.** Adding Claude Code as a harness is therefore not additive; it requires moving that glob out of the prohibition list and into `canonical.instruction-adapter`. Nested `AGENTS.md` and `.claude/rules/**/*.md` take its place, so the boundary tightens overall — worth stating, because the diff alone reads like a loosening.

**2026-09-08 — HIPPO excludes `docs` from its mapped trees deliberately.** Its `repo-config.yml` records the reason: Diátaxis landing pages link into sections by name, which is a different contract from naming every direct sibling exactly once. Adding `docs` while adding `repo-governance` would have been precisely the blind adoption this plan exists to avoid.

**2026-09-08 — RHINO does not exclude `local-tmp` from its scan.** It is git-ignored, but RHINO walks the filesystem rather than the index, so scratch Markdown is reachable by the gate today. Unrelated to worktrees, found while designing the exclusion set, and fixed in the same phase.

**2026-09-08 — both repositories are public and neither `main` carries a ruleset or branch protection.** Rulesets and Actions minutes therefore cost nothing, and the before-state is unambiguous.

**2026-09-08 — every canonical skill in this repository is an Nx skill.** Seven of seven, plus one of two canonical agents being an Nx Cloud CI helper, and the one required capability being `npx nx mcp`. Porting the roster would have produced a parity contract over content neither repository can run, in a repository whose own rules forbid introducing the tool. The roster is authored instead.

## Plan Quality Gate — Pre-Execution Checkpoint

**2026-09-08 — cycle 1 — terminal result recorded below.** Authorized by the explicit direction to recheck the work before execution. Snapshot: plan at `plans/in-progress/hippo-rhino-governance-adoption/`, stage `in-progress`, beaver-nest revision `ebf70a021` on `worktree/repo-rules-adoption`, dirty paths limited to this plan folder and `plans/in-progress/README.md`. The only in-progress plan in the repository.

| ID    | Rule                                                                          | Location                         | Gap                                                                                                             | Repair                                                                                   | Status           |
| ----- | ----------------------------------------------------------------------------- | -------------------------------- | --------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ---------------- |
| QG-01 | No pre-created empty companions or placeholder artifacts                      | `learnings.md`                   | Eleven empty phase headers were created before any phase had content.                                           | Replaced with a statement that sections are created when they have content.              | `FIXED`          |
| QG-02 | Internal consistency of delivery                                              | `delivery.md` phases 1 and 6     | Phase 1 instructed removing the worktree that phases 2–5 depend on; phase 6 the same for 7–10.                  | Worktree and branch retained through each repository's phases and removed in phase 11.   | `FIXED`          |
| QG-03 | Every executable non-archived checkbox carries relevant `[AC-...]` labels     | `delivery.md` phase 11, recovery | Eight checkboxes carried `[AI]` with no acceptance label.                                                       | Labels added to each.                                                                    | `FIXED`          |
| QG-04 | Both repositories require a specification-impact assessment before any change | `delivery.md` phases 5 and 10    | No task assessed `specs/behaviours/` or `specs/architecture.md` impact, though both repositories mandate it.    | Added one `[AI]` task per repository, with a recorded verified no-op as a valid outcome. | `FIXED`          |
| QG-05 | Documentation stays true and must not contradict `specs/`                     | `delivery.md` phases 5 and 10    | No task updated either repository's `README.md` or `docs/` to match the new integration path, gate and ruleset. | Added one `[AI]` task per repository, and a required outcome in `brd.md`.                | `FIXED`          |
| QG-06 | Stop unneeded non-production processes before completion                      | `delivery.md` phase 11           | The completion requirement was unrecorded.                                                                      | Added the check, whose expected result is that none exists.                              | `FIXED`          |
| QG-07 | Plans progress `backlogs/` → `in-progress/`                                   | plan stage                       | The plan was created directly in `in-progress/`.                                                                | None required: explicit user direction placed it there, and the stage is truthful.       | `NOT_APPLICABLE` |

No row is `OPEN` or `BLOCKED`. Verification re-read only the repaired meaning and its cross-document effects, then ran the deterministic gate: repo-config, 32 diagrams, 57 files, three harnesses, 511 links and 48 directory maps, no findings.

**Terminal result: `PASS`** (cycle 1). It authorizes neither execution nor commit; both were separately directed.

## Material Input Change During Execution

**2026-09-08 — `main` moved eleven commits while the plan PR was open, and four of them changed this plan's inputs.** The branch was rebased onto `origin/main` and the whole incoming diff read before continuing, as the rewritten integration path requires.

What changed and what it cost:

- Three new conventions — `pull-request-body`, `pull-request-boundaries`, `pull-request-merge` — and one new workflow, `rules-grooming`. All four are directly about the thing these repositories are adopting, so all four are adopted. The corpus is fifty-four documents, not fifty; thirty-eight are adopted per repository rather than thirty-four.
- `integration-path` was rewritten around trunk-based development and now carries obligations the plan's design did not: sync before working and before resuming, one worktree per plan reused across delivery units, a measurable short-lived-branch limit, deleting all three artifacts rather than two, and invoking a release only from the primary checkout on local `main`. [The worktree design](tech-docs/03-worktrees-and-integration.md) was updated to match.
- `pull-request-boundaries` requires a plan to declare its delivery boundaries and work location, and requires a plan predating that rule to record both at execution start. `delivery.md` now does.
- `pull-request-merge` supplies the merge authority this execution runs on, and its draft lifecycle applies to every pull request from here. [The gate design](tech-docs/04-pr-gate-and-ruleset.md) now carries the five preconditions.
- `github-polling` moved from two minutes to three, and prohibits streaming or watching outright.

One deviation is recorded rather than repaired: pull request #8 was opened non-draft, because it was created before this convention was read. Every later pull request in this plan opens as a draft.

An empty probe commit, `ebf70a021 chore: probe whether direct pushes to main are refused`, was carried on the branch from before this work and never reached `main`. It was dropped during the rebase rather than merged: it changes no file and records nothing the ruleset itself does not already prove.

## Phase Records

_Appended as each phase completes. Sections are created when they have content, never before._

### Phase 0 — Baseline and Inventory

**2026-09-08 — baselines.** Both repositories clean on `main`. RHINO at `7d14ff595f0038e0abd9ebdf7c855d56b30f70a9`; HIPPO at `385531a86bfed9520163ee3adc2b05f4ff27710b`. Neither `main` carries a ruleset or branch protection, and both repositories are public — so rulesets and Actions minutes cost nothing.

RHINO gate baseline: `cargo xtask self-validate` reports 1 configuration file, 2 word-budget files, 7 directories, 109 links, 3 diagrams and 0 harnesses with no findings; `cargo fmt --all --check` clean. `cargo xtask` exposes exactly four tasks: `test-quick`, `self-validate`, `dist`, `checksums`.

**Correction, same day.** This entry first recorded Prettier as clean in RHINO. It is not: `docs/reference/configuration.md` is unformatted on `main` and has been. The first claim came from a glob that did not reach it; running Prettier over the tree does. The finding is real and its cause is structural — RHINO's `pre-commit` runs `lint-staged`, which only ever sees staged files, and neither its `test-quick` nor its `ci.yml` runs Prettier at all. So a file formatted before Prettier's rules changed, or edited outside a commit, drifts and nothing reports it. Recorded here rather than fixed in place: it is repaired in the unit that adds a formatting gate, which is where a formatting fix belongs, and that unit gains a repository-wide Prettier check rather than a changed-files-only one, because a changed-files check would never have caught this.

HIPPO gate baseline, exit `0`: `npm run test:quick` passes end to end, selected production line coverage `99.17%` (597/602 statements), three BDD adapters green, and the pinned RHINO documentation gate reports 1 configuration file, 2 directories, 0 budgeted files, 0 diagrams, 0 harnesses and 152 links with no findings.

**Two of those zeroes matter.** RHINO checks `0 harnesses` and HIPPO checks `0 harnesses` and `0 budgeted files`. The gates that this plan makes load-bearing are, today, passing vacuously. That is the enforcement gain stated as a number.

**2026-09-08 — check inventories.**

RHINO `ci.yml`: pinned toolchain install; `cargo fmt --all --check`; `cargo clippy --all-targets --all-features -- -D warnings`; `cargo install cargo-llvm-cov`; `cargo install cargo-deny` and `cargo deny check`; `cargo xtask test-quick`; `cargo xtask self-validate`. Its `pre-push` runs only `cargo xtask test-quick`, which itself contains fmt, clippy, the unit adapter under a 99% line-coverage floor, the static behaviour check, and self-validation. **The delta CI adds over the hook is exactly `cargo deny check`** — plus a redundant re-run of self-validate, named again so a failing repository is legible in the job list without opening a log.

HIPPO `ci.yml`: `commit-policy` running commitlint; `test` on `ubuntu-24.04` and `macos-15` running `scripts/test.sh`; `release-build` running `scripts/build-release.sh v0.0.0` and `tests/artifacts/release-assets.sh`. Its `pre-push` runs `npm run test:quick` = `scripts/test-quick.sh`, and `scripts/test.sh` is that plus `go test ./tests/integration`, `tests/e2e/run.sh`, a `-race` pass, and `go tool govulncheck`. **The delta CI adds is integration, E2E, race detection, vulnerability scanning, a second operating system, and the release-asset build.** `loaded-host.yml` runs nightly and is deliberately not a required check; it stays as it is.

**2026-09-08 — a containment risk confirmed by reading, before any worktree existed.** HIPPO's `scripts/format-check.sh` ends with `npm exec -- prettier --check --ignore-unknown .` — the whole tree. Prettier does not read `.gitignore`, so an in-repository worktree would be formatted-checked as a second copy of the repository. Neither repository's `.prettierignore` lists `worktrees`. Both need the entry, and HIPPO's is the one that would have failed loudly.

**2026-09-08 — a data-safety finding on the plan's own first pull request.** The pre-merge review of the head diff found a prohibited category — a machine-specific absolute path carrying the local operating-system username — in three locations across `README.md`, `delivery.md` and the worktree design. Beaver Nest is public, so that is prohibited content regardless of how harmless the directory itself is.

Remediated by replacing each with a repository-relative description, and the branch history was rewritten before the value could reach `main`; the pull request was never merged carrying it. Nothing was rotated because nothing was a credential.

Worth recording rather than quietly fixing: the value entered because the plan was describing a real directory on this workstation and the obvious way to name it was to paste its path. The convention anticipates exactly that, and the merge precondition is what caught it — the deterministic gate reported clean on the same head, because no tooling checks this.

**2026-09-08 — rule inventories.** Every numbered item must reach exactly one destination document in phase 4 or phase 9; an item with no destination blocks its phase.

HIPPO `AGENTS.md`, 17 rules: `H01` generic and repository-independent, no product-specific defaults · `H02` preserve exit codes 73/75/78, evidence readers and config compatibility absent owner authorization · `H03` assess both specification surfaces before every change · `H04` README, docs and CHANGELOG true to the shipped binary, Diátaxis one-section-per-page, never publish an unexecuted transcript, specs canonical · `H05` update every affected Gherkin scenario and C4 view in the same change, Gherkin-first, prove the binding failure, strict adapters, verified no-op over churn · `H06` every scenario through the unit adapter, no unit exemption, integration and E2E exemptions exact and named · `H07` `npm ci` for locked tooling, hooks enforce commits, staged formatting and the quick gate · `H08` Actions storage inside the free allowance, `$0` budget · `H09` `test:quick` for fast verification, `npm test` before release, never introduce Nx · `H10` documentation hygiene under the pinned RHINO release, change the declaration not the tool · `H11` deterministic production core coverage ≥99% · `H12` phase separation in Go functions by blank lines · `H13` generated, coverage, local, runtime-evidence and scratch paths stay ignored · `H14` never commit credentials, identifiers, absolute local paths or private infrastructure values · `H15` comment non-obvious shell safety invariants, no line-by-line narration · `H16` build release assets only through `scripts/build-release.sh` · `H17` never replace a tag or weaken checksum verification.

RHINO `AGENTS.md`, 26 rules: `R01` a generic validator that owns no repository's answers · `R02` ship no default a repository could decide differently · `R03` name no repository, harness or organization in `src/` · `R04` the policy/tool-behaviour line is whether a consumer could disagree and be right · `R05` exit 0/1/2 semantics, only validators report 1 · `R06` `version --json` shape is a public contract · `R07` no removal or rename without a major version · `R08` `specs/` canonical and at the root · `R09` assess Gherkin and C4 before every change, verified no-op over churn · `R10` Gherkin-first, prove the binding fails for the stated reason · `R11` no unit exemption; integration and E2E exemptions name the concrete boundary and the alternative proof, never difficulty, runtime, flakiness or cost · `R12` classify by the strongest real boundary touched; E2E is the process contract · `R13` `test-quick` holds only what is fast enough for every push; integration and E2E never in a hook · `R14` validator-module line coverage ≥99% with two declared exclusions · `R15` read-only, network-free, process-free, path-contained, no loopback · `R16` understand, reuse, stop at the smallest verified change; a dependency needs need, alternatives, evidence and an owned consequence · `R17` `#![forbid(unsafe_code)]` stays; `cargo deny check` gates · `R18` documentation true to the built binary, Diátaxis, no unexecuted transcript, no contradiction of specs · `R19` phase separation by blank lines · `R20` comment safety invariants, no narration · `R21` release assets only through `cargo xtask dist`, digests only through `cargo xtask checksums`, tag reachable from the default branch · `R22` never replace a tag, never weaken checksum verification · `R23` an archive per platform plus `checksums.txt`, embedded identity matching tag and commit · `R24` `npm ci` for locked tooling, hooks enforce commits, formatting and the quick gate · `R25` build output, coverage and scratch ignored · `R26` never commit credentials, identifiers, absolute paths or private infrastructure values.

## Rule Inventory Mapping

_Phase 0 produces the numbered inventories; phases 4 and 9 annotate each item with its destination document. A numbered item with no destination blocks its phase._

## Adoption Matrix Deviations

_Any document whose verdict changes during execution is recorded here with the evidence that changed it. The matrix in [the governance restructure design](tech-docs/01-governance-restructure.md) is a decision made from reading; execution is where it meets two real trees._
