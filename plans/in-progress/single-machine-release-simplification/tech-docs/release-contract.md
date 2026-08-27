# Deterministic Release Contract

This companion defines the implementation and verification contract for the selected alternative. Read the [technical decision guide](README.md) first for the current condition, port allocation, recommendation, and alternatives.

## Deterministic Release Constraints

The selected mechanism must expose one revision-bound state machine even if it composes existing Nx targets internally:

1. **Preflight:** acquire the host-wide release lock; resolve one clean `main` revision; verify unchanged inputs, capacity admission, exact port owners, and active-route health; and refuse missing configuration without printing values. A busy lock queues/coalesces the request, while insufficient safe headroom returns a non-mutating deferred result.
2. **Pre-artifact gates:** run a fixed target manifest covering applicable quick, integration, behavior, repository, and isolated browser tests. Any failure or indeterminate result stops before build.
3. **Build:** create or verify one immutable revision-addressed artifact and manifest its revision, toolchain, content digest, passed gate evidence, and declared data/schema compatibility.
4. **Migration proof when declared:** verify backup/restore evidence and the migration checksum; acquire one lock; expand, migrate, and prove compatibility according to [migration design](migration-design.md). Failure leaves the active route unchanged and stops before candidate activation.
5. **Candidate or restart proof:** verify readiness, revision, port ownership, and observed schema compatibility; run release-specific HTTP and browser checks that cannot be proven before build.
6. **Activate:** promote an independently verified candidate or perform the explicitly bounded single-slot restart.
7. **Routed proof:** verify intended revision, HTTPS, WebSocket reconnection, current route, no duplicate action, no progress loss, and representative isolated data behavior at the exact user origin.
8. **Recover or clean:** rollback automatically on a failed activation/proof; otherwise complete bounded drain, old-process retirement, worktree cleanup, artifact retention, and recording of deferred contract work.

Every stage returns a versioned structured summary and a nonzero failure status. It may reference detailed machine-local logs, but routine AI operation consumes only the bounded summary. Retrying with the same revision must be idempotent or return one exact recovery transition; it must never silently skip a gate because an artifact directory already exists. Capacity deferral and queued/coalesced requests are normal non-mutating outcomes, not release failures.

### Exact pre-artifact manifest

Until Phase 1 proves complete cache inputs and outputs, release evidence must use `--skip-nx-cache`. This spends more test time but removes cached success as a release decision. The composed release target must invoke this fixed order without asking an operator or AI to select tests:

| Order | Canonical Nx command                                                                                                                                           | Required result                                                                                 |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| 1     | `npm exec -- nx run -p bnest-app -t test:quick --skip-nx-cache`                                                                                                | Typecheck, lint, unit, unit coverage, and behavior coverage pass.                               |
| 2     | `npm exec -- nx run -p bnest-app -t test:integration --skip-nx-cache`                                                                                          | Local-only integration scenarios pass.                                                          |
| 3     | `npm exec -- nx run -p bnest-app-e2e -t test:release-quick --skip-nx-cache`                                                                                    | E2E harness typecheck and lint pass without repeating application quick.                        |
| 4     | `npm exec -- nx run -p bnest-app-e2e -t test:e2e --skip-nx-cache -- --workers 1 --grep "An automatic LiveView reconnect preserves"`                            | Desktop, tablet, and mobile reconnect journeys pass sequentially without reload.                |
| 5     | `npm exec -- nx run -p bnest-app-e2e -t test:e2e --skip-nx-cache -- --workers 1 --project chromium --grep "Ten synthetic visitors preserve recoverable state"` | Ten distinct synthetic identities across three groups preserve route and draft; cleanup passes. |
| 6     | `npm exec -- nx run -p badakmini-cli -t test:repo --skip-nx-cache`                                                                                             | Repository links, maps, word budgets, and Mermaid checks pass.                                  |

The Bnest behavior-coverage target is named explicitly above but is not duplicated because it is already a dependency of the application quick gate and the E2E runtime gate. The isolated browser run uses `test-user-<suite>-<run-id>`, a distinct marked `data/test/runs/<run-id>/` root and browser context, synthetic payloads only, and the exact leased application origin including hostname and port. Release qualification covers 10 clients across 3 groups, including at least one two-client resumable state session. Its `finally` cleanup stops its browsers and servers, releases its port lease, and removes only the validated marked run root; cleanup failure fails the gate and reports only the safe synthetic path.

When an artifact declares a data/schema migration, its unit and isolated adapter tests are part of the application quick/integration gates. The host migration and compatibility proof runs only after the artifact exists because it consumes that artifact's manifest, but it remains before candidate activation and cannot reuse cached live-state evidence.

### Transition and evidence contract

| Transition               | Declared success condition                                                                                                                      | Failure edge                                                                    |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Preflight → gates        | Lock acquired; clean `main` SHA fixed; capacity and ports admitted; active local/routed readiness/revision pass; required configuration exists. | Defer or queue without mutation, or stop before tests/build and restore health. |
| Gates → build            | Every manifest entry passes for the same SHA and isolated cleanup passes.                                                                       | Stop before artifact creation.                                                  |
| Build → migration proof  | Artifact manifest contains SHA, toolchain versions, digest, gate IDs, schema range, migration checksum, and build duration.                     | Remove only incomplete revision-addressed output; active route is unchanged.    |
| Migration → candidate    | No migration is required, or backup, lock, expand/backfill, N−1 compatibility, and safe retry evidence pass.                                    | Keep the active route; record expanded state; never improvise a down change.    |
| Candidate → promote      | Inactive slot returns ready with the exact SHA and schema range; candidate-only HTTP and isolated journey pass.                                 | Retire failed candidate; active route is unchanged.                             |
| Promote → routed proof   | Caddy route reports the SHA; Tailnet HTTPS and connected LiveView/WebSocket pass at the exact origin and declared load.                         | Warm rollback before retirement, then prove the previous routed revision.       |
| Routed proof → cleanup   | Route, data, input, partial output, progress, session version, ordered events, and exactly-once actions survive automatically.                  | Warm rollback and preserve safe evidence for diagnosis.                         |
| Cleanup → complete       | Drain deadline expires; inactive process and worktree are gone; only active and prior verified artifacts remain.                                | Report cleanup failure; never delete an unresolved path.                        |
| Complete → cold rollback | Recorded prior SHA is re-prepared in the inactive slot, passes readiness/revision, and is promoted and routed-proven.                           | Keep the current healthy route and stop recovery mutation.                      |

Each transition records bounded machine-local evidence; the transaction emits exactly one bounded final JSON result. `schemaVersion` is exactly `1`; `releaseRevision` is a 40-character lowercase Git SHA when pinned and `null` for an unpinned capacity deferral; states and `nextTransition` come from the documented machine; `outcome` is `passed`, `failed`, `rolled-back`, `deferred`, or `queued`; `evidenceIds` is an ordered unique list; `durationMs` is a nonnegative integer; `migrationState` is declared; and `errorCategory` is `null` on success or one of `capacity`, `concurrency`, `configuration`, `port`, `preflight`, `gate`, `artifact`, `migration`, `candidate`, `promotion`, `routed-proof`, `continuity`, `rollback`, or `cleanup`. Unknown fields are allowed, but missing required fields fail validation.

```json
{
  "schemaVersion": 1,
  "releaseRevision": "0123456789abcdef0123456789abcdef01234567",
  "fromState": "cleanup",
  "toState": "complete",
  "outcome": "passed",
  "evidenceIds": [
    "bnest-quick",
    "bnest-integration",
    "e2e-quick",
    "release-recovery-e2e",
    "release-load-e2e",
    "repository"
  ],
  "durationMs": 1234,
  "nextTransition": "complete",
  "errorCategory": null,
  "migrationState": "not-required"
}
```

## Mermaid Legibility Prerequisite

The release state diagram exposed a deterministic documentation failure: long transition labels can be clipped without a syntax error. Badakmini's `md mermaid validate` leaf now emits renderer-free `mermaid-legibility` findings for supported diagram types. It measures each visible node/state segment at a maximum of 32 Unicode grapheme clusters and each edge/transition segment at 24 after entity decoding, markup removal, and whitespace normalization. `<br>`, `<br/>`, and escaped newlines are segment boundaries; `;` in state-transition labels is rejected. Class members, ER attributes, requirement body fields, directives, comments, and front matter are excluded.

```mermaid
flowchart LR
    Source[Changed Markdown] --> Extract[Extract labels]
    Extract --> Measure[Normalize and measure]
    Measure -->|Within limits| Pass[Pass]
    Measure -->|Over limit| Finding[Structured finding]
    Finding --> Hook[Pre-push repository gate]
```

The JSON finding includes `kind`, `path`, `line`, `labelRole`, `actualLength`, `limit`, and `message`. Canonical Gherkin fixtures cover supported diagram types, exact boundary values, split labels, combining graphemes, excluded declarations, and state semicolons. The pre-push repository gate triggers for documentation, governed trees, Badakmini source/adapters, or the hook itself. The check uses no renderer, browser, network, or new package.

## Specification Changes

- `[E] specs/apps/bnest/app/behaviours/chat.feature`: require automatic transport reconnect, current-route preservation, and unsent composer recovery without reload.
- `[E] specs/apps/bnest/app/architecture.md`: show the deterministic release transaction, capacity/port/migration boundaries, browser recovery, and future authoritative multiplayer session boundary.
- `[E] apps/bnest-app/test/behaviour/driver.ex`, `apps/bnest-app/test/behaviour/steps/home_page_steps.exs`, `apps/bnest-app/test/unit/support/home_page_driver.ex`, `apps/bnest-app/test/integration/support/home_page_driver.ex`, and `apps/bnest-app-e2e/tests/steps/browser.steps.ts`: add draft/route bindings and adapters; make the deployment step disconnect and reconnect the transport.
- Release orchestration behavior is proven by deterministic Node unit tests because it operates OS processes and machine-local deployment state; shared application adapters must never execute it against production.

## File Impact

- `[E] apps/bnest-app/tools/deployment.mjs`: immutable-artifact refusal and production-origin-safe candidate preparation.
- `[N] apps/bnest-app/tools/release.mjs`, `apps/bnest-app/tools/resource-monitor.mjs`, `apps/bnest-app/tools/verify-liveview.mjs`, and `apps/bnest-app/tools/production-origin.mjs`: transaction, aggregate resource evidence, anonymous routed proof, and origin validation.
- `[N] apps/bnest-app/tools/release.test.mjs`, `apps/bnest-app/tools/continuity-contract.mjs`, and `apps/bnest-app/tools/continuity-contract.test.mjs`: failure-state, serialization, capacity, migration, rollback, and multi-client resume proof.
- `[N] apps/bnest-app/tools/port-lease.mjs`, `apps/bnest-app/tools/port-lease.d.mts`, and `apps/bnest-app/tools/serve.mjs`: process-marked bounded listener leases and development startup.
- `[E] apps/bnest-app/project.json`, `apps/bnest-app/mix.exs`, `apps/bnest-app/lib/bnest_app_web/live/chat_live.ex`, `apps/bnest-app/test/behaviour/driver.ex`, `apps/bnest-app/test/behaviour/steps/home_page_steps.exs`, `apps/bnest-app/test/unit/support/home_page_driver.ex`, and `apps/bnest-app/test/integration/support/home_page_driver.ex`: Nx targets, layer-owned coverage, form auto-recovery, and recovery bindings/adapters.
- `[E] apps/bnest-app-e2e/project.json`, `apps/bnest-app-e2e/playwright.config.mts`, `apps/bnest-app-e2e/tools/run-e2e.mts`, `apps/bnest-app-e2e/tests/support/test-identity.ts`, `apps/bnest-app-e2e/tests/steps/browser.steps.ts`, and `[N] apps/bnest-app-e2e/tests/steps/release-recovery.steps.ts`: bounded release quick gate, leased origin, distinct identities, and no-reload multi-client reconnect.
- `[E] specs/apps/bnest/app/behaviours/chat.feature` and `specs/apps/bnest/app/architecture.md`: canonical automatic recovery, release state machine, and authoritative multiplayer boundary.
- `[E] apps/badakmini-cli/Governance.fs`, `apps/badakmini-cli/Cli.fs`, `apps/badakmini-cli/tests/contract/BehaviourSteps.fs`, `apps/badakmini-cli/tests/contract/BehaviourSupport.fs`, `apps/badakmini-cli/tests/unit/UnitDriver.fs`, `apps/badakmini-cli/tests/integration/IntegrationDriver.fs`, `apps/badakmini-cli-e2e/E2eDriver.fs`, and `apps/badakmini-cli/README.md`: label extraction, structured findings, adapters, CLI contract, and operation.
- `[E] specs/apps/badakmini/cli/behaviours/mermaid-cli.feature`, `specs/apps/badakmini/cli/behaviours/mermaid-governance.feature`, and `specs/apps/badakmini/cli/architecture.md`: exact legibility behavior and C4 responsibility.
- `[E] .husky/pre-push`, `AGENTS.md`, `repo-governance/README.md`, `repo-governance/conventions/markdown-visualizations.md`, `repo-governance/conventions/push-hook-verification.md`, `repo-governance/development/live-service-continuity.md`, and `repo-governance/workflows/development-caddy-deployment.md`: point-of-use rules, canonical detail, and enforcement trigger.
- `[E] README.md`, `apps/bnest-app/README.md`, and `apps/bnest-app-e2e/README.md`: repository and project operating commands and port ownership.
- `[E] repo-governance/workflows/red-green-refactor.md` and `plans/done/2026-08-26__bnest-centralized-data/tech-docs/migration-design.md`: Mermaid corpus repairs required before enforcement.
- `[E] plans/in-progress/single-machine-release-simplification/README.md`, `brd.md`, `prd.md`, `delivery.md`, `learnings.md`, and `tech-docs/`: reconciled decisions, implementation, safe evidence, and remaining live/archival checkpoints.

## Decision Criteria

A later choice must use measurements collected without user data or secret exposure and show all of the following:

1. The active routed HTTPS service is healthy before work, every pre-artifact gate passes for one unchanged revision, and the resulting artifact is verified at that revision.
2. Every affected connected page remains usable or automatically reconnects/updates at the exact served HTTPS origin without a manual reload.
3. An overlapping design retains the previous usable backend until routed proof passes; a single-slot design proves a bounded interruption, automatic state recovery, and deterministic restart of the prior artifact.
4. Normal steady state contains no unneeded Phoenix slot, temporary worktree, watcher, candidate, or proxy.
5. The measured temporary overlap fits the machine's available CPU, memory, file-descriptor, and disk budget.
6. Mixed-version readers and writers remain compatible for the shared runtime root, or the release declares and safely handles the exception.
7. If Caddy is removed, the selected path explicitly proves how it replaces—or makes unnecessary—Caddy's stable listener, atomic promotion, five-minute WebSocket drain, health-gated upstream routing, and previous-slot rollback.
8. Before/after assertions prove that the current route, acknowledged data, recoverable in-progress input, partial output, and completed progress survive without duplicate actions or user reconstruction.
9. The routine path needs no free-form AI choice between stages and reports enough structured evidence to decide success, rollback, cleanup, or diagnosis without loading verbose logs.
10. Authenticated state/progress tests use a marked isolated test root and exact served application origin. Production-origin checks remain read-only and anonymous unless an approved mechanism proves test-data isolation; lack of that mechanism blocks live authenticated proof rather than permitting a real-user test.
11. Every listener has one declared owner, development cannot collide with a production slot, and the selected alternative's exact production/candidate/test port path passes preflight.
12. Data changes follow expand–migrate–verify–contract, run once under a lock, preserve N−1 rollback compatibility, and defer destructive contract work until the rollback window closes.
13. One release owns the host lock; newer requests queue/coalesce; the transaction defers without mutation when the documented RAM/CPU/disk envelope cannot coexist with 5–10 development workloads.
14. Repeated-release proof covers three serialized releases under 10 connected clients across 3 groups with no process, port, lock, artifact, resource, or user-state leak.
