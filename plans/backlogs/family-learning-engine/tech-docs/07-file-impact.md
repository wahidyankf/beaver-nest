# File Impact

Every path this plan expects to create, change, move, or delete. `[N]` new, `[E]` edit, `[M]` moved, `[D]` deleted. No directory, glob, or ellipsis stands in for a file.

## Shared event log

Domain-agnostic infrastructure delivered by this plan, owned by no single feature. Learning is its first writer.

```text
apps/bnest-app/lib/bnest_app/event_log.ex                                 [N] append with expected version, read by domain
apps/bnest-app/lib/bnest_app/event_log/registry.ex                        [N] per-domain event names and upcasters
apps/bnest-app/lib/bnest_app/event_log/upcaster.ex                        [N] event version chain behaviour
apps/bnest-app/lib/bnest_app/event_log/dispatcher.ex                      [N] post-commit publish and cursor advance
apps/bnest-app/lib/bnest_app/event_log/schema/event.ex                    [N] bnest_events
apps/bnest-app/lib/bnest_app/event_log/schema/projection_cursor.ex        [N] bnest_projection_cursors
apps/bnest-app/lib/bnest_app/event_log/schema/listener_cursor.ex          [N] bnest_event_listeners
```

## Learning domain

```text
apps/bnest-app/lib/bnest_app/learning.ex                                  [N] public context facade
apps/bnest-app/lib/bnest_app/learning/event.ex                            [N] learning event catalogue and upcasters
apps/bnest-app/lib/bnest_app/learning/command.ex                          [N] load, decide, append, project
apps/bnest-app/lib/bnest_app/learning/projector.ex                        [N] deterministic apply and checkpoints
apps/bnest-app/lib/bnest_app/learning/rebuild.ex                          [N] drop and replay projections
apps/bnest-app/lib/bnest_app/learning/corpus.ex                           [N] corpus reader and validator
apps/bnest-app/lib/bnest_app/learning/mission_kind.ex                     [N] kind payload and pass-rule contract
apps/bnest-app/lib/bnest_app/learning/content.ex                          [N] sync command handler and corpus diff
apps/bnest-app/lib/bnest_app/learning/catalogue.ex                        [N] course, topic, and trail queries
apps/bnest-app/lib/bnest_app/learning/progress.ex                         [N] attempt and mastery decisions
apps/bnest-app/lib/bnest_app/learning/review.ex                           [N] interval ladder and due queue
apps/bnest-app/lib/bnest_app/learning/coins.ex                            [N] earning decision and balance
apps/bnest-app/lib/bnest_app/learning/verification.ex                     [N] parent submission and decision
apps/bnest-app/lib/bnest_app/learning/authorization.ex                    [N] learner and parent access rules
apps/bnest-app/lib/bnest_app/learning/sifat_allah_migration.ex            [N] imported-event conversion
```

## Learning projection schemas

```text
apps/bnest-app/lib/bnest_app/learning/schema/course.ex                    [N] projection
apps/bnest-app/lib/bnest_app/learning/schema/topic.ex                     [N] projection
apps/bnest-app/lib/bnest_app/learning/schema/mission.ex                   [N] projection
apps/bnest-app/lib/bnest_app/learning/schema/course_topic.ex              [N] projection
apps/bnest-app/lib/bnest_app/learning/schema/topic_mission.ex             [N] projection
apps/bnest-app/lib/bnest_app/learning/schema/mission_progress.ex          [N] projection
apps/bnest-app/lib/bnest_app/learning/schema/mission_attempt.ex           [N] projection
apps/bnest-app/lib/bnest_app/learning/schema/coin_entry.ex                [N] projection
```

## Database and tasks

```text
apps/bnest-app/priv/sqlite_repo/migrations/20260901000000_create_event_log.exs         [N] shared log and cursors
apps/bnest-app/priv/sqlite_repo/migrations/20260901000100_create_learning_projections.exs [N] learning projections
apps/bnest-app/lib/mix/tasks/bnest.learning.sync.ex                                    [N] headless content sync
apps/bnest-app/lib/mix/tasks/bnest.learning.rebuild_projections.ex                     [N] drop and replay
apps/bnest-app/lib/mix/tasks/bnest.learning.generate_sifat_allah.ex                    [N] corpus generator
apps/bnest-app/lib/mix/tasks/bnest.learning.migrate_sifat_allah.ex                     [N] progress migration
apps/bnest-app/lib/bnest_app/application.ex                                            [E] supervise the event dispatcher
apps/bnest-app/project.json                                                            [E] learning Nx targets
```

## Authored corpus

The generated Sifat Allah mission files are committed. Their exact set is deterministic: `sifat-allah/<pair_id>/kenalan` for each of the 40 pairs, and `sifat-allah/<pair_id>/<kind>` for each of the 6 question kinds, giving 280 files under `apps/bnest-app/priv/learning/missions/sifat-allah/`. The generator task owns their creation and a test asserts regeneration produces no diff.

```text
apps/bnest-app/priv/learning/courses/aqidah-dasar.json                    [N] first course
apps/bnest-app/priv/learning/topics/sifat-wajib-allah.json                [N] pair topic
apps/bnest-app/priv/learning/topics/sifat-mustahil-allah.json             [N] opposite topic
apps/bnest-app/priv/learning/missions/sifat-allah/wujud/kenalan.json      [N] generated, first of 280
apps/bnest-app/priv/learning/missions/sifat-allah/wujud/wajib-meaning.json [N] generated
apps/bnest-app/priv/learning/README.md                                    [N] authoring guide and map
```

## Web surfaces

```text
apps/bnest-app/lib/bnest_app_web/live/learn_live.ex                       [N] course list
apps/bnest-app/lib/bnest_app_web/live/learn_course_live.ex                [N] topic trail
apps/bnest-app/lib/bnest_app_web/live/mission_live.ex                     [N] generic mission runner
apps/bnest-app/lib/bnest_app_web/live/review_live.ex                      [N] due queue
apps/bnest-app/lib/bnest_app_web/live/verify_live.ex                      [N] parent queue
apps/bnest-app/lib/bnest_app_web/components/learning_components.ex        [N] trail, card, choice, coin badge
apps/bnest-app/lib/bnest_app_web/router.ex                                [E] learn routes, API scope, GraphiQL
apps/bnest-app/assets/js/learning_trail.js                                [N] trail and history hook
apps/bnest-app/assets/js/learning_celebration.js                          [N] reduced-motion-aware celebration
apps/bnest-app/assets/js/app.js                                           [E] register learning hooks
apps/bnest-app/assets/css/app.css                                         [E] trail and runner styles
```

## GraphQL boundary

```text
apps/bnest-app/lib/bnest_app_web/graph/schema.ex                          [N] root schema
apps/bnest-app/lib/bnest_app_web/graph/types/learning_types.ex            [N] object and enum types
apps/bnest-app/lib/bnest_app_web/graph/resolvers/learning_resolver.ex     [N] resolvers
apps/bnest-app/lib/bnest_app_web/graph/middleware/authorize.ex            [N] per-field authorization
apps/bnest-app/lib/bnest_app_web/graph/context_plug.ex                    [N] session to viewer
apps/bnest-app/mix.exs                                                    [E] absinthe dependencies
apps/bnest-app/mix.lock                                                   [E] pinned versions
```

## Retired Sifat Allah code

```text
apps/bnest-app/lib/bnest_app/sifat_allah.ex                               [D] curriculum becomes content
apps/bnest-app/lib/bnest_app_web/live/sifat_allah_live.ex                 [D] replaced by the runner
apps/bnest-app/assets/js/sifat_history.js                                 [D] replaced by learning_trail.js
apps/bnest-app/assets/js/sifat_celebration.js                             [D] replaced by learning_celebration.js
apps/bnest-app/test/unit/bnest_app/sifat_allah_test.exs                   [D] behaviour moves to learning tests
apps/bnest-app/test/integration/bnest_app_web/sifat_allah_live_test.exs   [D] replaced by runner tests
apps/bnest-app/lib/bnest_app/storage/record_map.ex                        [E] keep the retained reader entry
```

## Application tests

```text
apps/bnest-app/test/unit/bnest_app/learning/review_test.exs                       [N] interval ladder
apps/bnest-app/test/unit/bnest_app/learning/projector_test.exs                    [N] determinism, no clock reads
apps/bnest-app/test/unit/bnest_app/learning/mission_kind_test.exs                 [N] payload and pass-rule contract
apps/bnest-app/test/unit/bnest_app/learning/corpus_test.exs                       [N] slug and corpus validation
apps/bnest-app/test/unit/bnest_app/learning/authorization_test.exs                [N] access matrix
apps/bnest-app/test/integration/bnest_app/learning/schema_test.exs                [N] DDL contract, idempotent apply
apps/bnest-app/test/integration/bnest_app/event_log/event_log_test.exs            [N] append-only triggers, stream version, domain scoping
apps/bnest-app/test/integration/bnest_app/event_log/dispatcher_test.exs           [N] cursors, resume, idempotence
apps/bnest-app/test/integration/bnest_app/learning/rebuild_test.exs               [N] byte-identical replay
apps/bnest-app/test/unit/bnest_app/event_log/catalog_spec_test.exs                [N] registry and catalogue agree
apps/bnest-app/test/integration/bnest_app/event_log/upcaster_test.exs             [N] event version chain
apps/bnest-app/test/integration/bnest_app/learning/content_test.exs               [N] sync diff, rejection, retirement
apps/bnest-app/test/integration/bnest_app/learning/progress_test.exs              [N] mastery, streaks, review
apps/bnest-app/test/integration/bnest_app/learning/coins_test.exs                 [N] exactly-once earning
apps/bnest-app/test/integration/bnest_app/learning/verification_test.exs          [N] parent decision rules
apps/bnest-app/test/integration/bnest_app/learning/sifat_allah_migration_test.exs [N] conversion and blocking
apps/bnest-app/test/integration/bnest_app_web/graph/learning_query_test.exs       [N] every query
apps/bnest-app/test/integration/bnest_app_web/graph/learning_mutation_test.exs    [N] every mutation
apps/bnest-app/test/integration/bnest_app_web/graph/authorization_test.exs        [N] per-field denial matrix
apps/bnest-app/test/integration/bnest_app_web/graph/limits_test.exs               [N] depth, complexity, batching
apps/bnest-app/test/integration/bnest_app_web/mission_live_test.exs               [N] runner states
apps/bnest-app/test/integration/bnest_app_web/verify_live_test.exs                [N] parent queue and denial
apps/bnest-app/test/behaviour/steps/learning_steps.exs                            [N] shared corpus bindings
apps/bnest-app/test/behaviour/steps/sifat_allah_steps.exs                         [E] rebind onto the engine
apps/bnest-app/test/support/learning_fixtures.ex                                  [N] synthetic corpus and learners
```

## End-to-end

```text
apps/bnest-app-e2e/tests/steps/learning.steps.ts                          [N] learner and parent journeys
apps/bnest-app-e2e/tests/steps/learning_api.steps.ts                      [N] routed endpoint scenarios
apps/bnest-app-e2e/tests/support/learning.ts                              [N] setup, assertions, isolation
apps/bnest-app-e2e/tests/steps/sifat_allah.steps.ts                       [E] rebind to the generic runner
apps/bnest-app-e2e/playwright.config.mts                                  [E] add the browserless api project
apps/bnest-app-e2e/project.json                                           [E] api project target wiring
apps/bnest-app-e2e/README.md                                              [E] document the api project
```

## Specifications and documentation

```text
specs/apps/bnest/app/event-catalog.md                                     [N] as-built event vocabulary
specs/apps/bnest/app/README.md                                            [E] directory map entry
specs/apps/bnest/app/behaviours/learning.feature                          [N] canonical corpus
specs/apps/bnest/app/behaviours/sifat_allah.feature                       [E] route change only
specs/apps/bnest/app/behaviours/README.md                                 [E] directory map entry
specs/apps/bnest/app/architecture.md                                      [E] C4 and constraints
apps/bnest-app/README.md                                                  [E] engine, corpus, API, tasks
apps/bnest-app-e2e/README.md                                              [E] listed above
README.md                                                                 [E] learning targets and commands
plans/backlogs/README.md                                                  [E] index this plan
```

## Prerequisites blocking execution

None outstanding. The four decisions that would otherwise block naming files are settled and recorded: the event log is the single source of truth with projections rebuilt from it ([event model](01-event-model.md)), progress is keyed by learner and mission ([data model](02-data-model.md)), authored content files are a command input rather than an authority ([event model](01-event-model.md)), and Sifat Allah merges into the generic runner rather than keeping a bespoke screen ([UI design](04-ui-design.md)). The one remaining external check — current Absinthe maintenance and compatibility evidence — is a Phase 1 task with a named fallback in [the GraphQL document](03-graphql-api.md#dependency-decision), not an unmade decision hidden in this tree.
