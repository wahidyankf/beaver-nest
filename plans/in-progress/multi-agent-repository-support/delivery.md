# Delivery

Implementation is not authorized by the plan-creation request. Only Phase 0 is complete.

## Phase 0 — Plan Readiness

- [x] `[AI] [AC-01–AC-07]` Input: current repository instructions, `.agents/skills/`, Codex adapters, Badakmini architecture/corpus, local CLI availability, and official harness documentation. Action: inventory the current contract, choose canonical sources and minimal adapters, write all formal plan documents, and run the plan quality gate. Outcome: one junior-executable in-progress plan exists without implementation. Proof: 2026-08-28 recursive plan review, technical line-count check, repository validation, and diff review recorded in `learnings.md`.

### Phase 0 Checkpoint

- [x] `[AI] [AC-01–AC-07]` Block later work until the plan has one technical shape, aligned BRD/PRD/technical decisions, exact specification changes, exact File Impact, complete maps/links, and no implementation edits. Proof: 2026-08-28 gate result in `learnings.md`.

## Phase 1 — Canonical Rules and Portable Workflows

- [ ] `[AI] [AC-01, AC-07]` Input: `AGENTS.md`, `RTK.md`, the new harness convention, and official discovery rules. Action: add the concise point-of-use rule, create the exact Claude import adapter, neutralize RTK wording, ignore only `CLAUDE.local.md`, and keep vendor/local exclusions explicit. Outcome: all three harnesses route to one repository instruction source. Proof: focused Badakmini fixtures and manual file inspection.
- [ ] `[AI] [AC-02]` Input: every `.agents/skills/<name>/SKILL.md` and its resources. Action: validate the common skill subset and add one thin `.claude/commands/<name>.md` route per canonical skill without copying workflow bodies. Outcome: Codex/OpenCode use canonical skills natively and Claude exposes equivalent commands. Proof: one-to-one name/description/path reconciliation with missing, stale, extra, and malformed red cases.
- [ ] `[AI] [AC-03]` Input: the current Codex CI-monitor subagent, the three OSE Public web-researcher adapters, and current official custom-agent formats. Action: move CI-monitor intent to `.agents/agents/ci-monitor-subagent.md`; author a Beaver Nest `web-researcher` canonical prompt with the repository-first/source-grounded/read-only quality contract; and create thin Codex, Claude, and OpenCode adapters for both agents. Outcome: exactly two canonical custom-agent workflows are reachable by all harnesses without copied prompt bodies or OSE-only dependencies. Proof: one-to-one adapter fixtures, exact semantic capability mappings, web-research permission assertions, and no duplicate canonical prompt body.

### Phase 1 Checkpoint

- [ ] `[AI] [AC-01–AC-03, AC-07]` Run after rules, skills, and agent adapters exist. Confirm one canonical body per concern, no extra always-on rule source, no secret or machine path, and complete harness routes. Outcome: content topology is ready for deterministic enforcement. Proof: reviewed tree and focused red fixtures; block Phase 2 on drift.

## Phase 2 — Required Capabilities

- [ ] `[AI] [AC-04]` Input: the current Codex `nx-mcp` declaration and official Claude/OpenCode project formats. Action: add credential-free `.mcp.json` and `opencode.json` equivalents, preserve Codex configuration, and keep OpenCode `instructions` absent. Outcome: every harness declares `npx nx mcp` from the workspace. Proof: JSON/JSONC and minimal TOML fixtures for equal, missing, malformed, and divergent commands.
- [ ] `[AI] [AC-04, AC-07]` Input: official RTK supported-agent setup. Action: document the per-user Codex, Claude, and OpenCode integration commands and fail-closed status checks without committing generated global hooks/plugins. Outcome: each contributor can establish equivalent command filtering while secrets and personal settings remain local. Proof: safe guide review and `rtk init --show` instructions.

### Phase 2 Checkpoint

- [ ] `[AI] [AC-04, AC-07]` Confirm every mandatory capability has exactly one declared equivalent per harness and no optional MCP/plugin was invented. Outcome: capability parity is bounded and credential-free. Proof: config reconciliation and public-data-safety review.

## Phase 3 — Gherkin and Deterministic Badakmini Enforcement

- [ ] `[AI] [AC-05–AC-06]` Input: the Specification Changes section and existing Badakmini corpus. Action: add `harness-contract.feature`, update `cli-contract.feature`, bind every new step in the shared contract/support, implement all unit/integration/E2E driver members, and run behavior coverage. Outcome: the complete changed corpus is bound before production code. Proof: `test:coverage:behaviour` passes while runtime scenarios are red for missing implementation.
- [ ] `[AI] [AC-05]` Input: failing unit and integration scenarios. Action: implement repository-contained scanning, normalized adapter comparison, skill/agent reconciliation, JSON/JSONC parsing, minimal Codex TOML inspection, stable findings, and no-write behavior in `Governance.fs`. Outcome: deterministic in-process inspection passes without network or processes. Proof: unit and integration targets plus 99% coverage slices.
- [ ] `[AI] [AC-05]` Input: the inspection API and failing CLI scenarios. Action: add `governance harness-contract validate` with text/JSON summaries and established exit codes. Outcome: the public CLI reports parity and drift consistently. Proof: focused unit/integration/E2E scenarios and CLI contract tests.
- [ ] `[AI] [AC-06]` Input: the new command and complete contract path list. Action: add the command to `test:repo`, include all JSON/Markdown/TOML adapter inputs in Nx caching, and extend pre-push selection. Outcome: repository integration cannot skip the validator because of file type or cache selection. Proof: changed-path fixtures or safe hook path inspection plus uncached `test:repo`.
- [ ] `[AI] [AC-05–AC-06]` Input: final production behavior. Action: update Badakmini C4 responsibility, behavior map, and project README. Outcome: as-built specs and project guidance match the implemented validator. Proof: links/maps pass and architecture impact is reconciled.

### Phase 3 Checkpoint

- [ ] `[AI] [AC-05–AC-06]` Run the Badakmini unit, integration, coverage, quick, E2E, focused validator, and repository gates through Nx. Outcome: every layer proves the same corpus and the validator remains read-only/network-free. Proof: recorded target results; block documentation smoke on any failure.

## Phase 4 — Harness Smoke and Documentation

- [ ] `[AI] [AC-01–AC-04, AC-07]` Input: an already-authenticated Codex environment. Action: perform read-only instruction, skill, both-agent, Nx MCP, and web-researcher sandbox discovery without model-generated edits. Outcome: Codex retains the canonical routes and read-only research boundary. Proof: safe pass/fail only in `learnings.md`.
- [ ] `[AI] [AC-01–AC-04, AC-07]` Input: an already-authenticated Claude Code environment with project trust approved. Action: use `/context` and native discovery views to confirm `CLAUDE.md`, skill commands, both agents, Nx MCP, and the web-researcher tool allowlist without edits. Outcome: Claude reaches the canonical contract. Proof: safe pass/fail only; no prompt, output, credential, or path capture.
- [ ] `[AI] [AC-01–AC-04, AC-07]` Input: an already-authenticated OpenCode environment. Action: confirm root rules, canonical skills, both agents, Nx MCP, and web-researcher permission denies through read-only discovery. Outcome: OpenCode reaches the canonical contract. Proof: safe pass/fail only; no session export.
- [ ] `[AI] [AC-07]` Input: verified setup and failure modes. Action: finish the coding-harness how-to, root README route, convention, maps, and rules propagation; document unavailable authentication as a blocker rather than weakening proof. Outcome: a contributor can choose any supported harness with honest guarantees. Proof: reader review and repository gate.

### Phase 4 Checkpoint

- [ ] `[AI] [AC-01–AC-07]` Reconcile deterministic proof with all three safe runtime discovery smokes. Outcome: no claim exceeds observed repository or harness behavior. Proof: dated learnings and no sensitive evidence.

## Final Verification and Archive

- [ ] `[AI] [AC-01–AC-07]` Input: completed phases and clean runtime state. Action: rerun the plan quality gate, all affected Nx gates, uncached `test:repo`, links/maps, public-data-safety inspection, and diff review; stop any temporary process started for smoke tests. Outcome: implementation is complete and no unneeded process or artifact remains. Proof: dated results in `learnings.md`.
- [ ] `[AI] [AC-01–AC-07]` Input: accepted final checkpoint and collision-free local date. Action: set completion metadata, reconcile every conditional/dependency, move this one folder to `plans/done/YYYY-MM-DD__multi-agent-repository-support`, update stage maps, and verify no old-path references. Outcome: exactly one archived plan remains. Proof: source absence, destination presence, valid links/maps, and authorized commit/push if separately approved.
