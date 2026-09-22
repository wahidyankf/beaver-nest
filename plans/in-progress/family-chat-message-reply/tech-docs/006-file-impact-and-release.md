# File Impact, Documentation, and Release

`[E]` updated · `[N]` new · `[M]` moved · `[D]` deleted. Paths are exact and repository-relative. A path discovered
during execution that is not listed here is recorded as a File Impact deviation in `learnings.md` rather than added
silently.

## Backend

| Status | Path                                                                                          | Change                                                                                  |
| ------ | --------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `[N]`  | `apps/bnest-app/priv/sqlite_repo/migrations/20260922000000_add_family_chat_message_reply.exs` | Additive column and partial index; reversal refuses once replies exist                  |
| `[E]`  | `apps/bnest-app/lib/bnest_app/family_chat/store.ex`                                           | `@message_columns` gains the column; insert accepts it; new batch quote lookup          |
| `[E]`  | `apps/bnest-app/lib/bnest_app/family_chat.ex`                                                 | Target validation, quote attachment for pages and single messages, preview truncation   |
| `[E]`  | `apps/bnest-app/lib/bnest_app/family_chat/message.ex`                                         | `normalize_reply_to_message_id/1` beside the existing body and client-ID rules          |
| `[E]`  | `apps/bnest-app/lib/bnest_app_web/schema/types/family_chat_types.ex`                          | `:family_chat_message_quote` object and the `replyTo` field with its live-name resolver |
| `[E]`  | `apps/bnest-app/lib/bnest_app_web/schema.ex`                                                  | `replyToMessageId` argument on the mutation                                             |
| `[E]`  | `apps/bnest-app/lib/bnest_app_web/resolvers/family_chat_resolver.ex`                          | Pass the argument through; no lookup, no parsing, no truncation                         |
| `[E]`  | `apps/bnest-app/lib/bnest_app_web/controllers/family_chat_controller.ex`                      | Expose the reply flag to the template                                                   |
| `[E]`  | `apps/bnest-app/config/runtime.exs`                                                           | Read `BNEST_FAMILY_CHAT_REPLY_ENABLED` beside the existing family-chat flag             |

## Frontend

| Status | Path                                                                           | Change                                                                          |
| ------ | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| `[N]`  | `apps/bnest-app/assets/js/family_chat/message_actions.js`                      | The action menu: four triggers, two items, focus contract                       |
| `[N]`  | `apps/bnest-app/assets/js/family_chat/reply_target.js`                         | Reply-target state shared by the composer, the menu, and the outbox             |
| `[N]`  | `apps/bnest-app/assets/js/family_chat/jump_to_message.js`                      | Bounded jump, highlight, and the refusal announcement                           |
| `[E]`  | `apps/bnest-app/assets/js/family_chat/operations.js`                           | `messageFields({replies})`, the quote fragment, the new mutation argument       |
| `[E]`  | `apps/bnest-app/assets/js/family_chat/message_render.js`                       | Quote card rendering, roving tabindex, highlight class                          |
| `[E]`  | `apps/bnest-app/assets/js/family_chat/composer.js`                             | Carry the reply target into `submit()` and clear it on success only             |
| `[E]`  | `apps/bnest-app/assets/js/family_chat/outbox.js`                               | Queue record carries `replyToMessageId`                                         |
| `[E]`  | `apps/bnest-app/assets/js/family_chat/outbox_send.js`                          | Send the argument; treat its rejection as the existing non-retryable path       |
| `[E]`  | `apps/bnest-app/assets/js/family_chat/outbox_namespace.js`                     | Queued-message typedef                                                          |
| `[E]`  | `apps/bnest-app/assets/js/family_chat/persistence_indexeddb.js`                | Persist and hydrate the field; `DB_VERSION` deliberately unchanged              |
| `[E]`  | `apps/bnest-app/assets/js/family_chat/real_store.js`                           | Expose rendered-node lookup for the jump                                        |
| `[E]`  | `apps/bnest-app/assets/js/family_chat/real_store_render.js`                    | Render quotes on every window path                                              |
| `[E]`  | `apps/bnest-app/assets/js/family_chat/history.js`                              | Bounded older-page loading on behalf of a jump                                  |
| `[E]`  | `apps/bnest-app/assets/js/family_chat/elements.js`                             | Handles for the menu host and the reply strip                                   |
| `[E]`  | `apps/bnest-app/assets/js/family_chat/mount_browser.js`                        | Bind the four triggers and the quote activation                                 |
| `[E]`  | `apps/bnest-app/assets/js/family_chat/mount_browser_composer.js`               | Bind the strip, its cancel control, and Escape                                  |
| `[E]`  | `apps/bnest-app/assets/js/family_chat/accessibility.js`                        | Extend the keyboard-reachability proxy to the roving contract                   |
| `[E]`  | `apps/bnest-app/lib/bnest_app_web/controllers/family_chat_html/room.html.heex` | Menu host element, reply strip markup, reply-enabled data attribute             |
| `[E]`  | `apps/bnest-app/assets/css/app.css`                                            | Quote card, menu, sheet, strip, highlight, reduced-motion, coarse-pointer rules |

### A split this plan should expect

Every module under `assets/js/family_chat/` carries a header comment saying it was split out of a larger file to keep
each one small, and several of the files this plan touches — `message_render.js`, `real_store_render.js`, and
`real_store.js` — are already near the size that prompted the last split. Quote rendering and roving focus both land
in exactly those files.

No lint rule currently enforces a line ceiling in this repository, so nothing will fail; the convention is upheld by
the authors, not by a gate. Execution should therefore expect to create one or two further modules rather than let
these three grow, and must record each new path as a File Impact deviation in `learnings.md` with the reason. The
split is predicted here so that it reads as a planned consequence rather than as unplanned drift.

## Tests

**Corrected 2026-09-22.** The table below was rewritten after execution against `git diff` over the plan's own
commits. The original listed thirteen files; the plan touched forty-five. Three kinds of error produced the gap: the
Vitest+Gherkin adapter layer was not represented at all, the fe-e2e support files a new scenario needs were not
foreseen, and one row named a file (`family-chat-composer.ts`) that in the end was never changed. Each individual
surprise was recorded as a File Impact deviation in `learnings.md` while it happened; this is the reconciled list.

### Backend

| Status | Path                                                                           | Change                                                                        |
| ------ | ------------------------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| `[E]`  | `apps/bnest-app/test/unit/bnest_app/family_chat_test.exs`                      | Validation, quote attachment, preview truncation, idempotent replay           |
| `[E]`  | `apps/bnest-app/test/unit/bnest_app/family_chat/message_test.exs`              | Reply-target normalization                                                    |
| `[E]`  | `apps/bnest-app/test/unit/bnest_app_web/schema_test.exs`                       | Schema shape and the unchanged resolver dependency direction                  |
| `[N]`  | `apps/bnest-app/test/unit/bnest_app/backup_restore_test.exs`                   | Restore evidence scoped to the active room — a production fix this plan found |
| `[E]`  | `apps/bnest-app/test/unit/support/family_chat_driver.ex`                       | Reply-aware driver for the unit layer                                         |
| `[E]`  | `apps/bnest-app/test/unit/support/home_page_driver.ex`                         | Entry-point assertions under the reply flag                                   |
| `[E]`  | `apps/bnest-app/test/integration/bnest_app/family_chat_migration_test.exs`     | Additive migration, idempotent re-run, refused reversal                       |
| `[E]`  | `apps/bnest-app/test/integration/bnest_app/sqlite_storage_test.exs`            | Storage round trip carrying the new column                                    |
| `[N]`  | `apps/bnest-app/test/integration/bnest_app_web/family_chat_graphql_test.exs`   | Endpoint, router, session/CSRF, and `Absinthe.Plug` in process                |
| `[N]`  | `apps/bnest-app/test/integration/bnest_app_web/family_chat_room_page_test.exs` | The rendered room page under both flag postures                               |
| `[E]`  | `apps/bnest-app/test/integration/support/family_chat_driver.ex`                | Reply-aware driver for the integration layer                                  |
| `[E]`  | `apps/bnest-app/test/behaviour/steps/family_chat_backend_steps.exs`            | Bindings for the new backend scenarios                                        |

**The boundary tests run in process, not against a loopback listener.** The plan asked for "a loopback listener the
test starts, owns, and stops". [API testing](../../../../repo-governance/development/api-testing.md) permits either,
and the rest of this suite is in process. `family_chat_graphql_test.exs` drives the genuine endpoint, router,
session and CSRF plugs, and `Absinthe.Plug`, asserting status, content type, variable coercion, and the
`data`/`errors` envelope. Binding a second listener beside a 24/7 service buys nothing that `bnest-app-be-e2e`
does not already prove at the real socket.

### Frontend unit

| Status | Path                                                                  | Change                                                                      |
| ------ | --------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `[E]`  | `apps/bnest-app/assets/test/unit/family_chat/composer.test.ts`        | Reply-target lifecycle in the composer                                      |
| `[E]`  | `apps/bnest-app/assets/test/unit/family_chat/outbox.test.ts`          | Queue, persist, hydrate, and drain a reply; legacy record without the field |
| `[E]`  | `apps/bnest-app/assets/test/unit/family_chat/history.test.ts`         | Bounded older-page loading and the refusal                                  |
| `[E]`  | `apps/bnest-app/assets/test/unit/family_chat/reconnect.test.ts`       | Catch-up drain beside the offline flag                                      |
| `[N]`  | `apps/bnest-app/assets/test/unit/family_chat/message_actions.test.ts` | Trigger, focus, disabled-Reply, and copy decisions without a browser        |
| `[N]`  | `apps/bnest-app/assets/test/unit/family_chat/reply_target.test.ts`    | Target selection and the bounded preview by grapheme                        |
| `[N]`  | `apps/bnest-app/assets/test/unit/family_chat/message_quote.test.ts`   | Quote-card rendering and its accessible name                                |
| `[N]`  | `apps/bnest-app/assets/test/unit/family_chat/menu_anchor.test.ts`     | Menu placement and dismissal decisions                                      |
| `[N]`  | `apps/bnest-app/assets/test/unit/family_chat/roving_focus.test.ts`    | The roving tab-stop invariant                                               |
| `[N]`  | `apps/bnest-app/assets/test/unit/family_chat/operations.test.ts`      | One field set shared by query, mutation, and subscription                   |
| `[N]`  | `apps/bnest-app/assets/test/unit/family_chat/accessibility.test.ts`   | The rendered-list invariant under `happy-dom`                               |
| `[M]`  | `apps/bnest-app/assets/test/support/fake_clock.ts`                    | Moved out of `unit/family_chat/` once a second layer needed it              |

`accessibility.test.ts` is why `happy-dom` entered the dependency tree. Its predecessor read the shipped template as
text and looked for words suggesting keyboard reachability, which is not a property a template rendering an empty
`<ol>` can have. The replacement renders real messages through the shipped renderer, so breaking the roving reset
fails it.

### Vitest and Gherkin adapter

The plan did not name this layer. It is not optional: `BnestApp.Behaviour.FeVitestUnitScope` prunes every
`@fe-vitest-unit` scenario from the Elixir corpus and `verify.ts` then requires **exactly** that complementary set,
so every new frontend scenario needs a binding here, including ones whose real proof is a browser.

| Status | Path                                                              | Change                                                                |
| ------ | ----------------------------------------------------------------- | --------------------------------------------------------------------- |
| `[E]`  | `apps/bnest-app/assets/test/behaviour/family_chat.steps.ts`       | Existing bindings under the reply flag                                |
| `[N]`  | `apps/bnest-app/assets/test/behaviour/family_chat_reply.steps.ts` | Reply bindings for the document-free and document-bearing rooms alike |
| `[N]`  | `apps/bnest-app/assets/test/behaviour/support/reply_room.ts`      | A room built from production pieces under `happy-dom`                 |
| `[E]`  | `apps/bnest-app/assets/test/behaviour/verify.ts`                  | Teardown that takes `document` off `globalThis`                       |

`reply_room.ts` exists because `family_chat.steps.ts` opens the real `initRoom` in Node, where
`typeof document === "undefined"` selects the in-memory store, transport, and page source — the wrong branch for
scenarios about markup, focus, and key events. The hazard is the seam: a `document` left on `globalThis` silently
flips every _following_ document-free scenario onto the browser branch, so it is taken down in `verify.ts`'s
`finally` and again inside the builder when a room fails to build half-way.

### Browser and API end-to-end

| Status | Path                                                                         | Change                                          |
| ------ | ---------------------------------------------------------------------------- | ----------------------------------------------- |
| `[E]`  | `apps/bnest-app-be-e2e/tests/steps/family-chat.steps.ts`                     | GraphQL reply bindings                          |
| `[N]`  | `apps/bnest-app-be-e2e/tests/steps/family-chat-reply.steps.ts`               | Reply-specific API bindings                     |
| `[N]`  | `apps/bnest-app-be-e2e/tests/support/family-chat-state.ts`                   | Seeded reply state for the API layer            |
| `[E]`  | `apps/bnest-app-fe-e2e/tests/steps/family-chat.steps.ts`                     | Existing bindings under the reply flag          |
| `[N]`  | `apps/bnest-app-fe-e2e/tests/steps/family-chat-reply.steps.ts`               | Menu, strip, quote, and jump                    |
| `[N]`  | `apps/bnest-app-fe-e2e/tests/steps/family-chat-reply-reading.steps.ts`       | Reading a conversation that contains replies    |
| `[N]`  | `apps/bnest-app-fe-e2e/tests/steps/family-chat-reply-keyboard.steps.ts`      | The keyboard path through menu, strip, and card |
| `[E]`  | `apps/bnest-app-fe-e2e/tests/steps/family-chat-offline-persistence.steps.ts` | An offline reply that keeps its target          |
| `[E]`  | `apps/bnest-app-fe-e2e/tests/steps/family-chat-resume.steps.ts`              | Resume with replies present                     |
| `[E]`  | `apps/bnest-app-fe-e2e/tests/steps/experience-release.steps.ts`              | The two-stage release scenarios                 |
| `[N]`  | `apps/bnest-app-fe-e2e/tests/support/family-chat-reply.ts`                   | Reply-specific page helpers                     |
| `[N]`  | `apps/bnest-app-fe-e2e/tests/support/family-chat-reply-room.ts`              | Reply-aware room helper                         |
| `[N]`  | `apps/bnest-app-fe-e2e/tests/support/family-chat-gestures.ts`                | Pointer and keyboard gestures the menu needs    |
| `[E]`  | `apps/bnest-app-fe-e2e/tests/support/family-chat.ts`                         | Shared room helper                              |
| `[E]`  | `apps/bnest-app-fe-e2e/tests/support/candidate-pool.ts`                      | Candidate slots for the release scenarios       |
| `[E]`  | `apps/bnest-app-fe-e2e/tests/support/routed-rollout.ts`                      | Routed-rollout helper under both flag postures  |
| `[E]`  | `apps/bnest-app-fe-e2e/tests/support/storage-authority.ts`                   | Storage authority for reply-bearing runs        |

## Specifications

Specifications are updated **before** implementation, in the same change, under
[specification maintenance](../../../../repo-governance/development/specification-maintenance.md).

| Status | Path                                                                | Change                                                                                                         |
| ------ | ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `[E]`  | `specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature`    | New `Rule` for the quote field, the mutation argument, and target validation                                   |
| `[E]`  | `specs/apps/bnest/app-be/behaviours/family_chat_operations.feature` | New `Rule` for storage, idempotent replay with a differing target, and unchanged push bookkeeping              |
| `[E]`  | `specs/apps/bnest/app-fe/behaviours/family_chat.feature`            | New `Rule`s for the menu, the strip, quote rendering, the bounded jump, offline replies, and the keyboard path |
| `[E]`  | `specs/apps/bnest/app-be/architecture.md`                           | Component view prose: the mutation argument and the quote field; constraints: read-time quote resolution       |
| `[E]`  | `specs/apps/bnest/app-fe/architecture.md`                           | Component view prose: the three new browser modules and the reply flag; two new constraints                    |

Neither architecture document's **Container View** changes, and neither **Behaviour Traceability** section does.
[Specification Changes](005-specification-changes.md) owns the reason for each and records both as deliberately
unchanged; this table names only what is edited, so the two documents agree.

No new `.feature` file is created. The reply behaviours are Rules inside the three existing family-chat features,
which keeps one feature per boundary per capability and leaves the two `behaviours/README.md` directory maps
untouched. If execution finds a Rule that genuinely does not belong in any of the three, adding a file also means
updating that directory's map in the same change.

## Documentation

| Status | Path                                    | Change                                                                                 |
| ------ | --------------------------------------- | -------------------------------------------------------------------------------------- |
| `[E]`  | `README.md`                             | Capability summary gains quoted replies and the new flag's default                     |
| `[E]`  | `apps/bnest-app/README.md`              | Family-chat section: the column, the GraphQL delta, the flag, the three new modules    |
| `[E]`  | `apps/bnest-app-be-e2e/README.md`       | The flag's required value for backend reply coverage                                   |
| `[E]`  | `apps/bnest-app-fe-e2e/README.md`       | The new reply step and support files, and the flag the browser suite needs             |
| `[E]`  | `docs/how-to-guides/releasing-bnest.md` | `BNEST_FAMILY_CHAT_REPLY_ENABLED` alongside the existing flag in the release procedure |
| `[E]`  | `docs/reference/glossary.md`            | `quoted reply`, `reply target`, and `quote preview` as defined terms                   |

Diátaxis placement is deliberate: the release procedure is a how-to, the vocabulary is reference, and neither gains a
tutorial or an explanation page, because this feature introduces no concept a family member has to learn separately
from using it.

## Configuration

| Variable                          | Values         | Default | Meaning                                                            |
| --------------------------------- | -------------- | ------- | ------------------------------------------------------------------ |
| `BNEST_FAMILY_CHAT_REPLY_ENABLED` | `true`/`false` | `false` | Gates the requested GraphQL fields, the action menu, and the strip |

The flag is read at boot, like `BNEST_FAMILY_CHAT_ENABLED`, and a slot that is missing it fails to boot rather than
guessing. With the flag off, the server still **accepts** `replyToMessageId` and still **serves** `replyTo`; only the
browser stops asking. That asymmetry is what the compatibility release depends on.

**Corrected 2026-09-22 — a flag needs the files that carry it, not only the files that read it.** The tables above
listed every file the _feature_ touches and none of the files the _release_ touches. A variable read at boot is
supplied by the managed process, so introducing one means editing the release path as well:

| Status | Path                                    | Change                                                             |
| ------ | --------------------------------------- | ------------------------------------------------------------------ |
| `[E]`  | `apps/bnest-app/tools/deployment.mjs`   | Passes `BNEST_FAMILY_CHAT_REPLY_ENABLED` into a slot's environment |
| `[E]`  | `apps/bnest-app/tools/release.mjs`      | Carries the flag through the two release stages                    |
| `[E]`  | `apps/bnest-app/tools/release.test.mjs` | Pins that a promoted slot receives it                              |

Without those, the experience stage would have promoted a revision that reads the flag and is never given it, and
`/health/ready` could not have told anyone: the room sits behind `:authenticated_browser`, so a healthy slot and a
correctly configured slot are not the same claim. The general rule — that a plan introducing a runtime flag must
cover the release path in its File Impact — is raised for the repository's own conventions in
`plans/ideas/q2-not-urgent-important/plan-and-checkpoint-contract-gaps.md`.

Retiring the flag after the rollback window is out of scope and is recorded as a follow-up idea brief, not left as an
unowned line in this plan.

## Release

Bnest is a 24/7 service. The change reaches production in the same two stages the room itself used, for the same
reason.

### Why two stages

The browser bundle is served by the application. During any promotion there is a window in which a browser holding
one revision's bundle talks to another revision's server. Of the two directions, only one is dangerous:

- an **old bundle** against a **new server** is safe — it never asks for `replyTo`;
- a **new bundle** against an **old server** is fatal — GraphQL rejects the whole document with
  `Cannot query field "replyTo"`, and the room does not load at all.

So the field must exist everywhere before any bundle asks for it.

| Stage                      | Contents                                                                                       | Proof before proceeding                                                                                                    |
| -------------------------- | ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| DU-2 compatibility release | Migration, store, context, schema, resolver, and the full browser bundle with the flag **off** | Routed revision healthy; the room loads for a pre-change browser; `replyTo` answerable by `curl`; 12-sample responsiveness |
| DU-3 experience release    | The **same reviewed revision**, released with the flag **on**                                  | Menu, strip, quote, and jump work at the routed origin; replies commit; 12-sample responsiveness                           |

The rollback floor for DU-3 is DU-2's revision, which can serve both bundles. The rollback floor for DU-2 is the
current production revision, which cannot see the new column and does not need to.

### Continuity requirements

- Caddy reload closes prior-slot sockets; clients reconnect and catch up through the existing subscribe-then-query
  path. **No page refresh may be required**, and the drain window is bounded rather than open-ended.
- The prior slot stays warm for the five-minute proof window and is then retired.
- Responsiveness at the exact routed origin is sampled 12 times at preflight, after each promotion, and after drain:
  p95 ≤ 500 ms, every sample ≤ 2 s, zero failures. A 2xx status alone is not responsiveness proof.
- **Rollback trigger.** Any of: a failed readiness sample, p95 above 500 ms, any sample above 2 s, a GraphQL document
  rejection observed at the routed origin, or a room that fails to load for either bundle. The response is a managed
  Caddy rollback to the floor above, not a fix-forward attempt.
- The sole backend is never stopped, Tailscale is never repointed, and no candidate, watcher, or temporary proxy
  outlives the release.

### Backup, capacity, and restore

One additive integer column on a table whose rows are already the dominant content. No new table, no new index on a
hot write path, and no measurable change to the database's growth rate or to backup duration. The existing whole-
database daily backup covers it with no change; no chat-only backup is created. Restore proof is the existing drill,
extended by one assertion: a restored database's replies still resolve their quotes.
