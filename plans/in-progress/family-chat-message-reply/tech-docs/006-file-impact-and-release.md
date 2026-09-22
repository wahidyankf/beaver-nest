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

| Status | Path                                                                       | Change                                                                      |
| ------ | -------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `[E]`  | `apps/bnest-app/test/unit/bnest_app/family_chat_test.exs`                  | Validation, quote attachment, preview truncation, idempotent replay         |
| `[E]`  | `apps/bnest-app/test/unit/bnest_app/family_chat/message_test.exs`          | Reply-target normalization                                                  |
| `[E]`  | `apps/bnest-app/test/unit/bnest_app_web/schema_test.exs`                   | Schema shape and the unchanged resolver dependency direction                |
| `[E]`  | `apps/bnest-app/test/integration/bnest_app/family_chat_migration_test.exs` | Additive migration, idempotent re-run, refused reversal                     |
| `[E]`  | `apps/bnest-app/test/behaviour/steps/family_chat_backend_steps.exs`        | Bindings for the new backend scenarios                                      |
| `[E]`  | `apps/bnest-app/assets/test/unit/family_chat/composer.test.ts`             | Reply-target lifecycle in the composer                                      |
| `[E]`  | `apps/bnest-app/assets/test/unit/family_chat/outbox.test.ts`               | Queue, persist, hydrate, and drain a reply; legacy record without the field |
| `[E]`  | `apps/bnest-app/assets/test/unit/family_chat/history.test.ts`              | Bounded older-page loading and the refusal                                  |
| `[N]`  | `apps/bnest-app/assets/test/unit/family_chat/message_actions.test.ts`      | Trigger, focus, disabled-Reply, and copy decisions without a browser        |
| `[E]`  | `apps/bnest-app-be-e2e/tests/steps/family-chat.steps.ts`                   | GraphQL reply bindings                                                      |
| `[N]`  | `apps/bnest-app-fe-e2e/tests/steps/family-chat-reply.steps.ts`             | Browser bindings for menu, strip, quote, and jump                           |
| `[N]`  | `apps/bnest-app-fe-e2e/tests/support/family-chat-reply.ts`                 | Reply-specific page helpers                                                 |
| `[E]`  | `apps/bnest-app-fe-e2e/tests/support/family-chat-composer.ts`              | Strip-aware composer helper                                                 |

## Specifications

Specifications are updated **before** implementation, in the same change, under
[specification maintenance](../../../../repo-governance/development/specification-maintenance.md).

| Status | Path                                                                | Change                                                                                                         |
| ------ | ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `[E]`  | `specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature`    | New `Rule` for the quote field, the mutation argument, and target validation                                   |
| `[E]`  | `specs/apps/bnest/app-be/behaviours/family_chat_operations.feature` | New `Rule` for storage, idempotent replay with a differing target, and unchanged push bookkeeping              |
| `[E]`  | `specs/apps/bnest/app-fe/behaviours/family_chat.feature`            | New `Rule`s for the menu, the strip, quote rendering, the bounded jump, offline replies, and the keyboard path |
| `[E]`  | `specs/apps/bnest/app-be/architecture.md`                           | Component view: the quote resolution step; container view: the new column; behaviour traceability rows         |
| `[E]`  | `specs/apps/bnest/app-fe/architecture.md`                           | Component view: the three new browser modules and the reply flag; behaviour traceability rows                  |

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
