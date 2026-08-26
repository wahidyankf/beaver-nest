# Delivery Plan

**Status:** Not started

## Executor Legend

- `[AI]` — executable by the repository agent within existing authorization and safety boundaries.
- `[HUMAN]` — requires a product, privacy, infrastructure, or external-state decision from the maintainer.

Keep this checklist synchronized with actual delivery. Record observations in [learnings.md](learnings.md), not in checked task text. A checked item means its stated outcome and verification are complete.

## Phase 0 — Revalidate and Bound the First Slice

- [ ] `[AI]` Re-read the BRD, PRD, technical documentation, current Bnest C4, Gherkin corpus, project READMEs, and resolved Nx targets.
- [ ] `[AI]` Compare the plan against the current implementation and record any stale assumption in its responsible document.
- [ ] `[HUMAN]` Select the initial family identity source and permission boundary.
- [ ] `[HUMAN]` Select the first shared record or document journey and its retention needs.
- [ ] `[AI]` Split this parent plan if the selected slice cannot be delivered and rolled back independently.

### Phase 0 Gate

- [ ] `[HUMAN]` Material product and infrastructure decisions required by the first slice are recorded.
- [ ] `[AI]` The affected specification, application, adapter, storage, and documentation surfaces are identified.
- [ ] `[AI]` No production implementation begins while a material decision remains unresolved.

**Pause safety:** Documentation-only state; no runtime or data migration has started.

## Phase 1 — Identity and Authorization

- [ ] `[AI]` Add proposed identity, role, route, and record-authorization behavior to the canonical Gherkin corpus.
- [ ] `[AI]` Update affected C4 actors, interfaces, trust boundaries, and constraints before implementation.
- [ ] `[AI]` Add failing bindings in every applicable Bnest adapter and capture the Nx red result.
- [ ] `[AI]` Implement the smallest identity and authorization slice that satisfies the selected journey.
- [ ] `[AI]` Run targeted unit, integration, behavior-coverage, and browser checks through Nx.
- [ ] `[AI]` Update affected project READMEs and perform the manual private-route smoke.

### Phase 1 Gate

- [ ] `[AI]` Authorized and unauthorized journeys behave as specified across applicable adapters.
- [ ] `[AI]` The C4 model and Gherkin describe the final identity boundary.
- [ ] `[AI]` Applicable Nx checks and the manual smoke pass.

**Pause safety:** The slice can be disabled or reverted without changing durable family data.

## Phase 2 — Durable Shared Data and Backups

- [ ] `[AI]` Specify ownership, persistence, migration, backup, restore, and restart behavior in C4 and Gherkin.
- [ ] `[AI]` Add failing bindings and capture the Nx red result for each applicable adapter.
- [ ] `[AI]` Introduce the smallest relational schema and repository boundary for the selected shared record.
- [ ] `[AI]` Provision isolated development and test storage without committing private infrastructure identifiers.
- [ ] `[AI]` Implement explicit backup and restore commands and verify them against isolated data.
- [ ] `[AI]` Run targeted unit, integration, behavior-coverage, E2E, and manual restart checks through Nx.

### Phase 2 Gate

- [ ] `[AI]` Authorized shared data survives restart, backup, restore, and release exercises.
- [ ] `[AI]` Live data and backups remain outside Git and the synchronized source workspace.
- [ ] `[AI]` Migrations and rollback behavior are documented and verified.

**Pause safety:** A verified backup and previous compatible release exist before production migration.

## Phase 3 — Recoverable Document Processing

- [ ] `[HUMAN]` Approve the first document format, processor, size limit, retention rule, and output ownership.
- [ ] `[AI]` Specify upload, job-state, failure, retry, processor, and authorization behavior in C4 and Gherkin.
- [ ] `[AI]` Add failing bindings and capture the Nx red result for every applicable adapter.
- [ ] `[AI]` Implement private staging, durable job state, and a supervised allowlisted processor boundary.
- [ ] `[AI]` Cover valid, corrupt, oversized, timed-out, unauthorized, retried, and failed document cases.
- [ ] `[AI]` Run targeted unit, local integration, behavior-coverage, E2E, and manual private-route checks through Nx.

### Phase 3 Gate

- [ ] `[AI]` A supported document reaches a visible terminal state without exposing arbitrary host control.
- [ ] `[AI]` Failures preserve the original input and leave retry or recovery state understandable.
- [ ] `[AI]` Processor permissions, resource limits, and storage ownership match the technical documentation.

**Pause safety:** Disable new submissions before rollback; retain originals and durable job records.

## Phase 4 — Operations, Release, and Recovery

- [ ] `[AI]` Specify named administrative actions, audit evidence, health checks, release, and rollback behavior.
- [ ] `[AI]` Add failing bindings and capture the Nx red result for applicable adapters.
- [ ] `[AI]` Implement only fixed administrative actions; expose no shell, Docker socket, or arbitrary launcher.
- [ ] `[AI]` Implement repeatable status, backup, release, health-check, and rollback paths through repository-owned commands.
- [ ] `[AI]` Verify proxy independence across application stop, restart, release, and rollback exercises.
- [ ] `[AI]` Run the complete applicable Nx quick, integration, behavior, targeted E2E, repository, and manual smoke gates.

### Phase 4 Gate

- [ ] `[AI]` A permitted administrator can recover the worker only through named actions.
- [ ] `[AI]` A failed health check can return to a known-good release without losing accepted data.
- [ ] `[AI]` Operational documentation matches tested commands and current runtime boundaries.

**Pause safety:** The previous release, verified backup, and independent private proxy remain available.

## Phase 5 — Knowledge Capture and Completion

- [ ] `[AI]` Review every entry in `learnings.md` and route it to permanent documentation, specifications, governance, a new two-pager, or an explicit discard rationale.
- [ ] `[AI]` Reconcile BRD outcomes, PRD acceptance criteria, technical decisions, C4, Gherkin, READMEs, and this checklist with the delivered system.
- [ ] `[AI]` Run all applicable final Nx and manual verification from a clean delivery state.
- [ ] `[AI]` Record final evidence and update the plan status only after every acceptance condition passes.
- [ ] `[AI]` Move the folder to `plans/done/YYYY-MM-DD__family-app-foundation/` using the completion date and update both indexes.

### Phase 5 Gate

- [ ] `[AI]` No open checklist item or undisposed learning remains.
- [ ] `[AI]` Every relevant specification and project README reflects the as-built system.
- [ ] `[AI]` Required verification passes and the completion date is accurate.

**Pause safety:** Archive only after the delivered system and its durable documentation agree.
