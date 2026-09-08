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

**2026-09-09 — no completion cycle was run, because none was authorized.** The pre-execution cycle above was authorized by an explicit instruction to recheck the plan before executing it. No comparable instruction covers completion, and the rules make that distinction load-bearing: [the plan quality gate](../../../repo-governance/workflows/plan-quality-gate.md) says authorization is not to be inferred from creating, editing, reviewing, or executing a plan, and `AGENTS.md` says plan and rules quality gates require explicit requests. Archival does not depend on one — [the lifecycle](../../../repo-governance/conventions/plan-lifecycle.md) conditions it on reconciled delivery, acceptance, verification and learnings plus a clean deterministic gate, all of which are recorded above. Running an unrequested cycle here would have been the cheaper mistake to make, which is why the rule names it.

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

### Phase 1 — RHINO: Worktree Tree and Containment

**2026-09-08 — RED was louder than predicted.** With one real worktree present and no exclusion, `cargo xtask self-validate` from the primary checkout went from 109 links to 218 and from 3 diagrams to 6 — it was reading a complete second copy of the repository — and harness parity reported:

```
worktrees/repo-rules-adoption/CLAUDE.md: unexpected-instruction-source:
a second always-on instruction source competes with the canon
```

The gate did not crash. It reported a finding against a duplicate of the repository, which is the failure mode the design anticipated: findings that look real.

**GREEN, as a controlled toggle.** With a probe directory in place and only the `worktrees` exclusion changing:

| Exclusion | Links | Findings |
| --------- | ----: | -------: |
| present   |   109 |        0 |
| removed   |   125 |       15 |

The present row is identical to the pre-worktree baseline.

**The `.prettierignore` entry is load-bearing, and the first assumption about why was wrong.** The initial reasoning was that Prettier 3 reads `.gitignore`, making the entry redundant. Measured instead: a deliberately misformatted file inside the worktree is reported with no `.prettierignore` entry and silent with one, whether or not `.gitignore` covers the path. The entry stays because it is what does the work.

**Checkpoint 1 passed 2026-09-08.** From the primary checkout, with a populated worktree on disk: `git status` clean, and self-validate reporting 2 budgeted files, 7 directories, 109 links, 3 diagrams, 0 harnesses, no findings — identical to the Phase 0 baseline. Merged as `b867ed7`.

**A method error worth recording.** Two `cd`-dependent Bash calls were issued in parallel, and one ran in a checkout other than the intended one, producing an experiment result that looked meaningful and was not. Caught by re-establishing state before trusting it. Every later command in this execution uses an absolute path rather than relying on inherited working directory.

### Phase 2 — RHINO: Pull-Request Quality Gate

**2026-09-08 — the pre-push hook refused the first attempt, and was right.** `tests/coverage/main.rs` asserts that no gate file invokes a slow adapter, and it reads that list by filename, including `.github/workflows/ci.yml`. Renaming the workflow left the assertion pointing at a file that no longer exists, and the test reported that rather than passing vacuously — which is exactly what it was written to prevent. Repaired by moving the test with the file, never by loosening it. The README badge moved too.

This is the first concrete evidence for the plan's claim that a rename is never only a rename in these repositories.

**The planned hook bypass turned out to be unnecessary, which is a finding about the gate itself.** This plan assumed RED would require `--no-verify`: the local hooks make an unformatted, non-conventional, quick-gate-failing commit impossible to *create* in a working tree. They do not make it impossible to *push*. A probe commit built with `git commit-tree` against the branch tip never touches the working tree, so `pre-push` ran `cargo xtask test-quick` on a genuinely clean checkout, passed honestly, and let the push through.

No bypass was used anywhere in this phase. The evidence is stronger for it, because the probe now demonstrates the exact gap the gate exists to close: a hook can only attest to the checkout it ran in, and that checkout is not what the pull request contains.

**The first skip-refusal probe passed, and proved nothing.** An `if: false` job was added to the workflow on the probe branch but left out of the aggregate's `needs` list. The aggregate never observed it and reported success. A probe that passes for the wrong reason is indistinguishable from a gate that works, and the only reason it was caught was that a *failing* aggregate was the expected result. Rewired, [run 34234034045](https://github.com/wahidyankf/rhino/actions/runs/34234034045) reported:

```
Gate results: success success success success success skipped
A quality gate job did not succeed.
```

**Three hook contracts, three independent refusals.** One probe commit violating all of them at once, [run 34234437170](https://github.com/wahidyankf/rhino/actions/runs/34234437170):

| Job             | Result | Evidence                                                                    |
| --------------- | ------ | --------------------------------------------------------------------------- |
| Commit messages | fail   | `subject may not be empty`, `type may not be empty`                          |
| Formatting      | fail   | `Code style issues found in the above file`                                  |
| Quick gate      | fail   | `assertion left == right failed: deliberate probe failure`, `1 passed; 1 failed` |
| Quality gate    | fail   | aggregate                                                                    |

`Pinned HIPPO bootstrap` and `Supply chain` passed, correctly — the probe touched nothing they check.

**Checkpoint 2 passed 2026-09-08.** Every check from the phase-0 `ci.yml` inventory has a home in the new gate, each hook contract is refused independently, a skipped dependency is refused, `ci.yml` is deleted rather than demoted, and the merge landed as `ce2bb99` by rebase. The observed status-check name, read back from the check-runs API on the merged head, is **`Quality gate`**, reported by the `github-actions` app, integration id `15368`.

### Phase 3 — RHINO: The `main` Ruleset

**2026-09-08 — created after the check name existed, which is the whole ordering argument.** Ruleset `22550173`, targeting `~DEFAULT_BRANCH`, enforcement `active`, `bypass_actors: []`, and `current_user_can_bypass: "never"` as the server reports it back. Rules: `deletion`, `non_fast_forward`, `required_linear_history`, `pull_request` with zero required approvals and `required_review_thread_resolution`, and `required_status_checks` requiring `Quality gate` from integration `15368` with `strict_required_status_checks_policy`.

Zero required approvals is deliberate and is the reason [the merge preconditions](../../../repo-governance/conventions/pull-request-merge.md) carry the weight they do: a sole maintainer cannot approve their own pull request, so requiring one would block every merge and the preconditions stand in for the reviewer.

**The refusal, proved from the owner's own account.** A tree-identical empty commit on local `main`, pushed directly:

```
remote: error: GH013: Repository rule violations found for refs/heads/main.
remote: - Changes must be made through a pull request.
remote: - Required status check "Quality gate" is expected.
 ! [remote rejected] main -> main (push declined due to repository rule violations)
```

The local `pre-push` hook ran and passed first; the refusal is entirely the server's. Local `main` was reset to `origin/main` immediately afterwards.

**A first attempt failed for the wrong reason and was redone.** Local `main` was one merge behind, so the initial push was rejected client-side as a non-fast-forward before the server ever evaluated the ruleset. A rejection is not evidence unless it is the rejection you were testing for.

**Checkpoint 3 passed 2026-09-08.** No bypass actor exists, the ruleset is active, and a direct owner push is refused by name for both the pull-request rule and the required check.

### Phase 4 — RHINO: Governance Hierarchy

**2026-09-08 — the tree was invisible before it was declared.** With all 49 governance documents on disk and `repo-config.yml` unchanged, `cargo xtask self-validate` reported 2 budgeted files and 7 mapped directories — byte-identical to the phase-0 baseline taken when the tree did not exist. Declaring `repo-governance` as a mapped tree and adding the budget surfaces took it to 51 files and 13 directories.

The RED here is not a finding. It is the *absence* of findings against 49 unchecked documents, which is the same failure mode as a skipped gate job: it looks exactly like passing.

**The declaration was proved load-bearing in both directions, by controlled toggle.** Removing one sibling from `workflows/README.md` reported `missing map entry for repo-governance/workflows/release-cut.md`. Setting the budget to 300 reported 24 documents over it. Both restored, gate clean.

**Budgets were set from the finished tree.** Largest document 633 words (`rules-grooming.md`), budget 750. `AGENTS.md` 518 words, budget 650, down from 1200. A number chosen before the documents exist is a number, not a policy.

**The budget bound the same day, and the rule held.** A one-sentence pointer added to `README.md` took it from 1593 to 1607 against a 1600 limit. The sentence was rewritten to fit; the limit was not moved. This is the first live test of "never raise the budget", and it arrived within minutes of the budget existing.

**A wc-based estimate was wrong by 43%.** `wc -w` reported 363 words for the new `AGENTS.md`; the validator's `letters-and-digits` rule reported 518, because a Markdown link contributes one word per path segment and an index is nothing but links. Any budget reasoning done with `wc -w` on a link-dense document is reasoning about a different number.

**Three documents were authored beyond the adoption matrix**, recorded below as deviations: `conventions/working-tree.md`, `development/public-contract.md`, and `development/code-clarity.md`. Each exists because a rule in the phase-0 inventory had no destination in the 38 inherited documents, which is exactly the condition the inventory method was built to surface.

**Published transcripts were re-executed rather than trusted.** Four pages in `docs/` show `[word-budget] checked 2 files` output that could plausibly have been RHINO's own — now 51. Reproduced byte-for-byte against a purpose-built two-governed-file tree with this build: they describe a two-file repository, not this one, and remain true. Left unchanged, having been verified rather than assumed.

**Checkpoint 4 passed 2026-09-08.** 49 documents, 51 budgeted files, 13 mapped directories, 342 links, clean. All 26 inventoried rules mapped to exactly one destination, each verified by locating its own distinguishing phrase in the document claiming it. Merged as `97a22e6`.

**Phase 3's remaining item closed here.** With the ruleset active and `Quality gate` required, GitHub reported this pull request `MERGEABLE` / `CLEAN` and the merge succeeded — proof that the required name is the one the gate emits, obtained from a real delivery rather than a manufactured trivial pull request.

**Marking a draft ready re-runs the whole gate.** `pr-quality-gate.yml` listens for `ready_for_review`, so `gh pr ready` starts a second run at the same head and the aggregate goes pending again. The first merge attempt was refused by the base-branch policy for exactly this reason, and `gh pr checks` looked green because it was still showing the previous run's aggregate. Not a defect — the gate green is always for the ready head — but it costs one full cycle and it is a trap worth naming.

### Phase 5 — RHINO: Harness Contract

**2026-09-08 — all four open schema questions settled against the binary.**

| Question | Answer | Evidence |
| --- | --- | --- |
| Skill adapter without an agent adapter, and the reverse? | Both accepted. `skill-adapter` is optional per harness. | A roster with one harness carrying both and one carrying only an agent adapter validates clean. |
| Skill adapter with no `skills-root`? | Refused. | `line 24: skill-adapter: 'claude' declares a skill adapter, but no 'skills-root' names what it would express` |
| Canonical instruction against its own prohibition glob? | Exempt, and the glob is not inert. | `**/AGENTS.md` prohibited with `canonical.instruction: AGENTS.md` validates clean; adding `docs/AGENTS.md` reports `unexpected-instruction-source`. |
| `capabilities` non-empty with no `required-mcp`? | Accepted. | A four-name vocabulary with no `required-mcp` and no per-harness `capability` validates clean. |

**A fifth answer nobody asked for, and it is the important one.** `skills-root` declared with no `skill-adapter` on *any* harness is accepted — and a canonical skill sitting under that root then reconciles against nothing and reports clean. `canon 1 harnesses, 1 skills` with no findings. That is not a defect, because the two harnesses here genuinely read the canonical directory, but it means **a harness with no skill adapter has unverified skill coverage and the gate will not say so**. Anyone declaring `skills-root` has to know which harnesses they are choosing not to check.

**The skill surfaces were established by inspection, and the sibling repository's answer is now out of date.** Current vendor documentation: Codex scans `.agents/skills` at the current directory, at parents, and at the repository root; OpenCode scans `.opencode/skills`, `.claude/skills`, and `.agents/skills` project-locally; Claude Code scans only `.claude/skills`. So Codex and OpenCode need no adapter — the canon is already their surface — and Claude Code needs exactly one, at `.claude/skills/{name}/SKILL.md`. The sibling repository routes Claude skills through `.claude/commands/{name}.md`, which predates Claude Code having a skills surface at all. This repository uses the current one, and that divergence is a decision.

Codex's own settings key for competing instructions was **not** established. Only OpenCode's `instructions` array in `opencode.json` is declared under `prohibited-instruction-fields`. A prohibition naming a key nobody confirmed claims coverage it does not have.

**RED: the roster was empty while the canon was not.** Three canonical skills, one canonical agent, and six adapter files on disk; the gate reported `canon 0 harnesses, 0 skills, 0 agents, no findings`. Declaring the roots without the roster is refused outright: `line 53: skills-root: declared alongside an empty harness roster, so there is no harness to reconcile it against`.

**GREEN and REFACTOR: every denial proved by breaking it.**

| Weakening | Finding |
| --- | --- |
| `tools: Read, Glob, Grep, Bash` | `tools` grants `Bash`, which the canon denies |
| `permission.bash: allow` | `permission.bash` is not `deny` |
| `sandbox_mode = "workspace-write"` | `sandbox_mode` is not `read-only` |
| `allowed-tools` added to a closed wrapper | beyond what a wrapper may declare |
| canon copied into a wrapper | `body` is not the canonical route to `release-cut` |

**The instruction prohibition proved in both forms, and in all four states.** A nested `AGENTS.md` is reported. `opencode.json` carrying `"instructions": ["docs/extra-rules.md"]` is reported in the vendor's own syntax. The same key written `[]` is not. The file present without the key is not. A file that cannot be parsed as JSON is reported as `the file is not readable in its declared format` rather than assumed clean.

**Checkpoint 5 passed 2026-09-08.** `checked 3 harnesses, no findings` — `canon 3 harnesses, 3 skills, 1 agents, 0 reconciled capability declarations`. Three harnesses, no capability server, no `.mcp.json`, and no Nx anywhere. The shape this plan claimed the schema would permit is the shape it accepted.

**Phase 6 RED found a consumer no ignore rule can satisfy, and it reversed the phase.** The plan expected the readers to be the shell scripts' own globs. The reader turned out to be the Go toolchain. With the worktree at `hippo/worktrees/repo-rules-adoption`, every `go build` failed:

```
error obtaining VCS status: exit status 128
	Use -buildvcs=false to disable VCS stamping.
```

A shim on `PATH` recorded the command Go actually runs and where it runs it:

```
cwd=<repos>/hippo status=128 args=status --porcelain
```

The path is written `<repos>/` because the shim printed this workstation's real one, and the pre-commit data-safety inspection caught it here rather than in review: evidence pasted verbatim from a tool carries whatever the tool knew about the machine. That is the bare repository, not the worktree. Go resolves the version-control root by walking up from the module and taking the **outermost** directory holding a `.git`, and it does not accept a `.git` *file* as one — so it walks past the worktree's own `.git` file and stops at `hippo/.git`, which is a bare repository where `git status` is fatal by definition.

The failure was not confined to this workstation's layout. A purpose-built ordinary clone — worktree inside, both checkouts committing — produced a binary stamped with the wrong revision and no error at all:

| | |
| --- | --- |
| main checkout HEAD | `d9543145ddf64e27ac05c8e6febd77a53a7adc6e` |
| worktree HEAD | `75fe89023e7be80fa2dc8485702efb2ea2ea4724` |
| `vcs.revision` in the binary | `d9543145ddf64e27ac05c8e6febd77a53a7adc6e` |

`vcs.modified=true` came with it, because the main checkout sees the worktree directory as untracked. A Go binary built from a worktree inside its own repository carries the other checkout's provenance and calls itself dirty, and nothing says so.

So the containment change was reverted for HIPPO and the worktree moved back outside the repository, where Go finds no root above it and stamps nothing rather than stamping a lie. `go build ./cmd/hippo-conformance` succeeds there.

**A background command's exit code described the wrapper, not the work.** The Phase 6 push was reported as "completed (exit code 0)". Its captured output ended `husky - pre-push script failed (code 1)` and `error: failed to push some refs`. The push never happened. Nothing downstream had noticed, because the notification was the only thing read. The captured output is the evidence; the notification is not.

**A test suite wrote 168 empty commits onto the live branch.** During that same failed push, `npm run test:quick` left 168 commits authored `HIPPO fixture <fixture@example.invalid>`, subject `fixture`, on `worktree/repo-rules-adoption`. Every tree was identical to the real head, so `git update-ref` back to it restored the branch without touching a file. Re-running the unit package alone reproduced neither the commits nor anything that would explain them, and that was the clue: the difference between the two runs was not the tests but the **caller**.

A `pre-push` hook **in a linked worktree** exports `GIT_DIR`. In an ordinary checkout it does not. Two scratch repositories, the same hook printing its own environment:

| Hook run from | `GIT_DIR` in the hook's environment |
| --- | --- |
| an ordinary checkout | absent |
| a linked worktree | `.../repo/worktrees/wt` |

HIPPO's fixture helpers build their git commands with the ambient environment, and git prefers `GIT_DIR` over the directory a command was started in. So under `pre-push` every fixture `git init` re-initialises the repository under test and every fixture `git commit` lands on its checked-out branch. Reproduced from first principles:

```
$ cd empty-fixture-directory
$ GIT_DIR=../repo/.git git init -q -b main
warning: re-init: ignored --initial-branch=main
$ GIT_DIR=../repo/.git git -c user.name="HIPPO fixture" ... commit --allow-empty -q -m fixture
```

The fixture directory stays empty and the real repository's HEAD moves. Every `t.TempDir()` in the suite is correct and irrelevant: the isolation is defeated by an environment variable, not by a path. The suite is hermetic when a human runs it, and not hermetic when a hook in a worktree does — which, after this plan, is the one caller that runs it before every push. The defect was latent for as long as it was, because it needs both conditions at once: fixtures that inherit the environment, and an integration path that works in worktrees. This plan supplied the second. Adopting a workflow is also a test of it.


**The fix, and a first attempt at proving it that proved nothing.** Two layers, because there are two kinds of caller. `tests/support/git.go` builds every fixture Git command with `GIT_*` stripped from the environment — all of it, not the handful known to redirect a write today, since the set grows with Git and a fixture that quietly followed a new one would fail the same way for a new reason. `scripts/test-quick.sh`, `scripts/test.sh` and `scripts/build-release.sh` unset the same variables at the top, because the shell layer has its own exposure: `build-release.sh` runs `git -C "$source_root" checkout --detach`, and `-C` does not override `GIT_DIR`, so under a hook that detaches the real repository's HEAD.

The scenario was written first and bound in all three adapters. Removing the sanitiser and re-running `go test ./tests/bdd` reported success — and that was the same trap as the skipped-job probe in phase 2. `tests/bdd` resolves bindings; it does not execute scenarios. The executing adapters do. Re-run against the one that actually runs it:

```
[FAIL] TestUnitBehaviours/Fixture_Git_work_ignores_the_repository_a_hook_names
     read fixture head: exit status 128
```

Exit `128` because the fixture directory holds no repository at all — the commit went to the one named in the environment. Restoring the sanitiser turns it green. **Twice now, a passing probe has meant "the check never ran".** The lesson is not about either bug: it is that "the suite passed" is only evidence if you can name the test that executed.

### Phase 7 — HIPPO's Pull-Request Gate

**2026-09-08 — the RED had to be built with plumbing, and that is a finding about the hooks.** The four violations this phase needed — a non-conventional subject, an unformatted file, a failing quick check, a broken link — are exactly the four things HIPPO's hooks make impossible to *create* in a working tree, and `--no-verify` is prohibited here. A commit built with `git commit-tree` against a scratch index never touches the checkout, so `pre-push` ran the quick gate on a genuinely clean tree, passed honestly, and let the violating commit reach the pull request the gate had to refuse. The hooks were not bypassed; they were asked a different question.

**The gate refused all four, and the aggregate refused the run.** [Run 34249416169](https://github.com/wahidyankf/hippo/actions/runs/34249416169): `subject may not be empty` and `type may not be empty`; `README.md` code style issues; `README.md:228: docs/does-not-exist.md does not exist` after 153 links; `Gate results: failure failure failure failure success success`. `Release build` and `Pinned RHINO bootstrap` passed, which is the correct answer for a probe that touched neither surface.

**One job failed for the wrong reason, and it is recorded rather than smoothed.** The `Test` job failed at `scripts/test.sh`'s formatting step, before it ever reached the unit test written to fail. So that job proved it runs `test.sh` and refuses on the first violation it meets — not that it runs the unit adapter. Under a stricter reading the RED is four jobs failing and three reasons proven. The unit adapter's own refusal is evidenced separately and locally in the same branch: adding the new Gherkin step before its binding reported `undefined behavior step "the quality gate runs on pull requests rather than pushes"`.

**Skip refusal, proved in isolation.** [Run 34250431194](https://github.com/wahidyankf/hippo/actions/runs/34250431194) carried an `if: false` job wired into the aggregate's `needs` and nothing else wrong. Every real job reported `success`, `Skip probe` reported `skipped`, and the aggregate refused: `Gate results: success success success success success success skipped`. Isolation mattered here — phase 2's first attempt at this in RHINO passed for the wrong reason, and a probe whose branch also carries an unrelated failure cannot tell you which one the aggregate objected to.

**Dropping a requirement is the one edit that weakens a gate silently, so it was replaced by a stricter one.** Deleting `ci.yml` removed its `Validate pushed commits` job, and `tests/support/driver.go` asserted that job existed. The honest options were to keep a push-event job that re-lints history the gate has already approved, or to drop the assertion. Neither is good: the second quietly widens what the contributor gate is willing to accept. The scenario now asserts the gate's whole *trigger set* — `the quality gate runs on pull requests rather than pushes` — so reintroducing a push trigger is a reported failure. A dropped assertion should leave behind a stronger one, not a gap.

**A stale remote ref after a rebase merge is not a fast-forward, and force-updating it was refused.** Pull request #5 merged by rebase, so `main` gained a copy of the branch tip and the branch's own ref was left pointing at a commit no longer reachable. `--force-with-lease` was denied by this workstation's tooling. The refspec was retired in the same push that published the probe — one push, two refspecs, one pre-push quick gate — and the branch re-created fresh. The knock-on is recorded in `delivery.md`: GREEN was observed on the delivery pull request rather than on the RED one, because reaching GREEN in place needs a rewritten commit message and therefore a force update.

**The hermetic fix held under its real caller.** Every push in this phase ran the `pre-push` quick gate from inside a linked worktree — the exact condition that wrote 168 commits in phase 6 — and each one recorded `repository history: unchanged` with the local head where it was left.


### Phases 8–10 — HIPPO's Ruleset, Hierarchy and Harness Contract

**2026-09-08 — the ruleset, created after the check name existed.** Ruleset `22562053`, `bypass_actors: []`, `current_user_can_bypass: "never"`, requiring `Quality gate` from integration `15368` under a strict policy. A fast-forward commit with an *unchanged tree* — so no client-side rejection was possible and only the server could refuse it — was declined:

```
remote: - Changes must be made through a pull request.
remote: - Required status check "Quality gate" is expected.
```

**The same absence-shaped RED, twice more.** Phase 9: 51 governance documents on disk and the gate reported `0 files budgeted, 2 directories mapped` — byte-identical to the baseline taken when the tree did not exist. Phase 10: three skills, one agent and six adapter files on disk and the gate reported `canon 0 harnesses, 0 skills, 0 agents`. In both cases the declaration is what makes the content visible, and in both cases the undeclared state looks exactly like a clean repository. This is now the third time in this plan that a passing check meant "the check never ran".

**A ruleset makes a carried finding impossible, and that moved a plan item.** The plan put `CLAUDE.md` in phase 9 and its prohibition finding in phase 10's RED. With `main` requiring a clean `Quality gate` and no bypass, a pull request carrying that finding cannot merge — so the finding has to be raised and resolved inside one delivery unit. `CLAUDE.md` moved to phase 10, where its RED and GREEN already lived. Ordering a plan's phases is also ordering what may be broken between them, and a no-bypass ruleset removes the slack a multi-phase RED assumes.

**The prohibition set tightened while the prohibition was being lifted.** Moving `**/CLAUDE.md` to `canonical.instruction-adapter` reads like a loosening. In the same edit the list went from three globs to eight, `.cursorrules` widened to `**/.cursorrules`, `**/CLAUDE.md` *stayed* on the list — the validator exempts the canonical instruction and its declared adapter and keeps reporting every nested one — and `opencode.json`'s `instructions` array was added in field form. Six probes confirmed each half, including the two negatives that matter: `"instructions": []` is not a finding, and the file present without the key is not a finding.

**The word budget did the job it exists for, on the one document nobody wanted to shorten.** Adding the integration path to `README.md` took it from 1583 counted words to 1743 against a 1600 limit. Trimming three words would have passed and left the document permanently at its ceiling. What actually fixed it was deleting what the README had no business restating: the contributor rules it now links to, and a "Popular entry points" list that duplicated `docs/README.md`, the Diátaxis landing page whose whole job that is. A budget is only useful if the answer to exceeding it is never a larger number.

**A specification gap that predates this plan, found by assessing rather than by failing.** HIPPO's pinned RHINO gate has run since it was adopted and no scenario said so. A `docs-check.sh` that stopped asking one of its six questions would still have exited zero, and the check that no longer ran would have looked exactly like the check that passed. `Documentation hygiene wiring is complete` now names both properties — one shared definition, and every validator by name rather than by count. The C4 assessment for the same change was a verified no-op on content: a coding-harness roster is repository configuration and crosses no boundary in the guard.


## Rule Inventory Mapping

_Phase 0 produces the numbered inventories; phases 4 and 9 annotate each item with its destination document. A numbered item with no destination blocks its phase._

### RHINO — 26 rules, 26 destinations

Verified 2026-09-08 against `origin/main` at `b17503b`. Paths are relative to `repo-governance/`.

| # | Rule | Destination |
| --- | --- | --- |
| R01 | A generic validator that owns no repository's answers | `vision/README.md` |
| R02 | Ship no default a repository could decide differently | `vision/README.md` |
| R03 | Name no repository, harness or organization in `src/` | `development/software-quality-enforcement.md` |
| R04 | The policy/tool-behaviour line is whether a consumer could disagree and be right | `vision/README.md`, `workflows/rules-quality-gate.md` |
| R05 | Exit `0`/`1`/`2` semantics; only validators report `1` | `development/public-contract.md` |
| R06 | `version --json` shape is a public contract | `development/public-contract.md` |
| R07 | No removal or rename without a major version | `development/public-contract.md` |
| R08 | `specs/` canonical and at the root | `development/specification-maintenance.md` |
| R09 | Assess Gherkin and C4 before every change; verified no-op over churn | `development/specification-maintenance.md`, `development/architecture-specifications.md` |
| R10 | Gherkin-first; prove the binding fails for the stated reason | `workflows/gherkin-implementation-review.md`, `development/specification-maintenance.md` |
| R11 | No unit exemption; integration and E2E exemptions name the concrete boundary and the alternative proof | `development/specification-maintenance.md`, `development/end-to-end-testing.md` |
| R12 | Classify by the strongest real boundary touched; E2E is the process contract | `development/specification-maintenance.md`, `development/behaviour-driven-development.md` |
| R13 | `test-quick` holds only what is fast enough for every push | `development/quality-gates.md` |
| R14 | Validator-module line coverage ≥99% with two declared exclusions | `development/software-quality-enforcement.md` |
| R15 | Read-only, network-free, process-free, path-contained, no loopback | `development/software-quality-enforcement.md` |
| R16 | Understand, reuse, stop at the smallest verified change; a dependency needs need, alternatives, evidence and an owned consequence | `principles/minimal-sufficiency.md`, `development/dependency-selection.md` |
| R17 | `#![forbid(unsafe_code)]` stays; `cargo deny check` gates | `development/dependency-selection.md`, `development/software-quality-enforcement.md` |
| R18 | Documentation true to the built binary; Diátaxis; no unexecuted transcript; no contradiction of specs | `conventions/documentation-architecture.md` |
| R19 | Phase separation by blank lines | `development/code-clarity.md` |
| R20 | Comment safety invariants; no narration | `development/code-clarity.md` |
| R21 | Release assets only through `cargo xtask dist`; digests only through `cargo xtask checksums`; tag reachable from the default branch | `workflows/release-cut.md` |
| R22 | Never replace a tag; never weaken checksum verification | `workflows/release-cut.md` |
| R23 | An archive per platform plus `checksums.txt`; embedded identity matching tag and commit | `workflows/release-cut.md` |
| R24 | `npm ci` for locked tooling; hooks enforce commits, formatting and the quick gate | `development/quality-gates.md` |
| R25 | Build output, coverage and scratch ignored | `conventions/working-tree.md` |
| R26 | Never commit credentials, identifiers, absolute paths or private infrastructure values | `conventions/public-repository-data-safety.md` |

No rule was dropped and none was softened. Three destinations are documents the adoption matrix did not allocate — `conventions/working-tree.md`, `development/public-contract.md`, `development/code-clarity.md` — recorded below as deviations.

### HIPPO — 17 rules, 17 destinations

Verified 2026-09-08 against the tree at commit `4e478d2`. Paths are relative to `repo-governance/`.

| # | Rule | Destination | Weakened? |
| --- | --- | --- | --- |
| H01 | Generic and repository-independent; no product-specific defaults | `principles/repository-independence.md` | No — restated as an absolute, with the reason a default cannot be retracted |
| H02 | Preserve exit codes `73`/`75`/`78`, evidence readers, config compatibility | `development/public-contract.md` | No |
| H03 | Assess both specification surfaces before every change | `development/specification-maintenance.md` | No |
| H04 | README, `docs/` and CHANGELOG true to the binary; Diátaxis; no unexecuted transcript; `specs/` canonical | `conventions/documentation-architecture.md` | No |
| H05 | Gherkin and C4 updated in the same change, Gherkin-first, prove the binding failure, strict adapters, verified no-op | `development/specification-maintenance.md`, `development/architecture-specifications.md`, `workflows/gherkin-implementation-review.md` | No — gains a named review workflow |
| H06 | Every scenario through the unit adapter; no unit exemption; integration and E2E exemptions exact and named | `development/behaviour-driven-development.md`, `development/end-to-end-testing.md`, `development/specification-maintenance.md` | No — the exemption rule now names an accepted and a rejected reason |
| H07 | `npm ci` for locked tooling; hooks enforce commits, staged formatting and the quick gate | `development/dependency-selection.md`, `development/quality-gates.md` | No |
| H08 | Actions storage inside the free allowance, `$0` budget | `development/github-actions-storage.md` | No |
| H09 | `test:quick` for fast verification, `npm test` before release, never Nx | `development/quality-gates.md` | No |
| H10 | Documentation hygiene under the pinned RHINO; change the declaration, not the tool | `development/dependency-selection.md` | No |
| H11 | Deterministic production core coverage at or above 99% | `development/quality-gates.md`, `development/test-driven-development.md` | No |
| H12 | Phase separation in Go functions by blank lines | `development/code-clarity.md` | No |
| H13 | Generated, coverage, local, runtime-evidence and scratch paths stay ignored | `conventions/working-tree.md` | No |
| H14 | Never commit credentials, identifiers, absolute local paths or private infrastructure values | `conventions/public-repository-data-safety.md` | No |
| H15 | Comment non-obvious shell safety invariants; no line-by-line narration | `development/code-clarity.md` | No |
| H16 | Build release assets only through `scripts/build-release.sh` | `workflows/release-cut.md` | No |
| H17 | Never replace a tag or weaken checksum verification | `workflows/release-cut.md` | No |

No rule was dropped and none was softened. Three destinations are documents the adoption matrix did not allocate; they are recorded below as deviations.

## Rules Propagation

**2026-09-09 — `PASS_NO_CHANGE`.**

Propagation applies to rule changes made **in this repository**. This plan made none: beaver-nest received one plan folder under `plans/` and no rule was created, changed, moved, or deleted. The ledger is therefore empty, no repair was needed, and step 4's verification passed on the unchanged tree:

```
[harness-parity] checked 3 harnesses, no findings
[harness-parity] canon 3 harnesses, 7 skills, 2 agents, 3 reconciled capability declarations
[directory-map] checked 48 directories, no findings
[internal-link] checked 544 links, no findings
NX   Successfully ran target test:repo for project rhino-consumer
```

**Propagation stops at this repository's boundary, and that is the point here rather than a technicality.** The two adopted trees now govern themselves: RHINO and HIPPO each own their `repo-governance/`, each declares its own `repo-config.yml`, and each is entitled to diverge. `conventions/rules.md` in both trees says so in their own words — divergence is expected, undocumented divergence is not. Anything else would make one repository's grooming pass a silent edit to two others, which is exactly the coupling [repository independence](../../../repo-governance/principles/repository-independence.md) exists to prevent.

The corollary is that this plan's changes to RHINO and HIPPO are **not** propagated from here and never will be. They were authored in those repositories, gated by those repositories' own checks, and merged through those repositories' own rulesets.

**No server, watcher, candidate or proxy was left running.** Checked at reconciliation: the only long-lived local processes are pre-existing bnest infrastructure and editor tooling, none started by this plan, and the propagation command left no Nx daemon behind. Neither adopted repository is an active service, so no routed-revision verification applies.

## Acceptance Criterion Reconciliation

_Completed 2026-09-09. Each criterion is judged against recorded evidence, not against intent. RHINO is at `origin/main` `b17503b`; HIPPO at `065f200`._

| Criterion | RHINO | HIPPO | Evidence |
| --- | --- | --- | --- |
| **AC-01** Governance extracted, verdict per document | MET | MET | 49 and 51 documents. Both rule inventories map completely — 26 of 26 and 17 of 17, tabled above. Six documents across the two repositories were authored beyond the adoption matrix because an inventoried rule had no destination; each is recorded as a deviation with its reason. |
| **AC-02** Instruction file is an index; hierarchy navigable | MET | MET | Both `AGENTS.md` files state no rule of their own. RHINO: 51 budgeted files, 13 mapped directories, 511 links. HIPPO: 53 budgeted files, 8 mapped directories, 359 links. No findings in either. |
| **AC-03** Workflows populated and executable | MET | MET | Both `workflows/` levels carry worktree-to-pull-request, harness-contract change, harness-parity verification, Gherkin-implementation review, red-green-refactor, rules propagation, rules grooming, rules quality gate, and a release cut naming that repository's real commands — `cargo xtask dist`/`cargo xtask checksums` for RHINO, `scripts/build-release.sh` for HIPPO. Every command named in HIPPO's tree resolves; `./hippo` appears only as the thing this repository is the exception to. |
| **AC-04** Worktrees live in the repository and change no result | MET | **NOT MET, consciously** | RHINO tracks `worktrees/.gitkeep` with `/worktrees/*` ignored, and every gate reports its pre-worktree baseline. HIPPO's worktrees stay *outside* the checkout: `go build` walks up out of a worktree, takes the outermost `.git` **directory**, and runs `git status` in the bare repository, where it is fatal. No ignore rule reaches a reader outside the tree it governs. Recorded as an Adoption Matrix Deviation with the shimmed-`git` evidence rather than worked around. |
| **AC-05** One merge-blocking gate, a superset of the hooks | MET | MET | RHINO run 34234034045; HIPPO run 34249416169 refused a non-conventional subject, an unformatted file and a broken link, with `Gate results: failure failure failure failure success success`. Skip refusal proved in isolation for both — HIPPO run 34250431194: `success success success success success success skipped` → refused. Every check from each retired `ci.yml` runs inside the new gate; `loaded-host.yml` stays nightly and never blocked a merge. **One caveat:** HIPPO's `Test` job failed at its formatting step before reaching the deliberately failing unit test, so the RED proved four failing jobs and three distinct reasons; the unit adapter's refusal is evidenced locally instead. |
| **AC-06** Main refuses everybody | MET | MET | Rulesets `22550173` and `22562053`, both `bypass_actors: []`, `current_user_can_bypass: "never"`, requiring the observed name `Quality gate`. Both direct owner pushes refused by the server, naming both the pull-request rule and the required check. Both repositories then merged real pull requests through the ruleset. |
| **AC-07** Three harnesses, no Nx, no MCP server | MET | MET | Both report `checked 3 harnesses, no findings`. RHINO `canon 3 harnesses, 7 skills, 2 agents`; HIPPO `canon 3 harnesses, 3 skills, 1 agents`. No `required-mcp`, no per-harness capability vector, no `.mcp.json` in either. `Nx` appears in HIPPO's tree only as a prohibition. Six probes confirmed the contract refuses a granted-too-much adapter, a dropped capability, a nested `AGENTS.md`, and a vendor settings field — and correctly stays silent on an empty field and an absent key. |
| **AC-08** The workflow is exercised before it is required | MET | MET | Every change landed through a pull request from `worktree/repo-rules-adoption`: RHINO #1–#6, HIPPO #5 and #8–#11. Branch and worktree removal is the final cleanup item. **Partial on one clause:** the branch name is identical in all three repositories, but the worktree *path* is not — `worktrees/repo-rules-adoption` in beaver-nest and RHINO, `hippo-worktrees/repo-rules-adoption` beside HIPPO, for the AC-04 reason. The directory name is the same everywhere. |
| **AC-09** Nothing already there is weakened | MET | MET | Coverage floors unchanged: RHINO ≥99% validator-module with its two declared exclusions, HIPPO 99.17% against a 99% floor. Exit-code contracts `0`/`1`/`2` and `73`/`75`/`78` restated at full force. Release immutability and checksum rules restated. Exemption boundaries tightened rather than relaxed — no unit exemption in either, and every E2E exemption names a concrete boundary and reason. The one dropped assertion, HIPPO's `Validate pushed commits`, was replaced in the same commit by a stricter one over the gate's whole trigger set. **The budget rule held under pressure:** `README.md` exceeded 1600 counted words and was resolved by removing restated rules and a duplicated entry-point list, never by raising the number. |

Two criteria carry a qualification rather than a clean pass, and both are stated above rather than rounded up: AC-04 is deliberately unmet for HIPPO, and AC-05's HIPPO RED proved one fewer distinct reason than planned.

**Reconciliation found unfinished work, which is the only reason to do it separately from delivery.** RHINO's phases finished before HIPPO's, and by the time HIPPO's `README.md` was updated with the integration path the same task for RHINO had been carried past for two phases with its checkbox still unticked. Nothing else surfaced it: the gate was clean, both repositories reconciled three harnesses, and the criterion table was being filled in with real evidence for everything around it. The table was what caught it — writing "MET" beside AC-03 and AC-08 forced a read of the delivery items those labels point at, and one of them was open. It was reopened as a task and executed rather than absorbed into a criterion that was true of the other repository. A reconciliation pass that only confirms what you already believe has not been run.


## Adoption Matrix Deviations

_Any document whose verdict changes during execution is recorded here with the evidence that changed it. The matrix in [the governance restructure design](tech-docs/01-governance-restructure.md) is a decision made from reading; execution is where it meets two real trees._

**2026-09-08 — RHINO: three documents authored beyond the matrix.** The matrix allocated 38 inherited documents plus two authored workflows. Executing the inventory pass found three rules from RHINO's `AGENTS.md` with no destination among them, and a rule with no destination stops the phase by design:

| Authored | Carries | Why no inherited document fits |
| --- | --- | --- |
| `conventions/working-tree.md` | `R25` — build output, coverage, and `local-tmp/` stay ignored | The sibling has no equivalent, and the worktree containment finding from phase 1 needed a home where the next person adding a tree-walking tool would find it. |
| `development/public-contract.md` | `R05`, `R06`, `R07` — exit codes, `version --json`, no rename without a major version | The sibling ships no released artifact and has no consumer pinning it, so it has no document about a contract that must not move. |
| `development/code-clarity.md` | `R19`, `R20` — phase separation, comment discipline | The sibling states both inline in `AGENTS.md` and nowhere else, so there was nothing to adopt. |

RHINO therefore receives 41 documents plus six READMEs — 49 files, of which 43 state rules. The matrix's verdicts on the 54 source documents are unchanged; this is addition, not revision.

**2026-09-08 — RHINO: the Claude skill adapter path diverges from the sibling.** The matrix assumed the sibling's `.claude/commands/{name}.md` wrapper. Current vendor documentation puts Claude Code's native skill surface at `.claude/skills/{name}/SKILL.md`, and Codex and OpenCode both read `.agents/skills/` natively. RHINO declares one skill adapter, on Claude, at the current path. Recorded rather than silently adopted, because it is the drift policy working as designed: the sibling's choice was right when it was made.

**2026-09-08 — HIPPO: worktrees stay outside the repository, and RHINO's containment does not transfer.** The matrix treated worktree containment as one decision applying to both repositories. It is a decision about a language toolchain. Cargo does not walk up out of a worktree looking for a version-control root; `go build` does, takes the outermost `.git` directory, and ignores the `.git` file a worktree actually has. In HIPPO's bare-repository layout that is a hard build failure; in an ordinary clone it is a binary stamped with the other checkout's revision. RHINO keeps `worktrees/` inside with ignore rules and a scan exclusion. HIPPO keeps its worktrees in `hippo-worktrees/` beside the checkout — the arrangement phase 6 had set out to retire — and states the reason where the next person would otherwise undo it. Acceptance criterion AC-04 is met for RHINO and consciously not met for HIPPO.
