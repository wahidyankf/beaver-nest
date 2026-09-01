# Business Requirements

## Goal

Turn Bnest's single hard-coded revision subject into a reusable learning engine, so a parent can add a new subject by authoring content instead of writing a module, and a child keeps one continuous record of what they have mastered across every subject.

## Roles

- **Child learner:** works through missions, sees progress, earns coins, and returns to review what is due without understanding courses, topics, or scheduling.
- **Parent:** verifies missions that must be checked in person, watches each child's progress, and later spends the coin balance in separately authorized redemption work.
- **Content author (a parent, working in the repository):** adds or changes courses, topics, and missions as reviewed files and ships them with a commit.
- **Maintainer:** ships schema, engine, API, and UI changes without interrupting the routed 24/7 service or losing a child's existing progress.
- **Bnest application:** validates content, enforces per-learner authorization, decides every fact before appending it to the log, awards each coin exactly once, keeps its read models rebuildable, and refuses an unsafe migration.

## Required Outcomes

- One course, topic, and mission model supports every existing Sifat Allah behaviour and at least one unrelated second subject without new modules.
- A mission may belong to several topics and several courses, and a learner who has mastered it does not repeat it when it appears elsewhere.
- Mastery, review scheduling, and coin awards are per learner and survive an application restart, a release, and a rolling revision change.
- A parent can verify an in-person mission for a child, and that verification is attributable and cannot be self-issued by the child.
- A per-mission coin reward is credited exactly once, at first mastery, and a retry, a reconnect, or a repeated submission never credits it twice.
- Every fact the engine knows — learner and content alike — exists first as an event in an append-only log, so history is complete by construction rather than by discipline.
- Any read model can be discarded and rebuilt from the log, reproducing byte-identical results, so recovery from a corrupted or mis-shaped projection is a replay rather than a data migration.
- Later features attach as subscribers or as new projectors, without editing the path that records mastery.
- Every existing Sifat Allah learner keeps their exact learned, mastered, and difficult state after the cutover, proven through the product journey with the previous source unavailable.
- Content is reviewable before it reaches a child: a new subject arrives through version control, not through a text box.
- One authenticated GraphQL boundary answers what the UI shows, so behaviour can be verified across the API and UI boundaries in the same journey.

## Business Rules

- The event log is the single source of truth. Every learning table the application queries is derived from it and may be rebuilt at any time. The log is shared Bnest infrastructure partitioned by domain, not a learning-owned table, so a later domain can adopt it without new machinery.
- Authored content files are the input to a sync command, not an authority. The sync appends only real differences, and a sync that finds none appends nothing. The API exposes no content mutation.
- Content sync never deletes a course, topic, or mission that a learner has touched. Removal from the repository retires the row and preserves its progress and attempt history.
- A learner may read and change only their own progress. A user holding `parents` or `admin` may read any household learner's progress and verify pending in-person missions.
- A `parent_check` mission is mastered only by a verification recorded against a different user than the learner.
- Coins are earned only through first mastery in this plan. No balance may be reduced, and no redemption exists until separately authorized work delivers it.
- Business invariants are decided by the command handler before the append and protected by the stream's expected version, not by a constraint on a derived table. No subscriber is required for correctness.
- Stored events are never edited or deleted. A wrong fact is answered by a compensating event, and the database enforces this with append-only triggers rather than convention.
- GraphiQL and any introspection convenience are available only when `dev_routes` is enabled; the production endpoint serves the same schema without the explorer.
- The learning UI never shows one child's progress or coin balance to another child.

## Non-goals

- Coin redemption, a reward catalogue, balance deduction, badges, streaks, or leaderboards.
- In-app content authoring, rich-media hosting, prose grading, or cross-topic prerequisites.
- Public API access, API tokens, or any access path that does not carry an existing browser session.
- Deleting retired Sifat Allah records inside this plan.
- Changing chat, theme, storage, backup, or identity product behaviour.

## Risks and Controls

- **Experience regression at the Sifat Allah cutover:** the bespoke screen is replaced by a generic runner, so the child could lose the trail, the automatic advance, and the celebration that make the current screen work. Control: the existing `sifat_allah.feature` corpus is the acceptance bar for the generic runner, and the route is cut over only after that corpus passes unchanged.
- **Progress loss during migration:** a child's mastery is the least replaceable data in the household. Control: expand-and-contract with immutable source retention, per-learner checksummed conversion, fresh-process verification with the previous source unavailable, and a retained rollback reader.
- **Duplicate coin awards:** a retry, a double submit, or a reconnect could credit twice. Control: the ledger carries a unique earning identity per learner and mission, the credit is written inside the mastery transaction, and a second attempt is a no-op rather than an error.
- **Non-deterministic replay:** a projector that reads the system clock or any value outside the log would rebuild differently every time, quietly destroying the recovery story. Control: projectors take time and order from the event, and a test rebuilds a representative workload and compares projection checksums.
- **Permanent wrong facts:** an append-only log keeps a defective event forever, and fixing the code does not fix history. Control: event versioning and upcasters from the first release, compensating events as the only correction, and no in-place rewrite path in the schema.
- **Event-driven drift:** an asynchronous subscriber could be mistaken for a guarantee. Control: projections are written in the append transaction, durable subscribers keep their own cursor and resume, delivery is explicitly at-least-once, and no correctness rule depends on delivery.
- **Reused mission, split mastery:** keying progress by course or topic would silently repeat known work. Control: the progress key is `(user_id, mission_id)` and the schema has no course or topic column to make the mistake possible.
- **Content defect reaching a child:** a malformed mission could break the runner mid-session. Control: sync validates the whole corpus against the mission-kind contract and applies it transactionally; a rejected corpus leaves the previous read model serving.
- **New API surface:** GraphQL adds a reachable boundary with per-field authorization. Control: session-only access, allow-listed operations, no content mutation, depth and complexity limits, value-free errors, and explorer gated to development.
- **Service interruption:** this plan changes schema, routes, and a live screen. Control: candidate preparation, Caddy promotion, routed revision proof, continuous exact-origin responsiveness sampling, LiveView reconnect without refresh, bounded drain, and a responsiveness rollback trigger.
- **Sensitive evidence:** synthetic `test-user-` identities and structural, value-free logs only.

## Success Measures

- Sifat Allah runs entirely on the engine, `BnestApp.SifatAllah` and `BnestAppWeb.SifatAllahLive` are gone, and the existing behaviour corpus passes against the generic runner.
- A second, unrelated subject is added by files and a sync alone, with no Elixir change.
- Every migrated learner's mastered and difficult sets match their pre-migration values, verified through the product journey in a fresh process with the previous source unavailable.
- Coin totals equal the sum of the rewards of the distinct missions each learner mastered through the engine, unchanged by a re-run of the sync or a repeated submission. Mastery carried over by the Sifat Allah migration credits nothing; the reasoning is recorded in [the migration design](tech-docs/05-migration-design.md).
- Dropping every projection and replaying the log reproduces byte-identical projections, verified by checksum.
- Every projection row traces to an event, and no writer can produce a projection row without one.
- Application, integration, behaviour, and focused E2E gates are green, including the new `api` end-to-end project.
- The routed origin records zero failures, p95 latency at or below 500 ms, and every sample at or below 2 seconds from preflight through drain.
- No household record, credential, or path enters Git.
