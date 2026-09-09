# Migration Design

Sifat Allah is the engine's first course and its only data migration. This document owns the current state, the target, the conversion contract, and the authority cutover, under the [plan migration convention](../../../../repo-governance/conventions/plan-migrations.md).

## Current state

Two things move: the curriculum, which is code, and each learner's progress, which is data.

**Curriculum.** `apps/bnest-app/lib/bnest_app/sifat_allah.ex` holds a 40-entry `@curriculum` list of `{id, wajib_name, wajib_meaning, mustahil_name, mustahil_meaning}` and a six-value `@question_kinds` list: `wajib_meaning`, `wajib_opposite`, `mustahil_meaning`, `meaning_wajib`, `mustahil_opposite`, `meaning_mustahil`. Questions are addressed by a key of the form `"<pair_id>:<kind>"`, produced by `SifatAllah.key_id/2`. Owner: the repository. Readers: `BnestAppWeb.SifatAllahLive` and the module's own query helpers.

**Progress.** One record per learner.

| Property             | Value                                                                                                                |
| -------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Record type          | `sifat-allah-progress`                                                                                               |
| Record key and owner | The learner's `userId`                                                                                               |
| Locations            | `bnest_records` in SQLite; historical flat path `users/<user-id>/sifat-allah/progress.json`                          |
| Accepted versions    | `2` current, `1` legacy, both accepted by `SifatAllah.restore/1`                                                     |
| Readers and writers  | `BnestAppWeb.SifatAllahLive` only, through `BnestApp.DataRepository`                                                 |
| Payload keys         | `version`, `learned_ids`, `review_ids`, `mastered_key_ids`, `review_key_ids`, `correct_answers`, `incorrect_answers` |
| Owner                | The learner                                                                                                          |
| Disposition          | Retained unchanged through this plan; deletion belongs to a later authorized plan                                    |

Version 1 stored pair-level `learned_ids` and `review_ids`; version 2 stores question-level `mastered_key_ids` and `review_key_ids`. `restore/1` already upgrades version 1 by expanding each pair into its three original question keys. The migration reuses that function rather than reimplementing the upgrade, so there is exactly one definition of what a legacy record means.

## Target

**Curriculum becomes content.** `nx run bnest-app:learning:generate-sifat-allah` expands `@curriculum` into committed corpus files: one `flashcard` introduction mission per pair and one `multiple_choice` mission per pair and question kind. Identifiers are deterministic.

| Source                                | Generated `mission_id`               |
| ------------------------------------- | ------------------------------------ |
| Pair `wujud`, introduction            | `sifat-allah/wujud/kenalan`          |
| Pair `wujud`, kind `wajib_meaning`    | `sifat-allah/wujud/wajib-meaning`    |
| Pair `qidam`, kind `meaning_mustahil` | `sifat-allah/qidam/meaning-mustahil` |

The rule is `sifat-allah/<pair_id>/<kind with underscores replaced by dashes>`, and `kenalan` for the introduction. Forty pairs produce 40 introduction missions and 240 question missions. Topics group pairs as the current dashboard does, and one course, `aqidah-dasar`, orders those topics.

**Progress becomes events.** The migration does not write projection rows. For each learner it appends `progress.imported` events — and a `mission.mastered` event for each mastered key — to that learner's stream, and the ordinary projectors turn them into rows. This is what keeps the recovery story whole: a later rebuild replays the migration exactly like any other history, so migrated learners are not a special case that only exists in a table.

| Source field                           | Appended to the learner's stream                                                                                                                                                            |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `mastered_key_ids` entry               | `progress.imported` with `state = "mastered"`, followed by the projector setting `mastered_at`, `review_step = 0`, and `next_review_at` one day later                                       |
| `review_key_ids` entry                 | `progress.imported` with `state = "answered"` and `correct_streak = 0`                                                                                                                      |
| `learned_ids` (version 1 only)         | Expanded by `SifatAllah.restore/1` into the same key space before conversion                                                                                                                |
| `correct_answers`, `incorrect_answers` | Carried on the first `progress.imported` event for that learner as aggregate counters; not distributed per mission, because the source never recorded which mission each answer belonged to |

Each imported event carries `source_version`, so the log records whether a fact came from a version 1 or version 2 record rather than hiding the difference.

Three conversion decisions are deliberate and stated rather than inferred. First, `occurred_at` on an imported event is the migration time, not a fabricated historical time, because the source never recorded when mastery happened; `recorded_at` matches it and the honesty is visible in the log. Second, per-mission `attempt_count` and `correct_count` start at zero for migrated missions, because inventing attempt histories that never existed would put fiction into the record of truth. Third, no `coins.earned` event is appended for migrated mastery.

**Migrated mastery earns no coins.** The ledger starts empty. Coins are credited only for mastery achieved through the engine after cutover. Crediting roughly 240 missions of historical mastery would hand each child a large balance before any reward exists to spend it on, devaluing the mechanic on its first day. The alternative — a one-off migration bonus — is a product decision that belongs with the redemption plan that will define what a coin is worth, not with a data migration.

## Transition

### Expand

The event log, its projections, the content sync, the engine, the API, and the runner ship while `SifatAllahLive` and the `sifat-allah-progress` record type continue to serve. Nothing reads learning progress in production yet. The schema migration is additive, so the previous revision runs unchanged against the same database and both revisions can serve during a rolling release.

### Migrate

`mix bnest.learning.migrate_sifat_allah` runs headlessly and idempotently:

1. Inventory every `sifat-allah-progress` record in deterministic key order, recording a checksum of each immutable source payload without copying any value into logs or evidence.
2. Restore each payload through `SifatAllah.restore/1`, so version 1 and version 2 are handled by the existing accepted definition.
3. Convert each restored key to its `mission_id` and append the learner's imported events in one transaction, at the learner stream's expected version. A re-run finds the learner already has imported events and appends nothing, so idempotence comes from the log rather than from an upsert.
4. Record each learner's outcome as `accepted`, `unsupported`, `invalid`, `changed`, or `failed`. A malformed or unknown-version record is preserved opaquely and reported for retry; it is never coerced or discarded.
5. Leave the source record byte-identical.

A second run appends no event and changes no projected row, because a learner whose stream already contains `progress.imported` events is skipped.

### Verify

Verification has three parts, and counts alone are explicitly insufficient.

1. **Per-learner equivalence.** For each learner, the set of missions projected as `mastered` equals the mission set derived from `mastered_key_ids`, and the `answered` set equals the one derived from `review_key_ids`. Set equality, not cardinality.

2. **Rebuild equivalence.** Dropping every projection and replaying the whole log, including the imported events, reproduces byte-identical projections. A migration that only writes rows would pass the equivalence check above and still leave the log unable to rebuild the migrated state; this check is what catches that.
3. **Fresh-process authority.** A new BEAM process starts against an isolated fixture with the `sifat-allah-progress` source removed, and a synthetic `test-user-` learner opens the course, answers a question, masters a mission, earns a coin, and sees the review queue — through the routed product journey, not through an adapter call. The engine must fail closed if a learning row is missing, never fall back to the retired source.
4. **Corpus parity.** The existing `sifat_allah.feature` corpus passes against the generic runner before the route is cut over. This is the acceptance bar for replacing the bespoke screen and is tracked as AC-10.

### Contract

After verification, `/apps/sifat-allah` redirects to the engine route, `BnestAppWeb.SifatAllahLive` and `BnestApp.SifatAllah` are removed, and the `sifat_allah` entry stays in `BnestApp.Storage.RecordMap` so existing records remain readable and restorable. That reader is retained for at least one full release cycle after cutover. Deleting the records is destructive contraction and requires its own authorized plan.

## Rollback and boundaries

**Reader and writer behaviour on rollback.** Rolling back to the previous revision restores `SifatAllahLive`, which reads the untouched `sifat-allah-progress` records. Progress recorded through the engine between cutover and rollback would not appear there, so the rollback window is bounded to the drain plus verification period and the trigger is a routed failure, not a slow decision.

**Mixed-version boundary.** Both revisions may serve during the drain. The previous revision never reads a learning table; the new revision never writes `sifat-allah-progress`. A learner who reconnects to the old slot mid-drain sees the old screen with their pre-migration state, which is consistent rather than corrupt.

**Retry behaviour.** The migration is resumable by identity. A failed learner is retried without touching accepted learners, and a `changed` source blocks the cutover rather than being overwritten.

**Recovery source.** The immutable source records and their checksums are the recovery evidence; the storage layer's existing backup and restore path covers the database itself. Restoring the pre-migration state means restoring the database and running the previous revision, both of which are already exercised by the storage plan's rehearsal.

**Manual verification.** Before completion, a maintainer opens the engine route at the exact served origin with a synthetic identity on desktop, tablet, and mobile, completes one mission of each kind, and confirms the trail, coin, and review behaviour. Recorded as route, state, viewport, and pass or fail, with no private values.
