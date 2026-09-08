# Delivery

Work happens in two external checkouts: `wahidyankf/rhino` and `wahidyankf/hippo`. Commit and push authorization does not cross a repository boundary — each repository requires its own under the [commit-authorization convention](../../../repo-governance/conventions/commit-authorization.md), and neither is granted by this plan. Shell invocations follow the shared RTK instruction.

Every change to either repository is authored in `worktrees/repo-rules-adoption/` on branch `worktree/repo-rules-adoption` and merged through a pull request, including changes made before that repository's ruleset exists.

RHINO completes phases 1–5 before HIPPO reaches phase 10, because RHINO validates itself from a source build and is the only place a schema refusal can be diagnosed without a release. HIPPO phases 6–9 may overlap RHINO's work; nothing in them depends on a RHINO answer.

## Delivery Boundaries and Work Location

Recorded at execution start, because this plan predates the [pull-request boundaries convention](../../../repo-governance/conventions/pull-request-boundaries.md).

**Work location.** One worktree per repository, provisioned once and reused for every delivery unit that repository produces: `worktrees/repo-rules-adoption/` on branch `worktree/repo-rules-adoption`, in beaver-nest, RHINO and HIPPO alike. A second `git worktree add` for this plan in any of the three is a defect. Units land serially — land one, sync that worktree from `origin/main`, branch the next in the same directory.

**Boundaries.** Phase 0 produces nothing reviewable and is never a boundary. Phase 3 and phase 8 change repository settings through the API, not the tree, so they produce no pull request either. Every other phase ends at one:

| Unit | Repository  | Phase    | Increment                                                      | Why it stands alone                                                                                      |
| ---- | ----------- | -------- | -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| 1    | beaver-nest | —        | This plan                                                      | A complete planning record. Green alone, and `main` stays releasable because no product code moves.      |
| 2    | RHINO       | 1        | Worktree tree and every scanner exclusion                      | A worktree can exist without changing a gate result. Nothing later is required for that to be true.      |
| 3    | RHINO       | 2        | The gate, and the deletion of `ci.yml`                         | They must land together: deleting the old workflow before the new one exists would leave `main` ungated. |
| 4    | RHINO       | 4        | The governance hierarchy and its configuration                 | A complete unit of meaning. Its budgets and mapped trees must land with the documents they govern.       |
| 5    | RHINO       | 5        | The canonical roster, three adapter sets, and the parity block | Canonical content and the configuration that reconciles it cannot land apart without a failing gate.     |
| 6    | RHINO       | 5        | Specification assessment and documentation reconciliation      | Depends on every prior unit; independently useful and independently reviewable.                          |
| 7–11 | HIPPO       | 6,7,9,10 | The same five increments                                       | Same reasoning, one repository later.                                                                    |
| 12   | beaver-nest | 11       | Reconciled delivery records and the archival move              | The last change-producing unit, so it is necessarily a boundary.                                         |

**Deployable state.** Neither CLI is a live service, so the rule reads as releasable state: every merge must leave `main` a commit a release could be cut from. No unit leaves a half-built binary, a broken gate, or a specification contradicting the tree. No feature flag is needed, because no unit ships incomplete user-reachable behaviour.

## File Impact

Paths are relative to each repository's root.

**RHINO** — `[N]` `worktrees/.gitkeep`, `.github/workflows/pr-quality-gate.yml`, `repo-governance/**` (the adopted tree, exact file list produced by phase 4), `.agents/skills/{worktree-to-pr,spec-impact-assessment,release-cut}/SKILL.md`, `.agents/agents/gherkin-implementation-reviewer.md`, `.claude/agents/gherkin-implementation-reviewer.md`, `.codex/agents/gherkin-implementation-reviewer.toml`, `.opencode/agents/gherkin-implementation-reviewer.md`, plus the skill adapters settled in phase 5. `[E]` `.gitignore`, `repo-config.yml`, `AGENTS.md`, `README.md`, `CLAUDE.md` (verify it remains only the import). `[D]` `.github/workflows/ci.yml`.

**HIPPO** — `[N]` `worktrees/.gitkeep`, `.github/workflows/pr-quality-gate.yml`, `CLAUDE.md`, `repo-governance/**`, the same `.agents/`, `.claude/`, `.codex/`, `.opencode/` set. `[E]` `.gitignore`, `repo-config.yml`, `AGENTS.md`, `README.md`. `[D]` `.github/workflows/ci.yml`.

**This repository** — `[E]` this plan's documents and `plans/in-progress/README.md`; `[M]` the plan folder at archival.

Unknowns to discover during execution: the exact file list of each adopted tree (phase 4), the native skill surface of Codex and OpenCode (phase 5), and whether `scripts/test.sh` or `scripts/format-check.sh` in HIPPO glob into `worktrees/` (phase 6).

## Phase 0 — Baseline and Inventory

- [x] `[AI] [AC-01]` Input: both checkouts on clean `main`. Action: record each repository's head commit, working-tree state, and the full result of every gate it runs today — quick, full, formatting, and the pinned documentation gate where one exists. Outcome: the comparison baseline every later "identical result" claim is measured against. Proof: recorded commands and outputs in `learnings.md`. _Done 2026-09-08._
- [x] `[AI] [AC-01]` Input: each repository's current `AGENTS.md`. Action: enumerate every rule it states as a numbered inventory, one line per rule, without interpreting or merging any of them. Outcome: the checklist phase 4 must fully consume. Proof: both numbered inventories recorded in `learnings.md`. _Done 2026-09-08._
- [x] `[AI] [AC-05]` Input: each repository's `.github/workflows/ci.yml`. Action: enumerate every check it performs as a numbered inventory. Outcome: the superset the new gate must contain before `ci.yml` may be deleted. Proof: both inventories recorded in `learnings.md`. _Done 2026-09-08._
- [x] `[AI] [AC-06]` Input: `wahidyankf/rhino` and `wahidyankf/hippo`. Action: record that no ruleset and no branch protection exists on either `main`, and confirm both are public. Outcome: the before-state the ruleset evidence is contrasted with. Proof: recorded API responses in `learnings.md`. _Done 2026-09-08._

**Checkpoint 0 (blocking).** Both rule inventories, both check inventories, and both gate baselines exist and are recorded. No repository file has changed. _Passed 2026-09-08: 17 HIPPO rules and 26 RHINO rules inventoried, both check inventories recorded, both gate baselines green, neither `main` protected._

## Phase 1 — RHINO: Worktree Tree and Containment

- [ ] `[AI] [AC-04]` Input: the RHINO checkout. Action: create `worktrees/repo-rules-adoption/` as a Git worktree on branch `worktree/repo-rules-adoption` and install dependencies inside it to activate its hooks. Outcome: the authoring location for every later RHINO change. Proof: `git worktree list` and evidence that a hook fires in that worktree.
- [ ] `[AI] [AC-04]` **RED.** Input: the worktree created above. Action: from the primary checkout run `cargo xtask self-validate` and the repository status. Expected failure: the validator reads Markdown inside `worktrees/`, and/or status reports the worktree as untracked. Outcome: proof that containment is required rather than assumed. Proof: recorded output showing duplicate or untracked paths.
- [ ] `[AI] [AC-04]` **GREEN.** Input: the RED evidence. Action: add `/worktrees/*` with a `!/worktrees/.gitkeep` re-inclusion to `.gitignore`, add `worktrees` and `local-tmp` to `scan.exclude-directories` in `repo-config.yml`, and commit `worktrees/.gitkeep`. Expected pass: the same commands now report exactly the phase-0 baseline. Proof: recorded output identical to the baseline.
- [ ] `[AI] [AC-04]` **REFACTOR.** Input: the passing state. Action: verify the remaining consumers against a populated worktree — `cargo fmt --all --check`, `cargo clippy --all-targets`, Prettier via `.prettierignore`, and ShellCheck's target list. Outcome: no consumer reads the worktree. Proof: each command's output recorded against the baseline.
- [ ] `[AI] [AC-08]` Input: the committed changes. Action: push the branch, open a pull request against `main`, merge after the existing `ci.yml` reports success, then delete the branch and remove the worktree. Outcome: the integration path exercised before it is required. Proof: pull-request URL and the post-merge branch and worktree listings.

**Checkpoint 1 (blocking).** A RHINO worktree can exist without changing any gate result, and the change reached `main` through a pull request.

## Phase 2 — RHINO: Pull-Request Quality Gate

- [ ] `[AI] [AC-05]` Input: the phase-0 check inventory and the hook contracts. Action: author `.github/workflows/pr-quality-gate.yml` with the jobs in [the gate design](tech-docs/04-pr-gate-and-ruleset.md), using the merge base for the commit range, the real head for commitlint, no HIPPO wrapper, and an aggregate job that treats skipped and cancelled as failure. Outcome: one workflow that is a superset of both the hooks and `ci.yml`. Proof: a line-by-line mapping from the phase-0 inventory to a job, recorded in `learnings.md`.
- [ ] `[AI] [AC-05]` **RED.** Input: a scratch branch. Action: push a commit with a non-conventional message, an unformatted file, and a failing quick check, and open a pull request. Expected failure: the aggregate check fails, and each responsible job fails for its own reason. Proof: the failing run with per-job reasons.
- [ ] `[AI] [AC-05]` **GREEN.** Input: the same pull request. Action: correct all three violations. Expected pass: every job succeeds and the aggregate reports success. Proof: the passing run.
- [ ] `[AI] [AC-05]` **REFACTOR.** Input: the passing gate. Action: force a conditional job to skip and confirm the aggregate still refuses; then delete `.github/workflows/ci.yml` in the same pull request that lands the gate. Outcome: one contract in one file. Proof: the skip-refusal run, and the merged diff showing the deletion.
- [ ] `[AI] [AC-06]` Input: the merged, green gate. Action: read back the exact status-check name the server observed. Outcome: the string phase 3 will require. Proof: the recorded check name.

**Checkpoint 2 (blocking).** Every check from the phase-0 inventory runs inside the new gate, the gate refuses each hook violation and refuses a skipped dependency, `ci.yml` is gone, and the observed check name is recorded.

## Phase 3 — RHINO: Default-Branch Ruleset

- [ ] `[AI] [AC-06]` Input: the observed check name. Action: create a `main` ruleset refusing direct push, force push and deletion for every actor, requiring linear history, requiring a pull request with zero approvals, requiring that check, and listing no bypass actors. Outcome: integration is enforced by the server. Proof: the created ruleset read back, showing an empty bypass list.
- [ ] `[AI] [AC-06]` Input: the active ruleset. Action: attempt a direct push of a trivial commit to `main` as the owner. Expected outcome: refusal. Proof: the recorded refusal message. Reset the local branch afterwards.
- [ ] `[AI] [AC-06]` Input: the active ruleset. Action: open a trivial pull request and confirm it becomes mergeable once the gate passes. Outcome: proof the required name is the one the gate emits, not a name that never reports. Proof: the mergeable state and the merge.

**Checkpoint 3 (blocking).** RHINO's `main` refuses the owner, and a pull request can still merge.

## Phase 4 — RHINO: Governance Hierarchy

- [ ] `[AI] [AC-01]` Input: the adoption matrix and RHINO's rule inventory. Action: create `repo-governance/` with `vision/`, `principles/`, `conventions/`, `development/`, and `workflows/`, authoring each adopted document adapted to RHINO and merging the inventory items that belong to it. Author `vision/README.md` from RHINO's own generic-tool rule. Outcome: the hierarchy. Proof: the file list, and the inventory annotated with one destination per item.
- [ ] `[AI] [AC-03]` Input: RHINO's own procedures. Action: author `workflows/worktree-to-pull-request.md` and `workflows/release-cut.md` with the real commands — `cargo xtask dist`, then `cargo xtask checksums` — and adopt the six inherited workflows. Outcome: a populated workflow level. Proof: each named command executed or shown to resolve.
- [ ] `[AI] [AC-02]` Input: the hierarchy. Action: reduce `AGENTS.md` to a link index and record the drift policy in `repo-governance/README.md`. Outcome: one home per rule. Proof: the diff, and a check that no rule is stated only in `AGENTS.md`.
- [ ] `[AI] [AC-02]` **RED.** Input: the new tree with `repo-config.yml` unchanged. Action: run `cargo xtask self-validate`. Expected failure: `repo-governance` is not a mapped tree and its documents carry no budget, so missing maps and oversized documents go unreported — demonstrated by pointing the mapped-tree list at it and observing the findings appear. Proof: recorded findings.
- [ ] `[AI] [AC-02] [AC-09]` **GREEN.** Input: the RED findings. Action: add `repo-governance` to `governance-directory-map.trees`, declare the `AGENTS.md` and `repo-governance/**/*.md` budgets, then fix every finding by adding maps and by **splitting** any oversized document. Expected pass: a clean self-validation. Proof: the clean run and the recorded budget values with their reasons.
- [ ] `[AI] [AC-01]` **REFACTOR.** Input: the annotated inventory. Action: confirm every numbered rule has exactly one destination and no rule was silently dropped or weakened. Outcome: the restructure is proved by mapping, not by reading. Proof: the completed mapping in `learnings.md`.
- [ ] `[AI] [AC-08]` Input: the completed tree. Action: land it through the worktree branch and a pull request under the now-active ruleset. Proof: pull-request URL and merge.

**Checkpoint 4 (blocking).** RHINO's hierarchy is complete, self-validation is clean, every inventoried rule has a home, and nothing was weakened to fit a budget.

## Phase 5 — RHINO: Harness Contract

- [ ] `[AI] [AC-07]` Input: the open questions in [the harness contract](tech-docs/02-harness-contract.md). Action: settle each against the binary with `rhino repo-config validate` — the skill-adapter-without-agent-adapter question, the canonical instruction versus its own prohibition glob, and whether `capabilities` is declarable without `required-mcp`. Outcome: the shapes the schema actually accepts. Proof: each accepted or refused configuration with its exact message.
- [ ] `[AI] [AC-07]` Input: vendor documentation for Codex and OpenCode. Action: establish each harness's native skill surface by inspection. Outcome: the skill-adapter contracts, or a recorded decision that a harness expresses agents but not skills. Proof: the recorded finding and its source.
- [ ] `[AI] [AC-07]` Input: the settled shapes. Action: author the three canonical skills and the canonical `gherkin-implementation-reviewer` agent, then every adapter for all three harnesses. Outcome: a non-empty canonical roster. Proof: the file list.
- [ ] `[AI] [AC-07]` **RED.** Input: the canonical roster with `repo-config.yml` still declaring an empty harness list. Action: run the parity check. Expected failure: canonical content exists that nothing reconciles — and, after the roster is declared, a deliberately weakened adapter granting shell to the read-only agent is reported. Proof: both recorded failures.
- [ ] `[AI] [AC-07]` **GREEN.** Input: the RED evidence. Action: declare the full `harness-parity` block — three harnesses, canonical roots and routes, the `declaration` field names, the capability vocabulary, `prohibited-instruction-sources`, and `prohibited-instruction-fields` for the vendor settings keys — with no `required-mcp` and no per-harness `capability` block. Revert the weakened adapter. Expected pass: parity reconciles clean. Proof: the clean run.
- [ ] `[AI] [AC-07]` **REFACTOR.** Input: the passing contract. Action: add a second competing instruction source as a file and again as a vendor settings field, confirm both are reported, and confirm an absent or empty field is not. Outcome: the prohibition is proved in both forms. Proof: the three recorded results.
- [ ] `[AI] [AC-08]` Input: the completed contract. Action: land it through the worktree branch and a pull request. Proof: pull-request URL and merge.

- [ ] `[AI] [AC-09]` Input: RHINO's `specs/behaviours/` and `specs/architecture.md`. Action: assess whether this repository's own changes — governance tree, gate, ruleset, worktrees, harness roster — alter any documented behaviour or C4 element, and update every affected specification in the same change. A verified no-op is a valid outcome and is recorded as one; RHINO's own rules require the assessment before every repository change, so it cannot be skipped. Proof: the recorded assessment and either the specification diff or the evidenced no-op.
- [ ] `[AI] [AC-03] [AC-08]` Input: RHINO's `README.md` and `docs/`. Action: update every page that describes contributor rules, hooks, the integration path, or CI so it matches the new hierarchy, the new gate, and the ruleset. `docs/` may not contradict `specs/` and must stay true to the built binary. Land through a pull request. Proof: the diff and a clean gate.

**Checkpoint 5 (blocking).** RHINO reconciles a non-empty roster against three harnesses with no capability server, refuses a weakened adapter, and refuses a competing instruction source in both file and field form. Any schema limitation found is recorded with its consequence for HIPPO.

## Phase 6 — HIPPO: Worktree Tree and Containment

- [ ] `[AI] [AC-04]` Input: the HIPPO checkout. Action: create `worktrees/repo-rules-adoption/` on branch `worktree/repo-rules-adoption` and install dependencies inside it. Proof: `git worktree list` and hook evidence.
- [ ] `[AI] [AC-04]` **RED.** Input: the populated worktree. Action: run `npm run test:quick`, `scripts/test.sh`, `scripts/format-check.sh`, and the pinned `./rhino` gate from the primary checkout. Expected failure: at least one consumer reads the worktree — the shell scripts' own globs are the specific risk, since Go's own module rules already exclude a nested module. Proof: recorded output naming the reading consumer, or a recorded finding that none does.
- [ ] `[AI] [AC-04]` **GREEN.** Input: the RED evidence. Action: add the ignore rules, add `worktrees` to `scan.exclude-directories`, and correct any script glob that descends into it. Expected pass: every command reports the phase-0 baseline. Proof: outputs matched against the baseline.
- [ ] `[AI] [AC-04]` **REFACTOR.** Input: the passing state. Action: remove the external the external `hippo-worktrees/` directory beside the checkout directory and confirm nothing references it. Outcome: one worktree location. Proof: the removal and a search for remaining references.
- [ ] `[AI] [AC-08]` Input: the committed changes. Action: land through a pull request, then reset the local branch onto `main`. The worktree is retained for phases 7–10 and removed in phase 11. Proof: pull-request URL.

**Checkpoint 6 (blocking).** A HIPPO worktree changes no gate result and the external directory is retired.

## Phase 7 — HIPPO: Pull-Request Quality Gate

- [ ] `[AI] [AC-05]` Input: the phase-0 check inventory and the hook contracts. Action: author `.github/workflows/pr-quality-gate.yml` with the jobs in [the gate design](tech-docs/04-pr-gate-and-ruleset.md), fixing the commit range to use the merge base rather than the base tip, adding the `repository-contract` job that runs the pinned `./rhino` gate for the first time in CI, and adding the `consumer-bootstrap` job. Outcome: a superset gate. Proof: the inventory-to-job mapping.
- [ ] `[AI] [AC-05]` **RED.** Input: a scratch branch. Action: push a non-conventional message, an unformatted file, a failing quick check, and a governance document that breaks a link, then open a pull request. Expected failure: the aggregate fails and each job fails for its own reason. Proof: the failing run.
- [ ] `[AI] [AC-05]` **GREEN.** Input: the same pull request. Action: correct every violation. Expected pass: all jobs and the aggregate succeed. Proof: the passing run.
- [ ] `[AI] [AC-05]` **REFACTOR.** Input: the passing gate. Action: confirm a skipped conditional job still refuses the aggregate, and delete `.github/workflows/ci.yml` in the same pull request. Proof: the skip-refusal run and the merged diff.
- [ ] `[AI] [AC-06]` Input: the merged gate. Action: read back the observed status-check name. Proof: the recorded name.

**Checkpoint 7 (blocking).** HIPPO's gate is a superset of its old CI and its hooks, the documentation gate now runs in CI, `ci.yml` is gone, and the check name is recorded.

## Phase 8 — HIPPO: Default-Branch Ruleset

- [ ] `[AI] [AC-06]` Input: the observed check name. Action: create the same ruleset as phase 3, with no bypass actors. Proof: the ruleset read back with an empty bypass list.
- [ ] `[AI] [AC-06]` Input: the active ruleset. Action: attempt a direct owner push to `main` and record the refusal; reset afterwards. Proof: the refusal message.
- [ ] `[AI] [AC-06]` Input: the active ruleset. Action: confirm a trivial pull request reaches a mergeable state and merges. Proof: the merge.

**Checkpoint 8 (blocking).** HIPPO's `main` refuses the owner, and a pull request can still merge.

## Phase 9 — HIPPO: Governance Hierarchy

- [ ] `[AI] [AC-01] [AC-03]` Input: the adoption matrix and HIPPO's rule inventory. Action: author the hierarchy adapted to HIPPO, including `vision/README.md`, the two new workflows with `scripts/build-release.sh` as the real release command, and `development/resource-aware-development.md` stating the governed exception that HIPPO cannot run under its own guard. Outcome: the hierarchy. Proof: the file list and the annotated inventory.
- [ ] `[AI] [AC-02]` Input: the hierarchy. Action: reduce `AGENTS.md` to a link index, add `CLAUDE.md` containing only the import, and record the drift policy. Proof: the diffs.
- [ ] `[AI] [AC-02]` **RED.** Input: the new tree with `repo-config.yml` unchanged. Action: run the pinned `./rhino` gate. Expected failure: `repo-governance` is unmapped, no surface carries a budget, and the first `classDef` in an adopted diagram is refused against the empty colour lists. Proof: recorded findings.
- [ ] `[AI] [AC-02] [AC-09]` **GREEN.** Input: the RED findings. Action: add `repo-governance` to the mapped trees — and **not** `docs`, preserving HIPPO's stated reason for excluding it — declare the word-budget surfaces and the counting rule as a recorded decision, declare the Okabe-Ito palette, then fix every finding by adding maps and splitting oversized documents. Expected pass: a clean gate. Proof: the clean run and the recorded decisions.
- [ ] `[AI] [AC-01]` **REFACTOR.** Input: the annotated inventory. Action: confirm one destination per numbered rule and no weakening. Proof: the completed mapping.
- [ ] `[AI] [AC-08]` Input: the completed tree. Action: land through a pull request. Proof: pull-request URL.

**Checkpoint 9 (blocking).** HIPPO's hierarchy is complete and clean, `docs` was deliberately not added to the mapped trees, and every inventoried rule has a home.

## Phase 10 — HIPPO: Harness Contract

- [ ] `[AI] [AC-07]` Input: phase 5's settled shapes and any recorded schema limitation. Action: author HIPPO's three canonical skills, its canonical agent, and every adapter, with `scripts/build-release.sh` in its `release-cut` bundle. Proof: the file list.
- [ ] `[AI] [AC-07]` **RED.** Input: the canonical roster with the current empty roster and the current `**/CLAUDE.md` prohibition still in place. Action: run the pinned gate. Expected failure: the new `CLAUDE.md` is reported as a prohibited instruction source, and canonical content exists that nothing reconciles. Proof: both findings.
- [ ] `[AI] [AC-07]` **GREEN.** Input: the RED findings. Action: move `**/CLAUDE.md` from the prohibition list to `canonical.instruction-adapter`, add nested `**/AGENTS.md` and `.claude/rules/**/*.md` to the prohibitions in its place, and declare the full three-harness block with no `required-mcp`. Expected pass: a clean gate. Proof: the clean run, and a note that the prohibition set tightened overall.
- [ ] `[AI] [AC-07]` **REFACTOR.** Input: the passing contract. Action: confirm a weakened adapter and a competing instruction source in both file and field form are refused. Proof: the recorded results.
- [ ] `[AI] [AC-08]` Input: the completed contract. Action: land through a pull request. Proof: pull-request URL.

- [ ] `[AI] [AC-09]` Input: HIPPO's `specs/behaviours/` and `specs/architecture.md`. Action: assess this repository's own changes for behaviour and C4 impact and update every affected specification in the same change; record a verified no-op if there is none. HIPPO's own rules require this assessment before every repository change. Proof: the recorded assessment and either the diff or the evidenced no-op.
- [ ] `[AI] [AC-03] [AC-08]` Input: HIPPO's `README.md` and `docs/`. Action: update every page describing contributor rules, hooks, the integration path, or CI to match the new hierarchy, gate and ruleset. Land through a pull request. Proof: the diff and a clean gate.

**Checkpoint 10 (blocking).** Both repositories reconcile three harnesses against a non-empty canonical roster with no capability server and no Nx anywhere.

## Phase 11 — Reconciliation and Archive

- [ ] `[AI] [AC-01] [AC-09]` Input: both annotated inventories and both check inventories. Action: reconcile every acceptance criterion against recorded evidence, and confirm no coverage floor, exit-code contract, exemption boundary, or release rule was relaxed. Outcome: the completion claim is evidenced. Proof: a criterion-by-criterion table in `learnings.md`.
- [ ] `[AI] [AC-01] [AC-09]` Input: the rule changes this plan made in two external repositories. Action: apply the [rules-propagation workflow](../../../repo-governance/workflows/rules-propagation.md) to the changes made **in this repository** and record its terminal result, which may be `PASS_NO_CHANGE`. Note explicitly that propagation stops at this repository's boundary: the adopted trees are governed by their own repositories under the accepted-drift policy. Proof: the recorded terminal result.
- [ ] `[AI]` Input: this workstation. Action: confirm no unneeded non-production server, watcher, candidate, or temporary proxy was started by this plan and left running; neither repository is an active service, so the expected result is that none exists. Proof: the recorded check.
- [ ] `[AI] [AC-08]` Input: both repositories. Action: confirm no `worktrees/repo-rules-adoption` branch or worktree remains anywhere, and that `main` is the only branch in each. Proof: branch and worktree listings from all three repositories.
- [ ] `[AI] [AC-08]` Input: this plan and `plans/in-progress/README.md`. Action: set status Done with the final-checkpoint local date, then move the folder to `plans/done/YYYY-MM-DD__hippo-rhino-governance-adoption/` together with the stage-index and directory-map updates, refusing an existing destination. Proof: one destination, no source, and a clean repository gate here. This completes the archival item.

**Checkpoint 11 (blocking).** Every criterion is reconciled against evidence, propagation has a terminal result, no task branch or worktree survives, and the plan is archived.

## Recovery

Each item stays dormant until its trigger fires, and records a dated, evidenced `Not triggered` disposition at reconciliation otherwise.

- [ ] `[AI] [AC-07]` **Trigger: RHINO refuses a configuration shape this plan requires.** Action: diagnose whether it is a defect or a deliberate limit. If a defect, fix it in RHINO, cut a release, and move HIPPO's `rhino.lock` pin — both routine procedures. If a limit, record it and reduce the roster to the shape the schema accepts, restating the parity claim accordingly. Proof: the release and pin, or the recorded limit and the reduced claim.
- [ ] `[AI] [AC-06]` **Trigger: a ruleset is created and no pull request can merge.** Action: read the actual reported check names, correct the required name, and confirm a pull request becomes mergeable. Do not add a bypass actor; the ruleset's value is that it has none. Proof: the corrected ruleset and a merged pull request.
- [ ] `[AI] [AC-05] [AC-06]` **Trigger: a gate becomes unable to pass on `main`, making the branch unwritable.** Action: repair the gate on a branch and merge it through the gate itself. If the gate cannot pass at all, report the blocker with evidence and stop; deleting the ruleset is not an authorized recovery path under this plan. Proof: the merged repair, or the reported blocker.
- [ ] `[AI] [AC-02] [AC-09]` **Trigger: an adopted document cannot meet the declared word budget without losing substance.** Action: split it into coherent documents, each with its own reader task and directory-map entry. Never raise the budget and never trim substance. Proof: the split documents and a clean gate.
- [ ] `[AI] [AC-01]` **Trigger: a numbered rule from a phase-0 inventory has no destination.** Action: stop the phase, decide its destination explicitly, and record the decision — including a decision to drop it, which requires its own stated reason. Proof: the recorded decision.
