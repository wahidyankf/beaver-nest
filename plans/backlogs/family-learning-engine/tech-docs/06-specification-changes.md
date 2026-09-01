# Specification Changes

`specs/` is as-built truth. This document states which plan outcomes become durable contracts, which stay plan-only, and the exact planned delta for each affected file. Execution updates `specs/` with the final as-built result, never with proposed design.

## Which outcomes become contracts

Durable Gherkin contracts: content sync behaviour (AC-01), mission reuse and single mastery (AC-02), mission kinds and pass rules (AC-03), spaced review (AC-04), parent verification and its authorization (AC-05), coin earning (AC-06), API scope and authorization (AC-08), the learner interface (AC-09), and the migration's authority behaviour (AC-11).

Durable C4 changes: the new learning context, its data stores, the GraphQL boundary, the event bus relationship, and the removal of the Sifat Allah component.

Plan-only outcomes, with their verification task:

- **AC-07 event log as the source of truth** and **AC-07b rebuild from the log.** These are internal guarantees with no user-observable behaviour of their own: a learner cannot tell whether a row was projected or stored directly. They are proven by integration tests rather than product Gherkin. Verified by the Phase 2 event-store, projector-determinism, and rebuild tasks in `delivery.md`.
- **AC-10 Sifat Allah parity.** This is a statement about an existing corpus, not a new behaviour. Verified by the Phase 4 parity task, which runs the unchanged corpus against the generic runner.
- **AC-12 active-service rollout.** Deployment behaviour, not product behaviour. Verified by the Phase 6 rollout tasks.

## `specs/apps/bnest/app/behaviours/learning.feature` `[N]`

New canonical corpus for the engine.

```diff
+Feature: Learning through courses, topics, and missions
+  Scenario: A learner continues the next unmastered mission
+  Scenario: A mastered mission is not repeated in another course
+  Scenario: A multiple-choice mission needs two correct answers in a row
+  Scenario: A reading mission is completed by acknowledgement
+  Scenario: A due mission appears in the review queue
+  Scenario: An empty review queue shows the finished state
+  Scenario: A wrong review answer reschedules the mission sooner
+  Scenario: A first mastery credits the mission coins once
+  Scenario: Repeating a mastered mission credits nothing
+  Scenario: A child submits an in-person mission for a parent
+  Scenario: A parent approves a submission for a child
+  Scenario: A child cannot verify their own submission
+  Scenario: A child cannot open the verification queue
+  Scenario: A learner cannot read another learner's progress
+  Scenario: The API offers no content mutation
+  Scenario: The endpoint refuses an unauthenticated request
```

- → Bindings: `apps/bnest-app/test/behaviour/steps/learning_steps.exs`, `apps/bnest-app-e2e/tests/steps/learning.steps.ts`, `apps/bnest-app-e2e/tests/steps/learning_api.steps.ts`, and support in `apps/bnest-app-e2e/tests/support/learning.ts`.
- = Preserve: no existing scenario in another feature changes meaning.
- ✓ Proof: `bnest-app:test:coverage:behaviour` reports the enlarged corpus with no undefined, ambiguous, or unused binding; `bnest-app-e2e:test:e2e` runs the learner and parent journeys and the `api` project runs the endpoint scenarios.

<details>
<summary>Adapter capability per scenario group</summary>

- Content sync, coin idempotence, and event guarantees bind in the Elixir adapters. The browser adapter is incapable of driving a headless sync run and is exempted for those scenarios.
- Route denial, unauthenticated refusal, and explorer absence bind in the `api` browser project, because they depend on the real router and session; the unit adapter is exempted.
- Viewport-specific rendering binds only in the browser adapter.

</details>

## `specs/apps/bnest/app/behaviours/sifat_allah.feature` `[E]`

The corpus is preserved as the parity bar for the generic runner. Only its route changes.

```diff
-    When the child opens "/apps/sifat-allah"
+    When the child opens "/learn/aqidah-dasar"
```

- = Preserve: every scenario name and every assertion, including automatic advance after an answer, locked choices, browser Back returning to the mission dashboard, immediate movement between the learned and difficult queues, varied correct-answer positions, progress surviving reload and a live update, and the exam skipping learned questions until all are learned.
- → Bindings: `apps/bnest-app-e2e/tests/steps/sifat_allah.steps.ts` is rewritten against the generic runner's test identifiers; `apps/bnest-app/test/behaviour/steps/sifat_allah_steps.exs` moves onto the learning context.
- ✓ Proof: the corpus passes unchanged except for the route, before the route is cut over. No scenario may be deleted or weakened to make the runner pass; a scenario the runner cannot satisfy is a runner defect.

## `specs/apps/bnest/app/architecture.md` `[E]`

- **Container View:** add the GraphQL boundary as an entry point into the application container alongside the existing browser and health entry points; note that it carries the same session and adds no new external actor.
- **Component View:** add the shared `BnestApp.EventLog` component with its append, cursor, and dispatch responsibilities, and the `BnestApp.Learning` component with its content sync and progress responsibilities; add their relationships to `BnestApp.SqliteRepo` and to `Phoenix.PubSub`, and record that the log is domain-partitioned shared infrastructure with learning as its first writer; add `BnestAppWeb.LearnLive` and `BnestAppWeb.VerifyLive`; remove `BnestApp.SifatAllah` and `BnestAppWeb.SifatAllahLive` at the contract step, not before.
- **Release and Resumable State:** record that the learning event log is the system of record, that every other learning table is a rebuildable projection, that a rebuild is the recovery path for a bad read model, and that `sifat-allah-progress` remains a readable retained source for at least one release cycle after cutover.
- **Architectural Constraints:** add the four rules this plan depends on — the event log is the only source of truth and every learning table is derived from it; stored events are never edited or deleted, and correction is a compensating event; projectors are deterministic functions of the log and never read the system clock; and progress is keyed by learner and mission only.
- **Behaviour Traceability:** map the new `learning.feature` and the re-routed `sifat_allah.feature`.

The component-view and constraint updates are owned by the Phase 4 architecture task in `delivery.md`; the removal of the Sifat Allah elements is owned by the Phase 5 contract task, so `specs/` always describes the system as built at that moment.

## `specs/apps/bnest/app/behaviours/README.md` `[E]`

- Add a `learning.feature` entry to the directory map in the same change that adds the file.

## Ordering

For every behaviour above the order is fixed by the project rule: update the Gherkin, add failing bindings, confirm the expected red through the Nx target, implement, then verify manually. Specification updates precede implementation; C4 updates record the final as-built state within the phase that changes it.
