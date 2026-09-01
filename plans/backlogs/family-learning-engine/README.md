# Family Learning Engine

**Status:** Backlog

**Created:** 2026-09-01

**Scope:** An event-sourced course/topic/mission learning engine with per-learner mastery, coin earning, a read-mostly GraphQL boundary, one generic mission runner UI, and the retirement of the bespoke Sifat Allah screen onto that engine

## Context

Bnest already teaches one subject. `BnestApp.SifatAllah` hard-codes a 40-pair curriculum, six question directions, and its own mastery vocabulary, and `BnestAppWeb.SifatAllahLive` renders a bespoke screen for it. Nothing in that design can carry a second subject: adding one means copying a module, a LiveView, a record type, and a feature file.

The household needs more than one subject. This plan generalizes the idea that already works — small units, mastery instead of completion, scheduled review — into content that lives in the database and a runner that renders it, so a new subject is authored rather than programmed.

Three structural facts drive the design. First, a mission is reusable: the same mission may appear in several topics and several courses, so the content model is a graph and not a tree. Second, because a mission is reusable, mastery belongs to the `(learner, mission)` pair alone; carrying course or topic into the progress key would split one learner's mastery across contexts and make scheduled review repeat work the learner already knows. Third, the engine is event sourced: an append-only event log is the system of record for learner facts and content alike, and every table the application queries is a projection that can be dropped and rebuilt from that log.

![Selected desktop mission runner: topic trail beside a single focused mission with progress and answer states](assets/ui-trail-hifi-desktop.svg)

## Scope

- Add `bnest_events`, a shared append-only event log partitioned by domain, its cursor tables, and the learning projections — courses, topics, missions, their ordered many-to-many links, progress, attempts, and the coin ledger — through two committed, guarded, additive migrations.
- Author content as version-controlled files under `apps/bnest-app/priv/learning/` and treat them as the input to a sync command that appends the difference as content events; the files stay reviewable in Git, the log stays the only authority.
- Support six mission kinds: `reading`, `video`, `multiple_choice`, `short_text`, `flashcard`, and `parent_check`.
- Record per-learner mastery, spaced review scheduling, and parent verification as events on the learner's stream, projected into `(user_id, mission_id)` progress and attempt rows.
- Award a per-mission coin reward exactly once, at first mastery, by appending the earning event in the same transaction as the mastery event, and expose the learner's balance read-only.
- Append every state change to a learner or content stream in the `learning` domain with an expected version, apply projections in the same transaction, and publish after commit to live and durable subscribers, so later features attach instead of editing the mastery path.
- Ship a projection rebuild task and a test proving a rebuild from the log reproduces byte-identical projections, so recovery from a bad read model is a replay rather than a data migration.
- Expose one authenticated GraphQL endpoint at `/api/graphql`: content read-only, mutations limited to progress and parent verification, GraphiQL only under `dev_routes`.
- Implement one generic mission runner and the learner and parent routes it needs.
- Migrate Sifat Allah onto the engine: generate its missions deterministically from the existing curriculum, convert every learner's stored progress into imported events, make the generic runner satisfy the existing Sifat Allah behaviour corpus, then retire `SifatAllahLive` and the `sifat-allah-progress` record type.

## Non-goals

- In-app authoring, editing, or deleting of course content. Content mutations do not exist in the GraphQL schema, and no admin CRUD screen is built; adding a subject is a commit.
- Cross-topic or cross-course prerequisites. Ordering within a topic is in scope; unlocking a topic based on another topic is not.
- Grading free-form prose, media upload, media hosting, or a video player beyond an embedded external URL.
- Coin spending: a reward catalogue, redemption, balance deduction, approval flow, or any spending screen. This plan writes only `earned` ledger entries; the ledger and balance are designed to accept `spent` entries without a schema change, and a separate authorized plan owns redemption.
- Badges, daily streaks, leaderboards, or comparison between family members.
- Adopting the shared event log in another domain such as chat, schedules, or identity. This plan delivers the log as reusable infrastructure and is its only writer; migrating an existing domain onto it is separate authorized work.
- A public or token-authenticated API. The GraphQL endpoint reuses the existing browser session and is not reachable without one.
- Deleting the retired flat-file or SQLite Sifat Allah progress records. Retirement of the source record type is expand-and-contract with a retention window; destructive deletion belongs to a later authorized plan.

## Approach

1. Expand the event log, the projectors, and the content sync first, with no reader depending on them.
2. Add the command handlers and the GraphQL boundary next, so every later layer has one queryable, testable contract and one extension point instead of ad-hoc hooks.
3. Build the generic runner and its routes against that contract, holding it to the existing Sifat Allah behaviour corpus as the objective bar.
4. Migrate Sifat Allah progress and cut its route over to the runner last, when the runner has already been proven to satisfy the corpus.
5. Promote through Caddy with a candidate, prove the routed revision and continuous responsiveness, reconnect LiveView without a refresh, drain, and clean up.

## Dependencies

- The existing SQLite authority and `BnestApp.SqliteRepo` delivered by [Bnest SQLite Storage](../../done/2026-08-29__bnest-sqlite-storage/README.md).
- The existing identity roles `children`, `parents`, and `admin`, and the existing session boundary in `BnestAppWeb.UserAuth`.
- `absinthe` and `absinthe_plug`, reviewed under the [dependency-selection standard](../../../repo-governance/development/dependency-selection.md); the decision record lives in [the GraphQL API document](tech-docs/03-graphql-api.md#dependency-decision).
- The current Sifat Allah curriculum data in `BnestApp.SifatAllah` and the stored `sifat-allah-progress` records, which are this plan's migration source.

## Navigation

- [Business requirements](brd.md)
- [Product requirements](prd.md)
- [Technical design](tech-docs/README.md)
- [Delivery checklist](delivery.md)
- [Learnings](learnings.md)
- [UI assets](assets/README.md)
- Prior art: [SQLite storage schema and cutover](../../done/2026-08-29__bnest-sqlite-storage/tech-docs.md) and [scheduled backups](../../done/2026-08-30__bnest-daily-backups-and-schedules/README.md)

## Directory Map

- [`assets/`](assets/README.md) — lo-fi alternatives and the selected hi-fi responsive mission-runner design.
- [`brd.md`](brd.md) — business goals, roles, outcomes, boundaries, and risks.
- [`delivery.md`](delivery.md) — ordered implementation, verification, rollout, and reconciliation tasks.
- [`learnings.md`](learnings.md) — safe observations, exploratory and usability findings, and follow-up routing.
- [`prd.md`](prd.md) — personas, stories, and plan-level acceptance criteria.
- [`tech-docs/`](tech-docs/README.md) — architecture entry point and mapped technical companions.
