# Learnings

Two kinds of entry live here. **Decision records** are written during planning and are final once the plan is in
backlog. **Execution entries** are appended while `delivery.md` is worked through, and every one of them is resolved
to exactly one durable owner — or discarded with a reason — before this plan is archived.

## Pre-Write Decision Gate — 2026-09-22

Run before any plan document was authored. Eight material branches were presented as mutually exclusive options with
exactly one recommendation each, and all eight were resolved. Six selections matched the recommendation; one did not,
and that is recorded below as it happened.

### D1 — Storage shape: reference, not snapshot

**Selected:** a single nullable `reply_to_message_id` foreign key.

**Alternatives rejected:** copying the quoted body and sender onto the reply at send time (the WhatsApp and Signal
shape); a hybrid keeping both the key and a cached preview column.

**Why.** The snapshot exists in those products because an end-to-end encrypted, multi-device protocol has no
server-side plaintext to join against. Bnest is centralized and has exactly one authority. Two repository facts made
the decision rather than the precedent: `family_chat_messages` carries `BEFORE UPDATE` and `BEFORE DELETE` triggers
that abort every mutation, so a referenced row can never change or vanish; and `sender_display_name` is already
deliberately re-resolved at read time, so a copied quote name would have reintroduced the exact staleness that
resolution was added to remove. Comparative research confirmed the alignment: Discord, Telegram, and Slack — all
centralized — all use references, and Discord's API documents the deleted-original case as an explicit null rather
than as stale copied text.

**Consequence carried forward:** the immutability triggers are now load-bearing for a second feature. That obligation
is stated in [Data Model](tech-docs/001-data-model-and-migration.md) so a future plan that relaxes them finds it.

### D2 — Jump to original: bounded auto-load

**Selected:** scroll and highlight if the target is loaded; otherwise load at most five older pages, then state that
the message is too far back.

**Alternatives rejected:** a display-only quote that cannot be activated; a new `aroundId` pagination argument
returning a window centred on the target.

**Why.** A display-only quote drops half the value of the feature. An `aroundId` window would introduce a second
pagination contract that has to reconcile with the scroll anchor, the unread divider, and `hasNewer` — three
mechanisms the previous plan built and proved — for a case a bounded walk already covers. Signal's own issue tracker
records a quote pointing beyond the pagination boundary rendering as "Quoted message not found", which is the
outcome the stated refusal copy exists to replace.

### D3 — Invoke gestures: one menu, four triggers

**Selected:** 500 ms hold on touch, `contextmenu` on pointer devices, a hover- or focus-revealed `⋯` control, and
Enter on the focused message — all opening the same menu.

**Alternatives rejected:** adding swipe-to-reply; long-press alone.

**Why.** Long-press alone has no path for a desktop browser without a touchscreen and no path for a keyboard. Swipe
was declined for v1 on evidence rather than taste: it is a path-based gesture under WCAG 2.5.1 and would need an
alternative regardless, and Discord's swipe-to-reply rollout collided with its existing swipe-to-navigate gesture and
drew sustained complaints from users who could not turn it off. It is raised as a follow-up idea brief instead.

**Correction recorded.** The gate framed long-press-only as failing both WCAG 2.5.1 and 2.1.1. Research showed that
is wrong on the first: W3C treats long-press as an acceptable single-pointer alternative, and 2.5.1 targets
path-based gestures such as swipe. The real failure of a long-press-only design is 2.1.1 Keyboard. The decision is
unchanged; its justification is one criterion, not two. This is recorded because a wrong reason in a plan outlives
the conversation that produced it.

### D4 — Reply targets: committed messages only

**Selected:** Reply is unavailable on a message that has not committed; replies themselves can still be queued
offline.

**Alternatives rejected:** allowing a reply to one's own still-pending message; refusing replies entirely while
offline.

**Why.** Allowing a pending target would force the outbox to translate a client message ID into a server ID at drain
time, which gives the queue a dependency ordering it does not have today and creates a new failure mode — an orphaned
reply whose parent failed permanently. Refusing offline replies would give back offline-first behaviour that the
previous plan paid for. The chosen rule is one sentence, needs no queue ordering, and leaves records written before
this change valid as they are.

### D5 — Menu contents: Reply and Copy text

**Selected:** two items. **This did not match the recommendation**, which was Reply alone on minimal-sufficiency
grounds.

**Why the selection stands.** A one-item menu is an odd object, and `Copy text` is genuinely cheap: one Clipboard API
call, one success announcement, one refusal announcement. It also turned out to interact well with D4 — on a message
that cannot be replied to, the menu still has something to offer instead of opening with everything disabled. The
cost accepted is one more scenario at two layers and one more refusal path to prove.

### D6 — Notifications unchanged

**Selected:** a reply produces exactly the notification an ordinary message does.

**Alternatives rejected:** marking a notification when it answers the recipient's own message; including the quoted
text in the payload.

**Why.** A recipient-dependent notification means one commit renders differently per subscription, which changes the
push payload from a property of the message to a property of the delivery row. Including the quoted text would send
a second message's content to a third-party push service, reversing a privacy boundary the previous plan chose
deliberately.

### D7 — Quote payload: server-truncated preview

**Selected:** `replyTo { id senderKind senderDisplayName bodyPreview }`, with `bodyPreview` collapsed to one line and
cut at 160 graphemes on the server.

**Alternatives rejected:** sending the full body and clamping it with CSS; sending only the ID and letting the
browser find the original in memory.

**Why.** A 50-message page of full 4,000-grapheme bodies could carry 200 KB of quote text on the household's weakest
device; the cap bounds it near 8 KB. A CSS clamp is also invisible to a screen reader, which would read all 4,000
characters. Sending only the ID would leave the quote empty exactly when the original is not loaded — the common case
on opening the room.

### D8 — Plan shape: `tech-docs/` with five companions

**Selected:** an entrypoint plus five ordered companions.

**Alternative rejected:** a single `tech-docs.md`; writing an idea brief first.

**Why.** The technical design spans a migration, a GraphQL contract, twelve embedded assets, an interaction and
accessibility contract, and a two-stage release. In one file the migration reader would scroll past twelve mockups.
An idea brief was declined because the request was explicitly for a backlog plan and the eight decisions above were
already resolved.

### Branches closed without a question

These were material enough to name and were closed from repository evidence rather than by asking:

- **Deleted or edited originals.** Not applicable. Both are blocked by database trigger, so no tombstone and no
  re-validation path exists. Recorded rather than ignored, with the future obligation written into the data-model
  document.
- **Nesting depth.** Flat, one level, made unrepresentable by a separate GraphQL quote type. Telegram's Bot API and
  Slack's threading rule both enforce flatness explicitly; no product studied nests in the interface.
- **Replying to your own message, and to a system message.** Both allowed, with no special casing. A uniform rule is
  less code than an exception and there is no reason for one.
- **"You" versus a name in the quote.** The quote shows the same live-resolved display name the original bubble
  shows. The room does not say "You" on committed own messages today, so a quote that did would be inconsistent.
- **Reply target persistence.** Not persisted. Drafts are not persisted in this room, and the target is part of a
  draft.
- **Release shape.** Two stages, forced by the direction of the mixed-version risk: an old bundle against a new
  server is safe, a new bundle against an old server is fatal.
- **A new feature file versus new Rules in the existing ones.** Rules in the three existing family-chat features, so
  the two `behaviours/README.md` directory maps stay untouched.
- **IndexedDB version bump.** None. Adding a property to records in an existing key-path store needs no upgrade, and
  a bump would run a migration with nothing to do.

### An existing check this plan must not route around

`assets/js/family_chat/accessibility.js` proves keyboard reachability by asserting that `room.html.heex` contains no
`tabindex="-1"`. Message elements are rendered in JavaScript, so the roving tabindex this plan introduces would be
invisible to that check: it would stay green while the rendered room filled with `tabindex="-1"`. Delivery therefore
extends the check to assert the roving contract on the rendered list. Recorded here because it is a live example of a
structural proxy quietly ceasing to mean what its name says.

## Post-Write Decision Gate — 2026-09-22

Run against the complete draft, separately from the pre-write gate. Three branches became visible only once the plan
existed; all three were resolved and all three matched the recommendation.

### D9 — The keyboard contract is proven at two layers

**Selected:** `FE_UNIT` tests the renderer's invariant, and `FE_E2E` walks the real focus order.

**What the draft revealed.** `assets/js/family_chat/accessibility.js` proves keyboard reachability by reading the
shipped `room.html.heex` and asserting it contains no `tabindex="-1"`. Message elements are created in JavaScript, so
the roving tabindex this plan introduces is entirely invisible to that check: it would have stayed green while the
rendered room filled with `tabindex="-1"`. This was not visible before the interaction design existed, because
nothing before it put focus on a message.

**Alternatives rejected:** extending only the `FE_UNIT` check, which never exercises a focus or layout engine and so
can only ever check a proxy; and deleting the proxy in favour of `FE_E2E` alone, which is honest but gives up the
fast signal that keeps the invariant from regressing between browser runs.

**Why both.** They answer different questions. The unit layer asserts that the renderer maintains exactly one
`tabindex="0"` among the message items — a genuine, cheap, per-commit invariant. The browser layer asserts that Tab
enters once, the arrows move, Enter opens the menu, and Tab leaves once — the thing a member actually experiences.
Either alone is a check that can be green while the room is unusable. Delivery also requires the new unit check to be
broken once on purpose and observed failing, so it is known to be capable of failing.

### D10 — The plan stays whole

**Selected:** keyboard navigation of the message history stays inside this plan.

**What the draft revealed.** The finished plan is larger than the feature sounds — fourteen acceptance criteria and
eleven phases — and the single biggest contributor is roving tabindex, which changes the behaviour of every message
in the room rather than only replies.

**Alternatives rejected:** splitting it into a prerequisite plan landed first; dropping bounded jump-to-original to
shrink the scope instead.

**Why.** Roving tabindex is not an addition to this feature, it is its precondition: without it the action menu has
no keyboard path and AC-FCR-10 cannot pass. Splitting it would mean either releasing reply without a keyboard path,
which contradicts a decision already taken at the pre-write gate, or shipping a prerequisite plan that delivers
nothing a family member can use and doubles the number of production releases from two to four. Dropping the jump was
declined because it reverses D2 and lands on the display-only quote that was explicitly rejected there.

### D11 — The screen-reader wording is authored, not cited

**Selected:** `Reply to {name}: {preview}. Go to that message.` — relationship, then content, then affordance.

**What the draft revealed.** Comparative research established that **no WAI-ARIA or W3C guidance covers announcing a
quoted reply at all**. This is a documented gap, not a search failure. The wording is therefore a design decision the
plan owns, and it cannot be justified by pointing at a specification.

**Alternatives rejected:** a shorter label without the affordance sentence, which depends on a screen reader
announcing the `button` role early enough to be useful and not all of them do; and a longer label carrying the
original's timestamp, which is re-read on every reply while browsing history.

**Why this order.** Content first would make the first thing a listener hears sound like a new message from someone
else. Naming the relationship first is what makes the quote legible before it is read. Because there is no
specification to lean on, delivery proves the wording with a real screen-reader pass and records what was actually
announced, rather than asserting that the label is correct.

## Plan Quality Gate — 2026-09-22 — `PASS`

Run once, at the pre-execution checkpoint, on explicit user direction. One cycle. No stabilization cycle was needed.

### Snapshot

| Field                    | Value                                                                                                                                                                                                                                      |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Plan path and stage      | `plans/backlog/family-chat-message-reply/`, backlog                                                                                                                                                                                        |
| Git revision             | `91e0201df`, branch `family-chat-message-reply` in `worktrees/family-chat-message-reply/`                                                                                                                                                  |
| Dirty paths at freeze    | `plans/backlog/README.md` (modified), `plans/backlog/family-chat-message-reply/` (untracked)                                                                                                                                               |
| Scope                    | Semantic readiness of the six documents, twelve assets, and six technical companions                                                                                                                                                       |
| Governance consulted     | plans convention and its nine modules, plan lifecycle, plan migrations, plan UI design, plan specification changes, API testing, exploratory and usability testing, software quality enforcement, specification maintenance, task tracking |
| Specifications consulted | `app-be/architecture.md`, `app-fe/architecture.md`, and the three family-chat `.feature` files                                                                                                                                             |
| Unresolved decisions     | None. Eleven decisions were resolved across the two planning gates and recorded above.                                                                                                                                                     |
| Cycle                    | 1                                                                                                                                                                                                                                          |

### Ledger

| ID  | Canonical rule                                  | Location                          | Material gap                                                                                                                                                                                                                                                                                                                                          | Repair                                                                                                                                                                      | Proof                                                             | Status  |
| --- | ----------------------------------------------- | --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | ------- |
| Q1  | plan-migrations — data-model visualization      | `tech-docs/001`, ERD              | The ERD named entities and relationships but carried no primary, foreign, or unique keys and no optional cardinality on the self-reference, which the rule requires                                                                                                                                                                                   | Redrew the ERD with each affected entity's keys, and corrected the self-relationship to `\|o--o{` so the optional parent is visible                                         | `mermaid` gate green; keys legible in the diagram                 | `FIXED` |
| Q2  | plan-migrations — field guide                   | `tech-docs/001`, Field Guide      | The guide documented only the new column. The rule requires every column of the affected **resulting** table, with purpose, shape, lifecycle, and key role                                                                                                                                                                                            | Replaced it with a full ten-column guide for `family_chat_messages` as it will exist after the change, including the composite unique constraint                            | Guide present and complete                                        | `FIXED` |
| Q3  | plan-migrations — transition order and evidence | `tech-docs/001`, Transition       | Described only forward and reverse. Missing: the Expand/Migrate/Verify/Contract order, the source inventory with readers and writers, the rollback reader/writer behaviour, retry behaviour, the restore rehearsal, and the compatibility window                                                                                                      | Added a source inventory table and the four named steps, with Migrate recorded as not-applicable **and its reason**, plus rollback, retry, and restore-rehearsal statements | Section present; delivery items already carry the matching proofs | `FIXED` |
| Q4  | exploratory-and-usability-testing               | `delivery.md`, Phase 8            | The two passes were named but not specified: no Playwright MCP driver, no viewport classes, no ordering requirement, no exact `## Exploratory findings` / `## Usability findings` headings, no structural spec-blindness through a fresh delegated context, no cross-reference step, no Iron Rule reconciliation task, and no final verification item | Rewrote both items to the workflow's actual contract and added three items: cross-referencing, Iron Rule reconciliation of spec gaps, and the five-condition verification   | Six Phase 8 items; total delivery items 94 → 100                  | `FIXED` |
| Q5  | software-quality-enforcement — unit coverage    | `delivery.md`, Canonical Commands | The 99% line-coverage threshold carried by `test:unit` was never named, so a new module could land uncovered and the executor would discover the rule only from a red gate                                                                                                                                                                            | Named the threshold where the unit commands are defined, and required the three new browser modules and the migration to arrive covered                                     | Statement present beside the command table                        | `FIXED` |

No row is `OPEN` or `BLOCKED`. No finding was waived.

### What the audit deliberately did not check

Links, directory maps, word budgets, Mermaid syntax, and harness parity are owned by deterministic tooling and were
consumed rather than re-derived. The gate did not simulate any check that `delivery.md` itself delivers.

### Verification

Semantic re-read of the repaired sections and their cross-document effects found no new material gap: the repairs
added contract detail and proof obligations without expanding product scope, and no acceptance criterion, decision, or
file-impact entry changed. Structural invariants re-checked after repair — fourteen acceptance identifiers each
defined once, one hundred delivery items each carrying an executor label, no delivery item citing an undefined
identifier, no acceptance identifier left uncited, archival separated from every substantive phase, six contiguous
companions all listed by the entrypoint, and exactly one technical shape.

```sh
./hippo run --class ephemeral --resource-tier standard --disk-path . -- npm exec -- nx run -p rhino-consumer -t test:repo
```

Passed: `public-safety-tree`, `repo-config`, `word-budget`, `directory-map`, `harness-adapters`, `internal-links`,
`mermaid`.

### Verdict

`PASS`. No row open or blocked, tooling green, no new material semantic gap, and the snapshot changed only through
the recorded repairs above.

This verdict authorizes neither execution nor commit. Both require their own explicit direction.

## Execution Log

Entries are appended dated and sanitized as `delivery.md` is worked through, and every one is resolved to a durable
owner or discarded with a reason before archival.

### 2026-09-22 — Phase 0 preflight

**Checkout and inventory.** `worktrees/family-chat-message-reply/` on branch `family-chat-message-reply`, clean, at
`origin/main` after the plan itself landed there through pull request #80 (rebase merge, three thematic commits,
`Quality gate` green on the exact head and a `pass` leak review posted against that same head). Exactly one live copy
of this plan exists, at `plans/in-progress/family-chat-message-reply/`.

Nx projects: `bnest-app`, `bnest-app-be-e2e`, `bnest-app-fe-e2e`, `rhino-consumer`, `ex-bdd`. Every target this
plan's canonical command table names resolves: `bnest-app` carries `test:unit`, `test:unit:be`, `test:unit:fe`,
`test:integration`, `test:coverage:behaviour`, `test:quick`, `release:test`, and `release:run`; both E2E projects
carry `test:coverage:behaviour` and `test:e2e`; `rhino-consumer` carries `test:repo`. No canonical command names a
target that does not exist.

**SQLite version and the foreign-key pragma.** `exqlite` 0.40.0 through `ecto_sqlite3` 0.24.1, bundling **SQLite
3.53.4**. That is well above the 3.35 floor `ALTER TABLE ... DROP COLUMN` needs, so
[Data Model](tech-docs/001-data-model-and-migration.md)'s reverse path **can** drop the column and does not fall back
to raising. Phase 2 writes the dropping form.

The pragma answer is two-sided, and both sides matter:

| Connection                                | `PRAGMA foreign_keys` |
| ----------------------------------------- | --------------------- |
| A bare `Exqlite` connection, no options   | `0`                   |
| A pooled `BnestApp.SqliteRepo` connection | `1`                   |

`config/config.exs` sets `foreign_keys: :on` for `SqliteRepo`, and a live pooled connection confirms it rather than
the configuration merely claiming it. So the `REFERENCES` clause **is** enforced for application traffic — a second
line of defence, exactly as the data-model document predicted. It is still not the guard: the pragma is
per-connection and SQLite's own default is off, so anything opening its own connection loses it. The same-room
existence check in Elixir remains the first and real guard, and the plan's caveat stands as written.

Probed against an isolated scratch database under ignored `local-tmp/`, removed afterwards. Production storage was
not opened.

**Routed readiness baseline.** Caddy routes `4100` to the green slot on `4001`; the active revision is the
`origin/main` revision that preceded this plan. Twelve samples of the routed readiness endpoint: **zero failures,
p95 248.4 ms, maximum 248.4 ms, minimum 3.1 ms** — inside the p95 ≤ 500 ms and maximum ≤ 2 s budget with room to
spare. `hippo status` reported `state=normal`, `profile=local-constrained`, `concurrency=2`, 97 GiB free. The service
is healthy, so [live-service continuity](../../../repo-governance/development/live-service-continuity.md) does not
stop the work.

**Surprise worth recording.** None of the three preflight facts contradicted the plan, but the pragma result is
sharper than the plan assumed: the plan hedged on whether foreign keys would be enforced at all. They are, for every
connection the application itself uses. That does not relax the validation requirement — it means a bug in the Elixir
check would surface as a constraint violation rather than as a silently dangling reference, which is a better failure
than the one the plan prepared for.

### 2026-09-22 — Phase 1, and a File Impact deviation found by reading the harness

Specifications and both C4 models landed before any product code, as
[Specification Changes](tech-docs/005-specification-changes.md) requires. `REPO` green.

**File Impact deviation — `apps/bnest/assets/test/behaviour/family_chat.steps.ts` `[E]`.**
[File Impact](tech-docs/006-file-impact-and-release.md) lists the frontend unit tests as
`assets/test/unit/family_chat/*.test.ts` and the browser bindings as `bnest-app-fe-e2e/tests/steps/*`. Reading the
harness showed a third binding file the plan never named: `apps/bnest-app/assets/test/behaviour/family_chat.steps.ts`,
the Vitest+Gherkin adapter that binds the `app-fe` feature corpus.

It is not optional. `BnestApp.Behaviour.FeVitestUnitScope` prunes every `@fe-vitest-unit` scenario from the Elixir
corpus, and `assets/test/behaviour/verify.ts` then requires **exactly** that complementary set. So every new frontend
scenario needs a binding there, including the ones whose real proof is a browser — the existing corpus already does
this, binding `A connected client reconnects to the promoted slot without a page refresh` in both harnesses.

The plan's layer table is unaffected and its reasoning still holds: `FE_UNIT` proves the renderer's invariant and
`FE_E2E` proves the real focus order, and those remain **different scenarios**, not one scenario asserted twice. What
changed is only the count of files Phases 5 and 6 touch. Recorded here rather than added silently, per File Impact's
own instruction.

**Durable owner:** the file list in `tech-docs/006-file-impact-and-release.md`, corrected 2026-09-22.

### 2026-09-22 — Phase 2, and the dangling-reference case turning out to be unreachable twice

Migration, normalization, storage, quote resolution, validation, and idempotent replay all landed RED → GREEN →
REFACTOR with the evidence in `delivery.md`.

**The plan's "What Happens If the Original Is Gone Anyway" section is now half wrong, in a good way.**
[Data Model](tech-docs/001-data-model-and-migration.md) reasoned that the state is unreachable because the
`BEFORE DELETE` trigger refuses every delete, and asked for a unit test pinning the read path's silent degradation.
Writing that test surfaced a second guard the plan did not know it had.

The test set the state up the way the plan instructed — by **inserting** a row pointing at an id no message has,
never by deleting. That insert does not succeed. It raises `FOREIGN KEY constraint failed`, because Phase 0
established that `PRAGMA foreign_keys` is on for pooled `SqliteRepo` connections. So the application cannot create a
dangling reference at all, and the trigger never even gets the chance to be the reason.

What is still reachable is a raw connection with the pragma off, which is SQLite's own default — a manual `sqlite3`
repair, or a future migration that opens its own connection. So the degradation is still worth pinning, but not
through a row that cannot exist. Two tests now stand in place of the one the plan asked for:

- the read path is pinned directly on the exact input such a row would produce, a target id no row matches, which
  resolves to no quote rather than raising;
- the refusal itself is pinned, asserting that `insert_message!/7` raises rather than writing a dangling reference.

The second is the more valuable of the two. It means a future change that turns the pragma off — or that adds a
delete feature — breaks a test that says why, instead of silently widening what the schema permits.

**Durable owner:** `tech-docs/001-data-model-and-migration.md`'s dangling-reference section, corrected 2026-09-22 to
state both guards and which one fires first. **Done 2026-09-22.**

**Sequencing note, not a defect.** `delivery.md`'s Phase 2 checkpoint asks for `UNIT` and `INTEGRATION` green, but
Phase 1 deliberately added backend scenarios that stay unbound until Phase 3. Both suites are therefore green on
every test Phase 2 owns and red on exactly 14 behaviour scenarios that are Phase 3's declared RED. Recorded rather
than resolved by re-ordering the work, because the RED is the point; Phase 3's checkpoint is where both suites go
fully green.

**Durable owner:** the plans convention's guidance on checkpoints that span a declared cross-phase RED — raised as an
idea brief at archival if it recurs, discarded if it does not.

## Phase 3 — GraphQL Contract

**A resolver that would have raised on its first real call.** The quote object resolves its sender name through
`FamilyChat.live_sender_display_name/2`, which reads `message.sender_id`. The map `quote_of/1` built carried
`id`, `sender_kind`, `sender_display_name`, and `body_preview` — exactly the four fields the GraphQL type exposes,
and not the one the resolver needed. Every unit test passed, because none of them resolved a quote _through the
schema_; the first thing that would have hit it was a real client. The quote now carries `sender_id` internally,
with no field exposing it, and a unit case drives the seam directly rather than trusting the type.

The general shape is worth keeping: a resolver's input contract is not the type's field list. Matching the two by
eye is how this was missed.

**Durable owner:** `tech-docs/002-graphql-contract.md`, corrected 2026-09-22 — the quote's server-side shape stated
separately from its published fields.

**Three defects in pre-existing code, found by sharing its steps.**

1. `the response returns the original committed message unchanged` asserted only that the returned body _differed_
   from the Given's body — which a fresh commit of a different body also satisfies. Its `Given` never committed
   anything either: it recorded a client message ID and a body and sent neither, so the "retry" that followed was
   the first commit for that ID. The idempotent-send scenario has been passing without exercising idempotency.
   Both drivers now commit in the `Given` and compare the retry against that first commit by server ID _and_ body.

2. Two unit-layer subscription scenarios could not coexist. `Absinthe.Subscription` names its registry
   `Module.concat([pubsub, :Registry])`, so the second `start_link` died starting an already-running
   `BnestAppWeb.Endpoint.Registry` and took the linked test process with it — an exit, not a matchable
   `{:error, {:already_started, _}}`. The helper now checks the registered name with `GenServer.whereis/1` before
   starting anything. It was invisible while only one such scenario existed.

3. `Backup.restore_evidence/1` matched a single `family_chat_rooms` row with `[[...]] =` and read _every_ message
   id regardless of room. The schema has carried `deleted_at` on rooms since the family chat migration, so an
   archived room is a representable state that turned restore into `{:error, :restore_failed}` — found because this
   plan's cross-room refusal case needs a second room to refuse. Evidence is now scoped to the active room and its
   messages, with the single-row match kept: exactly one _active_ room is the invariant worth failing on.

**Durable owner:** the first two belong to `apps/bnest-app`'s test harness and are fixed in place; the third is a
production fix in `BnestApp.Backup`, pinned by `test/unit/bnest_app/backup_restore_test.exs`.

**Quote resolution is room-scoped, and that is not redundant.** `Store.quotes_for/2` now takes the room id and
filters on it. The write-time check in `message_by_id/2` guards the rows this application writes; the read-time
scope guards what a reader is shown, so a row written any other way can never surface another room's text inside
this room's page. The scope also made the previously unreachable degradation path reachable and therefore genuinely
covered: a message whose target exists but is in another room renders as an ordinary message, and a test pins it.

**Durable owner:** `tech-docs/001-data-model-and-migration.md` and `tech-docs/002-graphql-contract.md`, corrected 2026-09-22.

**Deviation — the boundary tests run in process.** `delivery.md` asked for "a loopback listener the test starts,
owns, and stops". `repo-governance/development/api-testing.md` permits either that or in-process, and the rest of
this suite is in-process. `test/integration/bnest_app_web/family_chat_graphql_test.exs` runs the genuine endpoint,
router, session/CSRF plugs, and `Absinthe.Plug`, asserting status, content type, variable coercion, and the
`data`/`errors` envelope. Binding a second listener beside a 24/7 service buys nothing the `bnest-app-be-e2e`
project does not already prove at the real socket.

**Durable owner:** `tech-docs/006-file-impact-and-release.md`, corrected 2026-09-22.

## Phase 4 — Send Path and Offline Outbox

**The optional field is the compatibility mechanism, not a nicety.** Three hops carry the reply target — the queued
record (`outbox_namespace.js`), the transport call (`outbox_send.js`), and the persisted row
(`persistence_indexeddb.js`) — and all three spread it conditionally rather than writing `replyToMessageId: x ?? null`.
That is what lets `DB_VERSION` stay at 1: a row written by the shipped release and a non-reply written by this one
are the same object, so hydration needs no migration and no version check. A `null` default would have forced a
schema bump for a field that adds nothing to most messages.

**Durable owner:** `tech-docs/003-ui-design.md`, corrected 2026-09-22.

**One field set, three documents.** `operations.js` used to hold the query, the mutation, and the subscription as
three independent template strings. Replies would have required editing all three identically, and a drift between
the subscription's fields and the query's is invisible until a live message renders differently from a resumed one.
They now all derive from `messageFields({replies})`, and the mutation additionally declares `$replyToMessageId`
only when the flag is on — so with the flag off the browser emits byte-identical pre-reply documents, which is what
the compatibility release depends on.

**Durable owner:** `tech-docs/002-graphql-contract.md`, corrected 2026-09-22.

**The draft and the reply target clear for different reasons.** The composer reads the target before awaiting the
queue and calls `clear()` only after the queue accepted. A refusal restores `draftState.body` and leaves the target
untouched, so a member who hit a full queue still has both their text and the message they were answering. Keeping
the target outside `draftState` is what makes that separation structural rather than a rule someone must remember.

**Durable owner:** `tech-docs/004-interaction-and-accessibility.md`, corrected 2026-09-22.

**Lint budget shaped the file split, again.** `max-lines` (300) and `max-lines-per-function` (50) pushed four
extractions this phase: `buildQueuedMessage` into `outbox_namespace.js`, `refuse`/`sendOptionsFor`/`publishQueued`
out of the composer's `submit`, `createReplyTarget`'s methods into top-level factories, and `assembleRoom` out of
`initRoom`. Each landed on a seam that was already there; none needed a new concept. The header comment in
`outbox.js` already records that this split exists for the budget — worth keeping, because the alternative reading
is that the modules were designed apart for their own sake.

**Durable owner:** none; recorded here so the next phase expects the same pressure.

## Phase 5 — Action Menu, Composer Strip, and Keyboard Reach

**The accessibility check was measuring the template, not the room.** `accessibility.js`'s keyboard-reachability
proxy read the shipped `room.html.heex` as text and looked for the words that suggest reachability. It could not
have failed for the reason it exists: nothing about a rendered list of fifty messages is visible in a template that
renders an empty `<ol>`. Replacing it meant rendering real messages through the shipped renderer, which meant a DOM,
which is why `happy-dom` entered the dependency tree. The deliberate RED is the point of the entry: breaking
`apply`'s reset to `item.tabIndex = 0` now fails the check, and the old scan could not have noticed.

**Durable owner:** `tech-docs/006-file-impact-and-release.md`, corrected 2026-09-22.

**A new dependency needed a decision record, not a convenience argument.** `happy-dom@20.14.5` is pinned exactly,
added as a dev dependency, excluded from the browser bundle through esbuild's `--external:happy-dom` beside the
existing `node:fs`/`node:url` externals, and checked against `package-lock.json`'s advisory set before and after.
The rejected alternatives are recorded in its commit body: Node's own stdlib (no DOM), a hand-written element shim
(a shim asserts what its author already believes), and jsdom (heavier for the same answer). The requirement it
serves is a plan requirement — "the rendered-list invariant" — not a preference.

**Durable owner:** `repo-governance/development/dependency-selection.md`'s existing record format; nothing to change.

**The flag plumbing moved a phase earlier than the plan put it.** Phase 7 owned `config/runtime.exs`, the controller
assign, and the `data-family-chat-reply-enabled` read. Phase 5 needed all three, because the fe-e2e binding-coverage
gate is all-or-nothing — 59 missing steps, including Phase 9's compatibility-revision scenario — and the repository's
Gherkin→bindings→red→code order therefore required binding every browser scenario before any of them could pass.
Recorded here rather than silently absorbed: the plan's phase boundary was wrong about which phase first _needs_ a
flag, not about who owns it.

**Durable owner:** none; a deviation, ticked in Phase 7 referencing where it actually landed.

**One menu host, one hidden attribute, and a focus rule that fought itself.** `bindMenuDismissal` returns focus to
the originating message on every close path — Escape, clicking outside, and choosing an item alike. Choosing
`Reply` is the one path that must not: it puts focus in the composer, and the dismissal listener on the host was
taking it straight back, in the same gesture. An item that places focus itself now stops the click before it
reaches the host. The bug was invisible to the unit specs, which drive `createMenuState` and `runCopyAction`
directly and never dispatch a real event through both listeners — it took the browser-shaped Gherkin room to see it.

**Durable owner:** `tech-docs/004-interaction-and-accessibility.md`, corrected 2026-09-22.

## Phase 6 — Quote Rendering, Jump, and Styles

**"The strip renders the server's bounded preview" was true of arrivals and false of selections.** A quote that
comes back from the server is already shortened by `BnestApp.FamilyChat`'s 160-grapheme rule. A target chosen from
a bubble on screen never passes through the server at all: `mount_browser_actions.js` built it from the rendered
body, in full. The scenario "A long quoted message is shortened in the strip" is what caught it —
`Error: the strip shows 400 graphemes` — and the fix is `bodyPreview` in `reply_target.js`, applying the same rule,
by grapheme rather than code unit, so the strip and the quote card can never disagree about the same message. The
BE and FE drivers both allow `<= 161`, with the same comment: the budget plus the one ellipsis that marks the cut.

**Durable owner:** `tech-docs/004-interaction-and-accessibility.md`, corrected 2026-09-22.

**A message composed offline never actually said so.** Tech-doc 003's state machine names "Waiting for connection",
and nothing was leaving a message there for longer than the instant between queueing and the first attempt: the
outbox attempted immediately, the transport failed, and the member saw "Retrying in …" — a state that reads like
something went wrong, for the one case where nothing did. The scenario "An offline reply queues with its target"
failed with `the queued reply shows status "Sent"`, which is how the gap surfaced. The outbox now carries the
browser's own `online`/`offline` verdict, deliberately as a flag separate from `draining` (which `reconnect.js`
owns while it fills a catch-up gap): both can be true at once, and resuming one must never resume the other.

**Durable owner:** `tech-docs/003-ui-design.md`, corrected 2026-09-22.

**The frontend typecheck gate had been red for three phases.** `tsc --noEmit` over `assets/` covers `test/**` as
well as `js/**`, and nothing had run it since Phase 4. Thirty-one errors had accumulated, including one that
mattered: a JSDoc block orphaned from `createRoomResume` by an inserted function, leaving both its parameters
implicitly `any` for the whole of Phases 5 and 6. Lint and the suites were green throughout. A gate that is not in
the loop is not a gate — the phase checkpoints name `FE_UNIT` and say nothing about `typecheck`, which is why it
went unnoticed rather than because anyone ignored a failure.

**Durable owner:** `repo-governance/development/software-quality-enforcement.md` — the phase-checkpoint command set
should name the typecheck target alongside the suites. Raised 2026-09-22 in
`plans/ideas/q2-not-urgent-important/plan-and-checkpoint-contract-gaps.md`.

**The Vitest+Gherkin harness needed a second kind of room, and the two must never meet.** `family_chat.steps.ts`
opens the real `initRoom` in Node, where `typeof document === "undefined"` selects the in-memory store, transport,
and page source. The reply scenarios are about markup, focus, and key events, so they need the other branch.
`support/reply_room.ts` builds it from the same production pieces — the template's shell under happy-dom,
`createRealStore`, `createHistory`, `createReplyTarget`, and the real `wire*` bindings — substituting only the
network. The hazard is entirely in the seam: a `document` left on `globalThis` silently flips every _following_
document-free scenario onto the browser branch. It is taken down in `verify.ts`'s `finally`, and again inside the
builder when a room fails to build half-way — which is exactly how it first leaked
(`ReferenceError: HTMLMetaElement is not defined`, in an unrelated auth-expiry scenario three tests later).

**Durable owner:** `tech-docs/006-file-impact-and-release.md`, corrected 2026-09-22.

**Where a browserless layer genuinely cannot answer, the binding says which layer does.** Tab's sequential-focus
engine, `prefers-reduced-motion`, and on-screen position have no Node equivalent. Those bindings assert the decision
this layer does own — the roving invariant, the highlight attribute the stylesheet answers, the recorded
`scrollIntoView` target — and name `bnest-app-fe-e2e` for the rest, in a comment at the binding. That is the
difference between a documented boundary and a no-op: each one still fails if the decision it owns regresses.

**Durable owner:** `repo-governance/development/specification-maintenance.md` already requires this; recorded as a
worked example.

**A test double that resolves too fast hides a real ordering.** `wireComposer` registers its status watcher _after_
awaiting `composer.submit()`. The harness server initially resolved on a microtask, reached "Sent" with nobody
listening, and the pending row was never reconciled — which looked like a rendering bug for several minutes.
`createTestTransport` already resolves on a timer for precisely this reason, and says so in a comment; the harness
server now does the same. Worth keeping in mind before treating a fast double as the neutral choice.

**Durable owner:** none; recorded here.

## Phase 7 — Documentation, Rules, and Public-Boundary Proof

**The real browser found the one thing every browserless layer had agreed on.** Tab's sequential-focus engine has
no Node equivalent, so `rovingInvariantHolds` checked the only thing it could see — exactly one message carrying a
tab stop — and the quote card, a `button` inside a bubble, was a tab stop by default. With fifty replies on screen,
Tab walked the conversation one quote at a time instead of leaving the list. `tabindex="-1"` fixes it without
touching the role, the type, or the accessible name, so a screen reader still reaches and announces the card, which
is all AC-FCR-10 asks for. The check now also rejects anything focusable _inside_ a message, so the next control
added to a bubble fails instead of quietly adding a stop per message. Whether a keyboard-only reader without a
screen reader should reach the card at all is Phase 8's question, not one to settle by widening the tab order.

**Durable owner:** `tech-docs/003-ui-design.md`, corrected 2026-09-22.

**One fix, applied one file too wide.** `getByLabel("Message")` became strict-mode ambiguous the moment the action
menu added `Actions for <name>'s message` to every bubble — but only on the room's page. The Codex chat LiveView's
composer is labelled `Message` and has no bubbles, so the locator was never ambiguous there. Ten step files
mentioned the label; six drive the room and four drive `/chat`, and all ten were converted. Every Codex chat
scenario then timed out looking for `Message the family` on a page that has no such label. The cost was a whole
suite run. A locator rename is a page-scoped change, and the page each step file drives — `[data-phx-main]` and
`phx-connected` for the LiveView, `[data-role="family-chat-room"]` for the room — is the thing to check first, not
the string being replaced.

**Durable owner:** none; recorded here.

**The flag existed, and nothing could turn it on.** `config/runtime.exs` read `BNEST_FAMILY_CHAT_REPLY_ENABLED`
from Phase 5, but `deployment.mjs` builds its launchd plist from a hard-coded allowlist, and `release.mjs`'s
experience candidate passed only `--family-chat-enabled`. A variable absent from that allowlist is a variable the
managed process never receives, so Phase 10 would have promoted a revision that reads the flag and is never given
it — and `/health/ready` cannot tell, because the room sits behind `:authenticated_browser`. The plan's file-impact
table did not list either tool, which is the deviation worth naming: it listed every file the _feature_ touches and
none of the files the _release_ touches.

**Durable owner:** `tech-docs/006-file-impact-and-release.md` — its File Impact table should cover the release path
whenever a plan introduces a runtime flag. Corrected 2026-09-22 in that document's Configuration section; the
general rule is raised in `plans/ideas/q2-not-urgent-important/plan-and-checkpoint-contract-gaps.md`.

**The root README's family-chat paragraph is stale, and this plan is not the place to fix it.** It says
`BNEST_FAMILY_CHAT_ENABLED` "still defaults to off in production, so the routes, GraphQL surface, and home-page
entry point stay inactive". The default is still off; production is not. The routed slot sets it explicitly, and
the room has been live since its own experience release. Correcting that sentence is a documentation change about a
different feature's release state, so it is raised as a follow-up idea brief rather than absorbed here.

**Durable owner:** corrected 2026-09-22 directly in `README.md`, which is a better owner than a brief — the
paragraph was live and false, and a brief would have left it that way.

### Manual API proof — six observations at an isolated origin

One `MIX_ENV=test` instance on the development port pool, its own runtime root and its own family-chat SQLite
path, started in a tmux pane so its lifetime did not follow the agent session. Two synthetic `test-user-`
identities, created through the product's own one-time setup form. No production root, port, pointer, or identity
was read or written; the instance and both roots were removed afterwards and their absence verified. Nothing below
records a secret, a cookie, a token, or real message text.

| #   | Observation                                                 | HTTP | `data`  | `errors`            | Side effect                |
| --- | ----------------------------------------------------------- | ---- | ------- | ------------------- | -------------------------- |
| 1   | `familyChatMessages`, one page                              | 200  | present | absent              | none (read)                |
| 2   | `sendFamilyChatMessage` with a valid `replyToMessageId`     | 200  | present | absent              | one row committed          |
| 3   | `sendFamilyChatMessage` with an absent `replyToMessageId`   | 200  | `null`  | `VALIDATION_FAILED` | no row committed           |
| 4   | `sendFamilyChatMessage` with a target from another room     | 200  | `null`  | `VALIDATION_FAILED` | no row committed           |
| 5   | The same operation, no session at all                       | 403  | `null`  | `CSRF_REJECTED`     | no row committed           |
| 5b  | The same operation, valid session, unresolved identity      | 200  | `null`  | `UNAUTHENTICATED`   | no row committed           |
| 6   | The same operation, authenticated without `use_family_chat` | —    | —       | —                   | unrepresentable; see below |

**Observation 1 is the one that matters most for the release.** The page carried three nodes: one with `replyTo`
`null` and two with it populated. The populated quote's `bodyPreview` measured **161** graphemes and ended in an
ellipsis — the 160-grapheme budget plus the single character that marks the cut, exactly what tech-doc 002 states
and exactly what the frontend's own `bodyPreview` produces for a target chosen on screen. The room shell for this
instance carried `data-family-chat-reply-enabled="false"`, so this is the compatibility posture the release
depends on observed directly: **the server answers `replyTo` with the flag off**, and only the browser stops
asking.

**Observations 3 and 4 are refused identically, and that is correct.** The target is looked up scoped to the room
(`message_by_id(room_id, message_id)`), so a message id belonging to another room is, from the room's point of
view, a message id that does not exist. Both are refused before any write, and the second room's message remained
the only message in that room afterwards.

**Observation 5 is refused at the transport layer, not the resolver.** A request with no session carries no CSRF
token either, and the CSRF pre-parse plug runs before identity resolution — so `CSRF_REJECTED` at 403, never
reaching `UNAUTHENTICATED`. To exercise the resolver's own refusal, observation 5b used a genuinely anonymous
_session_: a valid signed session cookie, a valid CSRF token, and no resolved identity. Both codes are reachable
and distinct.

**Observation 6 could not be made at the public boundary, because the account it needs cannot exist.**
`Authorization.allow?/3` grants `use_family_chat` to any identity whose roles are all drawn from
`children|parents|admin`, and the account record schema requires exactly that: a non-empty list drawn from the
same three. An authenticated identity without the capability is therefore unrepresentable, and the two layers were
each observed refusing it — a stored account with an empty role set could not be logged in at all (the store
refuses to read the record), and `Authorization.allow?/3` returns `false` for both `[]` and `["guest"]` while
returning `true` for `["parents"]`. Recorded as a documented boundary rather than a skipped observation: the
refusal is real and proven, but its proof is not an HTTP status.

**Subscription lifecycle.** The handshake was confirmed by `curl` at the isolated origin —
`101 Switching Protocols` on `/api/graphql/socket/websocket` with the authenticated session — and, as tech-doc 008
requires, that is handshake evidence only. The full lifecycle is proven by the protocol-capable Phoenix
channels-v2 client in `bnest-app-be-e2e`: "A subscribed reply arrives carrying its quote" and "A reply caught up
through `afterId` carries its quote", both green in the `BE_E2E` run recorded below (29 passed).

**Durable owner:** none; this is release evidence, not a rule.

### Rules propagation — terminal result

`PASS_NO_CHANGE`. The ledger for this execution has no `OPEN` rows: nothing under `repo-governance/`, `AGENTS.md`,
`CLAUDE.md`, or `RTK.md` was created, changed, moved, or deleted by it. The two governance gaps this execution did
find — that a plan's File Impact table should cover the release path whenever the plan introduces a runtime flag,
and that the phase-checkpoint command set should name the typecheck target alongside the suites — are recorded
above as proposals owned by archival, not as edits made here; raising them is a separate transaction with its own
authorization. Step 4 verified: `REPO` green.

**Durable owner:** none; a recorded terminal result.

### 2026-09-22 — Phase 8, and three defects only a person could see

The matrix below was walked by hand at the isolated origin
(`/family-chat/ruang-keluarga`, reply flag on, synthetic `test-user-manual-*` identities, isolated runtime and
SQLite roots). Every cell is a measurement taken from the live document — bounding boxes, computed styles,
attribute lifetimes — not a screenshot read by eye and not an assertion borrowed from a suite.

Three defects surfaced. All three were **invisible to the automated suites**, and the reason is worth stating
once: the browser scenarios assert that an element _exists_, is _not hidden_, and carries the right
`data-message-id`. None of those three facts constrains where the element is, how wide it is, or what colour its
focus ring is. A menu 600px from its message satisfies every one of them.

#### The matrix

Routes: `/family-chat/ruang-keluarga` throughout. `PASS` means measured and conforming to tech-doc 003.

| State             | 320 × 568                                                                   | 768 × 1024                        | 1440 × 900                        |
| ----------------- | --------------------------------------------------------------------------- | --------------------------------- | --------------------------------- |
| Idle              | PASS (after D-2)                                                            | PASS                              | PASS                              |
| Focused           | PASS (after D-3)                                                            | PASS (after D-3)                  | PASS (after D-3)                  |
| Menu open         | PASS — sheet, flush to bottom edge, full width, no inline placement         | PASS (after D-1) — popover, gap 8 | PASS (after D-1) — popover, gap 8 |
| Reply unavailable | PASS — `aria-disabled="true"`, reason stated, `Copy text` still live        | PASS                              | PASS                              |
| Strip shown       | PASS — inside viewport, preview ellipsized, cancel named, focus to composer | PASS                              | PASS                              |
| Reply rendered    | PASS — committed, quote card present, strip cleared, composer emptied       | PASS                              | PASS                              |
| Jump succeeded    | PASS — target focused and in view, highlight 1.2s, attribute held ~2.0s     | PASS                              | PASS                              |
| Jump refused      | PASS — bound respected, window left where paging put it, refusal announced  | PASS                              | PASS                              |
| Reduced motion    | PASS — `animation: none`, static sun outline ~2.1s, menu transition `0s`    | PASS                              | PASS                              |
| Offline           | PASS — banner shown, send queues as `Waiting for connection`                | PASS                              | PASS                              |

Behaviour-only states (Reply unavailable, jump, reduced motion, offline) are viewport-independent by construction;
they were driven end to end at 320 × 568, where the layout is tightest, and confirmed present at the other two.
Layout-sensitive states were measured at each width separately.

#### D-1 — The action menu never had a position

Tech-doc 003's Responsive Behaviour table asks for "popover anchored to the message" at both ≥1024px and
600–1023px. The stylesheet only implemented the sub-600px sheet, and `renderMenu` set `hidden`, the
`data-message-id`, and the items, but never placed the host. Measured at 1440 × 900 before the fix: menu at
`{x: 336, y: 20}`, its message at `{x: 702, y: 272}` — the fixed-position host had fallen to the room container's
top-left corner and was sitting on the dark header, roughly 600px from the message whose actions it offered.

Fixed by `menu_anchor.js`, a pure `menuPlacement` with its own unit tests plus a thin DOM wrapper, called from
`renderMenu`. It stands down entirely below 600px, clearing the inline properties so the sheet rules govern.
Confirmed after: own message anchors its right edge (menu right 1072 = message right 1072, top = bottom + 8),
another member's anchors its left, 768 × 1024 likewise, and 320 × 568 still reports no inline placement and a
full-width sheet flush to the bottom edge.

One branch is unreachable in this layout and is covered by unit test only: the composer pins the newest message
above itself, so "below" always fits and the flip-above path never fires in the room as built. It is kept because
the arithmetic should not depend on that remaining true.

**Durable owner:** none; the fix is the record.

#### D-2 — A quoted reply burst out of a 320px viewport

A message is a grid. A grid item's automatic minimum is its min-content width, and the quote card's preview is a
single `white-space: nowrap` line, so its min-content width is the whole preview — 255px at 320px wide. That floor
propagated up through the bubble into the message's auto track, which outgrew the message's own `max-width: 78%`.

Measured before: bubble 300px wide starting at x = 71, right edge at 371 against a 320px viewport — 51px off the
screen, with the history horizontally scrollable (`scrollWidth` 343 against `clientWidth` 264) and the
`text-overflow: ellipsis` that was meant to absorb a long preview never engaging, because nothing ever forced the
preview to be narrower than its text. Measured after `min-width: 0` on the bubble and the preview: bubble 163px
ending at 234, preview genuinely truncated, zero overflowing nodes, neither the history nor the page scrolling
sideways. Nothing moves at 768 or 1440, where the track never reaches the floor.

**Durable owner:** none; the fix is the record.

#### D-3 — Five focus rings that were not the room's

Tech-doc 003's Focus row names five targets — the message, the actions control, each menu item, the quote card,
and the cancel control — and says "The ring is the room's existing one." None of the five carried it. The only
`:focus-visible` rule any of them had set the actions control's _opacity_. Each therefore fell back to the user
agent's default ring: perfectly visible, which is exactly why no automated visibility or contrast check would flag
it, and not this room's.

Measured by real `Tab` at the isolated origin — programmatic `.focus()` does not match `:focus-visible` and will
mislead anyone who checks that way. A focused message reported `auto 1px rgb(0, 95, 204)` before and
`solid 3px rgb(247, 184, 75)` at `2px` offset after, identical to the brand and push controls beside it. The five
selectors joined the room's existing rule rather than restating it, so "the room's existing one" is now true of
the stylesheet as well as the prose.

**Durable owner:** proposed — _a spec line that names a shared token is a claim about the cascade, not only about
the rendering; it should be satisfied by referencing the rule, not by re-deriving its values._ Raised 2026-09-22 in
`plans/ideas/q2-not-urgent-important/shared-token-claims-and-layer-tags.md`.

#### Two observations that are not defects

**The jump highlight's attribute outlives its animation.** Under normal preference the animation is
`family-chat-jump-pulse` at 1.2s while `data-jump-highlight` is held ~2.0s; under `prefers-reduced-motion: reduce`
there is no animation and the static sun outline is held ~2.1s. Tech-doc 003 specifies "a 1.2 s fade" and "a
static outline held for 2 s". One attribute lifetime serving both, with only the animation differing, satisfies
both readings and is simpler than two timers. Recorded rather than changed.

**~~The refused jump speaks through the live region, not the remediation paragraph.~~ Withdrawn — this was a
defect, and the check that cleared it was too weak.** The original note recorded that the live region "is visible"
and concluded the spec was satisfied. The check behind that word was `getBoundingClientRect().height > 0`, and
`family-chat-live-region` is `1px × 1px` with `clip: rect(0, 0, 0, 0)` — a screen-reader-only element that passes
a `> 0` test comfortably. The spec names two surfaces precisely because one of them cannot be seen. Corrected and
fixed below as **D-5**; the lesson is that "visible" needs a predicate that a 1px clipped element fails.

#### How the refusal state was reached honestly

A refusal needs a target further back than `MAX_JUMP_PAGES` × `MESSAGE_PAGE_SIZE` = 250 messages _from the oldest
initially rendered message_, which is a stricter bound than it first looks: the first attempt seeded 270 fillers
and the jump **succeeded**, because the initial page of 50 plus five loaded pages of 50 covered all 277 messages.
Only after seeding to 408 total — putting the target 250 messages beyond the oldest of the newest page — did the
bound actually bite. The rows were inserted into the isolated SQLite root under the synthetic identities already
seeded there, which the append-only triggers permit; nothing was updated or deleted, and no production root, port,
or identity was touched.

Worth keeping: a test that seeds "more than the bound" by counting from the newest message is off by a whole
initial page and will quietly assert the success path while claiming to assert the refusal.

**Durable owner:** none; an execution note.

### 2026-09-22 — Phase 8, the keyboard and screen-reader walkthrough

Driven at the isolated origin with real key events, not programmatic focus. Two measurement cautions learned the
hard way and worth repeating to anyone who repeats this: **programmatic `.focus()` does not match
`:focus-visible`**, so checking a focus ring that way reports the user-agent default and hides a real defect
(this is how D-3 nearly escaped); and **`textContent` is not an accessible name** — reading the message that way
produced `"Ttest-user-manual-ayah 9/22/2026, 4:24:31 PMPesan..."`, which looks like a serious labelling defect and
is not one. The accessibility tree shows the avatar initial correctly marked `aria-hidden`, and the real names are
clean.

#### The journey, keyboard only

| Step                      | Key                      | Where focus lands                                | What is announced                                                        |
| ------------------------- | ------------------------ | ------------------------------------------------ | ------------------------------------------------------------------------ |
| Enter the room's controls | `Tab` ×n                 | `Load older messages`                            | —                                                                        |
| Enter the history         | `Tab`                    | the newest message (the single roving stop)      | —                                                                        |
| Move between messages     | `ArrowUp` / `ArrowDown`  | the previous / next message, stop moving with it | —                                                                        |
| Open the menu             | `Enter` or `Space`       | first item, inside `menu "Message actions"`      | —                                                                        |
| Choose Reply              | `Enter`                  | the composer textarea (`Message the family`)     | `Replying to test-user-manual-ayah.`                                     |
| Abandon the reply         | `Escape` in the textarea | stays in the composer                            | `Reply cancelled`                                                        |
| Send                      | `Enter`                  | stays in the composer                            | `New message from test-user-manual-ayah: Balasan lewat papan ketik saja` |

The whole reply journey completes without a pointer, and every state change that has no visible focus move is
spoken instead. The roving stop was verified to remain exactly one message throughout.

#### The exact announced text the plan asked to record

- **Quote card:** `Reply to test-user-manual-ayah: Assalamualaikum semuanya. Go to that message.` — a `button` in
  the accessibility tree, naming the sender, the preview, and the action, in that order.
- **Disabled Reply item:** `menuitem "Reply" [disabled]`, carrying
  `aria-description="Send this message before replying to it"`. It remains focusable while disabled, which is
  correct: a member who lands on it is told why it will not act, rather than finding it skipped with no
  explanation.
- **Actions control:** `Actions for test-user-manual-ayah's message`.
- **Refused jump:** `That message is too far back to jump to.`, in the room's `role="status"` live region.

#### The one gap, examined and accepted as non-blocking

**A sighted keyboard-only member cannot follow a quote back to its original.** The quote card is a button with
`tabIndex = -1` — deliberately, because the history's contract is one Tab stop — and the action menu offers only
`Reply` and `Copy text`. Tech-doc 004's key list is complete and deliberate and gives the jump no key of its own.

Accepted rather than fixed, for three reasons: a screen-reader user _does_ reach the card, because browse-mode
navigation reaches non-tabbable buttons and the card is a properly named button in the tree, which is what
tech-doc 004's "usable without sight" claim actually rests on; the menu's contents are fixed by decision D5 and a
third item is a specification change, not an implementation detail; and making the card a tab stop would break the
one-stop contract that D9 proved at two layers. Fixing it properly means adding a `Go to that message` menu item
through the Iron Rule, which is a change to D5 and belongs to its own plan.

**Durable owner:** raised 2026-09-22 in
`plans/ideas/q2-not-urgent-important/family-chat-room-reading-on-a-phone.md` — _the action menu should offer `Go to that
message` on a message that carries a quote, so the jump has a keyboard path that does not cost the one-stop
contract._

## Exploratory findings

Spec-aware, driven with Playwright MCP against the isolated origin across all three viewport classes, using the
synthetic `test-user-manual-*` identities and the isolated runtime and SQLite roots. Nothing shared or production
was read or mutated. This pass ran and was recorded **before** the usability pass began.

Findings from this pass that were defects are recorded above as **D-1**, **D-2**, and **D-3**, since they were
found while walking the matrix; they are not repeated here. What follows is what the pass probed beyond the
scripted scenarios.

| Route                         | State                              | Category         | Finding                                                                                                                                                                    |
| ----------------------------- | ---------------------------------- | ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/family-chat/ruang-keluarga` | reply to a 260-grapheme body       | boundary         | **Pass.** Preview is 161 graphemes — 160 plus one ellipsis — from 171 UTF-16 code units.                                                                                   |
| `/family-chat/ruang-keluarga` | preview beginning with a ZWJ emoji | boundary         | **Pass.** `👨‍👩‍👧‍👦` counts as one grapheme and is never split mid-sequence.                                                                                                     |
| `/family-chat/ruang-keluarga` | reply to a reply                   | boundary         | **Pass.** The quote shows the target's own body, never the grandparent's, and quoting stays exactly one level deep.                                                        |
| `/family-chat/ruang-keluarga` | over-length send with a target set | boundary         | **Pass.** Refusal states `Keep messages under 4,000 characters.`, the 4,001-character draft is kept, the reply target survives, nothing is sent.                           |
| `/family-chat/ruang-keluarga` | `familyChatMessages` over the wire | passive security | **Pass.** `replyTo` returns exactly `id`, `senderDisplayName`, `bodyPreview` — no sender id, no room internals, nothing that would let one member enumerate another.       |
| `/family-chat/ruang-keluarga` | rendered room                      | passive security | **Pass.** Exactly one opaque user id appears in the DOM, `data-current-user-id` on the room container, and it is the viewer's own. No other member's id is exposed.        |
| `/family-chat/ruang-keluarga` | route structure                    | route/URL        | **Pass.** No message identifier ever reaches the URL; the room has no per-message route to enumerate or share.                                                             |
| `/family-chat/ruang-keluarga` | reply target in another room       | boundary         | **Pass** (proven at the API in Phase 7). The server refuses a cross-room target rather than quoting across rooms.                                                          |
| `/family-chat/ruang-keluarga` | reply target deleted               | boundary         | **Unrepresentable by design.** The messages table carries `BEFORE UPDATE` and `BEFORE DELETE` triggers that abort, so a dangling reply target cannot exist to be rendered. |

**A methodology caution.** A synthetic `form.dispatchEvent(new Event("submit"))` reported the over-length case as
"draft lost, no remediation" — which would have been a real defect had it been true. Repeating it with a real
`Enter` keypress showed the refusal behaving exactly as specified. A probe that fabricates the event instead of
pressing the key tests the fabrication.

**Durable owner:** none; execution evidence.

## Usability findings

Spec-blind, and structurally so: the pass was delegated to a fresh agent context given only the origin, the route,
and the three viewport classes, and explicitly denied the specs, the source, and the design assets. It judged
first-time-user perception against Nielsen's ten heuristics, a cognitive walkthrough, the reachable empty/loading/
error/zero-result states, and responsive usability. It ran **after** the exploratory pass was finished and
recorded, so the two lenses never blended.

It reported the reply feature itself as the strong part of the room — the strip with its named target and explicit
cancel, the live-region announcement, the jump with its highlight, the mobile bottom sheet, scroll anchoring on
`Load older messages`, and the disabled `Beginning of family chat` end state. What it found wrong divides cleanly
into this plan's business and the room's.

### Findings inside this plan, and what happened to each

| #   | Finding                                                                                                                       | Severity | Disposition                                                                                                                                                                                                                                                   |
| --- | ----------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D-5 | A refused jump is announced only to a 1px clipped live region; a sighted member watches five pages load and then sees nothing | major    | **Fixed**                                                                                                                                                                                                                                                     |
| D-6 | The composer's reply strip drops the quoted text entirely at 320px and 414px — preview column measured exactly 0px            | major    | **Fixed**                                                                                                                                                                                                                                                     |
| D-7 | The `⋯` actions control is 35 × 21, under WCAG 2.2's 24 × 24 target-size minimum                                              | major    | **Fixed**                                                                                                                                                                                                                                                     |
| D-8 | A stale refusal outlives the successful jump after it, so a screen reader is told the jump failed when it landed              | minor    | **Fixed** (same change as D-5)                                                                                                                                                                                                                                |
| —   | The action menu opens below the bubble and can overlap the following message; nothing in the menu names its target            | minor    | **Accepted.** The menu is anchored to its own message with an 8px gap (D-1) and the control that opens it is named `Actions for <sender>'s message`. Naming the target inside the menu is a copy change to tech-doc 003's inventory, not a defect against it. |

**D-5.** Fixed in `mount_browser_jump.js`: the refusal now writes the live region _and_ the visible
`family-chat-remediation` paragraph, and both are cleared when a jump is activated. Measured after: the
remediation is 704 × 24 and unclipped, carrying the exact specified sentence, and a subsequent successful jump
leaves it hidden and empty.

**D-6.** The strip is `grid-template-columns: auto 1fr auto`. Narrow enough, the name wraps to two lines, the
cancel control keeps its width, and the preview — `overflow: hidden`, whose automatic minimum is therefore zero —
is the column that loses, collapsing to exactly `0px` while its text stays in the DOM. Measured `119.797px 0px
106.016px` at 320px. The preview now takes its own row below 600px: 128px wide and legible.

**D-7.** Raised to `min-height: 1.5rem`, measured 35 × 24. Worth noting that the control is not a tab stop and the
menu has two other entry points — `Enter` on the focused message, and hold or right-click on the bubble itself, a
far larger target — so WCAG's equivalent-control exception was arguably already available. It was cheaper to meet
the criterion than to argue the exception.

### Findings outside this plan

Recorded because they were observed, not fixed here: the interface is entirely in English while the room is named
and used in Indonesian (`<html lang="en">`); at 320px the header and composer take 291 of 568 pixels, leaving two
message bubbles visible; long messages are unreadable on a phone; the composer textarea never grows; `Use dark
theme` sets `data-theme="dark"` but the room's colours do not change; there is no "jump to newest" affordance;
every message repeats the sender name and full date with no day separators or grouping; `Send` is enabled on an
empty composer; and `Load older messages` gives no in-flight feedback. None of these is introduced, worsened, or
touched by quoted replies. They are the room's, they predate this plan, and fixing any of them here would be scope
this plan did not ask for and did not verify.

**Durable owner:** raised 2026-09-22 as deferred idea briefs, one per theme rather than one per finding, with
this dated pass as their evidence.

### Two reported findings that were wrong, and one that was my own test data

The pass is more useful for having been checked rather than believed.

- **"68 tab stops before you can type."** False at every width. Measured: 10 tabbable elements at 320 × 568 and 14
  at 1440 × 900, with **zero** `⋯` buttons and **zero** quote cards among them, and the composer at index 8 and 12
  respectively. The roving tabindex holds and D9's two-layer proof stands. The likely source of the count is a
  query that treated focusable-but-not-tabbable nodes as tab stops.
- **"The actions menu opens beneath the bubble, visually attached to the wrong message."** Half right: it does open
  below, by design and with a measured 8px gap. A sweep of the last twelve messages at 1440 × 900 found **no**
  message whose own centre the menu covers.
- **"The visible clock runs backwards in the middle of the conversation."** Real, and mine: message 408 shows
  4:40:00 PM above message 409's 4:24:31 PM because I inserted the far-reply fixture with a hand-written
  `committed_at` while seeding the jump-refusal state. An artefact of this session's test data, not of the
  product. Recorded so nobody chases it.
- The same applies to **"everyone has the same avatar"** — every initial is `T` because the seeded identities are
  `test-user-manual-ayah` and `test-user-manual-bunda`.

### Cross-reference between the two passes

One finding pair shares a root cause. The exploratory pass's **D-2** (a quoted reply bursting out of a 320px
viewport) and the usability pass's **D-6** (the strip's preview collapsing to zero) are the same mistake in two
places: a `white-space: nowrap` preview inside a grid or flex parent, where the automatic minimum size decides who
loses. D-2 lost by _overflowing_ because the bubble's minimum was its min-content width; D-6 lost by _vanishing_
because `overflow: hidden` makes that minimum zero. Both were fixed by making the sizing explicit rather than
automatic — `min-width: 0` in the first case, an own row in the second — and a note to that effect is recorded in
both sections.

No other pair shared a root cause: the exploratory pass's remaining findings were boundary and passive-security
probes that all passed, and the usability pass's remaining findings are room-wide.

### Iron Rule reconciliation

No usability or exploratory finding proposed a change to `specs/**`. D-5 through D-8 are defects against tech-doc
003 as already written — its Error row names both refusal surfaces, its strip description requires the preview,
and its Focus row already demanded the room's ring — so each was a straight fix with no Gherkin change. The one
specification change this phase did make came from the Gherkin implementation review, not from either manual pass,
and is recorded below with its own RED evidence.

**Durable owner:** none; execution evidence.

### 2026-09-22 — Phase 8, the Gherkin implementation review

Delegated, as the workflow requires ("Use an agent to perform the review. Do not replace the one-by-one inspection
with scenario counts, a grep-only heuristic, or a green test run"). Scope: the scenarios this branch added or
materially changed across the three feature files.

**Corpus.** 51 expanded scenarios (FE 38, `family_chat_graphql` 11, `family_chat_operations` 2) × 3 required
adapters = **153 rows**. Outlines expanded rather than counted: `A member opens the message action menu` ×4,
`A message that is not yet committed cannot be replied to` ×4, `The member abandons the reply` ×2, `A reply
carries its quote through each arrival path` ×4, and `A reply target the server cannot honour is rejected before
commit` ×3.

**Result as reviewed:** 64 `PASS`, 69 `EXEMPT`, 13 `PARTIAL`, **7 `FAIL`**. Every one of the 39 exemption tags was
scenario-level, canonically commented, genuinely a boundary mismatch, and named an alternative proof that exists
and runs; no unit-layer exemption was added anywhere; the test-data Iron Rule was clean at every layer.

#### The three defects, and the fixes

**1. `no committed-message event is published` could not fail (6 rows).** The claim sat on a rejection scenario
whose only precondition is the Background login — it never subscribes. The unit driver proved it by draining its
own mailbox, which a process holding no subscription can never receive on; the integration driver counted push
delivery rows joined to a message the _previous_ step had already asserted does not exist. Both returned true for
every possible implementation, including one that published on a refusal. Both drivers' own comments conceded it
("vacuously true … when the scenario never subscribed"; "which the preceding step already pins").

Fixed by moving the claim rather than patching the assertion. It now has its own scenario, `A rejected reply
target publishes no event`, under the post-commit subscription Rule — where the subscription `Given` makes a drain
meaningful and where that Rule's integration exemption is already justified and stated. The unit driver now
**raises** when asked without a subscription instead of answering, so the vacuous shape cannot return quietly; the
integration branch was deleted outright, so an accidental run fails loudly rather than reporting false proof,
which is what step 5 requires. `bnest-app-be-e2e` proves it on a real socket, waiting a second for a push that
should not come before concluding it did not. Green at both retained layers: unit 330 tests, be-e2e 30 passed
(29 before).

This is the one `specs/**` change this phase made. RED evidence: before the new binding existed, `missingSteps:
"fail-on-gen"` refused to generate the spec for the new scenario.

**2. The reduced-motion `Given` was a no-op (1 row).** It wrote `reducedMotion: true` into the step context and
nothing anywhere read it — the `Then` asserted `target.style.animation === ""`, which is equally true with the
`Given` absent. It now installs a real `matchMedia` answering the query, restored per scenario. Production still
does not consult it, and should not: the highlight is a data attribute and the stylesheet answers the media query,
which is the seam the `Then` genuinely pins and which makes the FE_E2E proof possible. The difference is that the
step now _establishes_ the precondition, so an implementation that started reading the preference and got it wrong
would be caught here instead of passing.

**3. Four browser `Then`s dropped the clause that discriminates (5 rows).** `the reply renders a quote naming the
original sender` asserted only that a quote was visible; `the composer shows a reply strip naming {string}` and
`the room announces that the visitor is replying to {string}` took the name as a parameter, ignored it, and
asserted the literal `"Replying to"`. Each would pass on a quote or strip naming the wrong member, or no one. All
four now assert the name, sourced from the scenario's own synthetic identity rather than scraped from the element
the assertion is meant to be judging — which was the weakness in the one place that _did_ check a name.

The feature text names `"Ayah"` while the suite seeds a synthetic `test-user-` identity, which is why the
parameters were ignored in the first place. That is a real constraint of the Iron Rule, and the resolution is to
assert the identity the suite actually used, not to assert nothing.

#### The remaining `PARTIAL` rows, examined and accepted

Eight rows are judgement calls about layer placement and step shape rather than false proof: a `When` that
re-locates instead of acting before a genuine markup assertion; a unit `When` that calls `.focus()` where the step
says "presses Tab", with FE_E2E pressing Tab for real; a page-count upper bound read one settle early; an
integration row that reads the store where its comment claims a GraphQL read. Each is named with its `file:line`
in the review. None asserts a fabricated or sentinel value, and each has a layer that proves the concern properly.
They are accepted as non-blocking and recorded here rather than silently upgraded.

One structural note the review raised and this plan did not create: 18 FE scenarios tagged `@fe-vitest-unit` plus
`@e2e-exempt` end up with exactly one proving adapter, because `FeVitestUnitScope.prune/1` removes them from the
Elixir integration adapter with no `# Exemption(integration): …` comment recording it. That is the repo's existing
sanctioned mechanism — 12 scenarios on `main` already work this way — so it is not scored against this branch.

**Durable owner:** proposed — _the `@fe-vitest-unit` prune silently omits the integration layer; either the tag
should carry the same canonical exemption comment every other omission does, or the standard should say that this
tag is itself the record._ Raised 2026-09-22 in
`plans/ideas/q2-not-urgent-important/shared-token-claims-and-layer-tags.md`.

#### What the review found already right

Two pre-existing placebo bindings that this branch had repaired before the review ran, and the review confirmed
the repairs are real: `:sent_message_with_known_id` used to record a client message ID and body without ever
sending them, so the "retry" was the first commit and idempotency was never exercised; `:original_message_unchanged`
used to assert only `body != known_body`, which a fresh commit of a different body also satisfies.

**Durable owner:** none; execution evidence.

### 2026-09-22 — Phase 8, the five-condition confirmation

Recorded against each condition the plan names, before the checkpoint.

1. **Both passes ran.** The spec-aware exploratory pass ran first and is recorded under `## Exploratory findings`;
   the spec-blind usability pass ran second and is recorded under `## Usability findings`. The second was
   structurally blind — delegated to a fresh context given the origin, route, and viewports only, and denied the
   specs, the source, and the design assets — so the fallback clause ("record explicitly that it ran spec-aware")
   does not apply.
2. **Findings are present or explicitly recorded as none found.** The exploratory pass recorded nine probes, all
   passing, plus one unrepresentable-by-design case; its defects are D-1 through D-3 in the UI matrix section. The
   usability pass recorded four in-plan findings (D-5 through D-8, all fixed), one accepted as non-blocking, nine
   out-of-plan findings, and three reported findings that verification showed to be wrong or to be this session's
   own test data.
3. **Both headings are correctly labelled.** `## Exploratory findings` and `## Usability findings` appear exactly
   once each, at heading level two, and neither set is merged into the other.
4. **Cross-references are noted.** One pair shares a root cause — D-2 and D-6, the same automatic-minimum-size
   mistake in two places — and the note naming it appears in both sections. No other pair shared one.
5. **Every accepted spec proposal completed the Iron Rule.** Neither manual pass proposed a `specs/**` change:
   D-5 through D-8 are defects against tech-doc 003 as already written. The single specification change in this
   phase came from the Gherkin implementation review — moving `no committed-message event is published` to its own
   scenario under the subscription Rule — and it carries its RED evidence and its GREEN result above.

**Durable owner:** none; a recorded confirmation.

### 2026-09-22 — Phase 8 checkpoint

All six manual layers are recorded and separately labelled:

| Layer                         | Where                     | Result                                                           |
| ----------------------------- | ------------------------- | ---------------------------------------------------------------- |
| API `curl` proof              | Phase 7 entry             | 6 observations, recorded by shape                                |
| Subscription proof            | Phase 7 entry             | handshake by `curl`, lifecycle by the channels-v2 client         |
| UI matrix                     | this phase                | 10 states × 3 viewports, all `PASS` after D-1, D-2, D-3          |
| Keyboard and screen reader    | this phase                | full journey without a pointer; announced text recorded verbatim |
| Exploratory (spec-aware)      | `## Exploratory findings` | 9 probes pass; 1 unrepresentable by design                       |
| Usability (spec-blind)        | `## Usability findings`   | 4 in-plan findings fixed, 1 accepted, 9 out of plan              |
| Gherkin implementation review | this phase                | 153 rows; 7 `FAIL` fixed, 13 `PARTIAL` examined                  |

Every finding is either fixed or explicitly accepted with its reason written down. The accepted ones are: the
quote card having no keyboard path of its own (the menu's contents are fixed by D5 and a third item is a
specification change); the action menu opening below its message (measured not to cover it); the eight `PARTIAL`
review rows (each has a layer that proves the concern properly); and the nine room-wide usability findings (not
introduced, worsened, or touched by this plan). None is unexamined.

Eight defects were found by hand in this phase and fixed, every one of them invisible to a 296-scenario browser
suite and a 330-test unit suite that were green throughout. That is the phase's argument for existing.

Gates green on the reviewed revision: `FE_UNIT` 310, `BEHAVIOUR` 150, `BE_UNIT` 330, `INTEGRATION` 330,
`BE_E2E` 30, `LINT` and `TYPECHECK` across all three projects. `FE_E2E` is recorded separately below.

**Durable owner:** none; a recorded checkpoint.

### 2026-09-22 — A strict-mode violation is not a failed assertion

`Sending brings the visitor to their own message` failed on `tablet-chromium` in an otherwise clean run, and kept
failing about once in seven when the scenario was repeated alone on an idle machine. The message was a strict-mode
violation: one locator matched two rows, an optimistic `data-delivery-state="Sending"` row keyed by the client UUID
and a `committed` row keyed by the server id, both carrying the same body.

The first reading was that the store had rendered a duplicate and left it there, because the call log says
`Expect "toBeInViewport" with timeout 5000ms`. Two seconds of arithmetic said otherwise: the failing run took
**1.1 s end to end**, and the passing repeats took 0.8–4.0 s. A 5-second retry loop cannot finish in 1.1 s. So the
assertion did not retry — Playwright retries a _failed_ web-first assertion, but a strict-mode violation is a hard
error raised before any retry. One frame with two rows on screen is enough to fail the step.

That also cleared the store. `reconcile` already handles this exact race: when a subscription push has rendered the
committed row before this send's own mutation response comes back, it drops the now-redundant pending row instead
of creating a second copy. The window between the two is real, tiny, and correct.

So the defect was in the proof, not the product. The `When` polls only `count() > 0`, which is satisfied by the
optimistic row; the `Then` then used a bare locator that the committed row could join at any instant. The fix takes
`.last()`, which names the surviving row whichever way `reconcile` resolves it — the committed row is appended
after the optimistic one, and the replace-in-place branch leaves a single row in the same position. Fifteen repeats
passed after the change.

What was deliberately **not** done: making the `Then` wait for the send to settle. That would have proved the
committed row is in view and quietly stopped proving the thing the scenario is named for, which is that the
visitor's message reaches the viewport immediately rather than after the server answers. Nor was a uniqueness check
added here; `the reply reaches status "Sent" exactly once` and `the offline member's queued message drains exactly
once after reconnect` own that claim already, and a step should not acquire a second job because a flake made it
convenient.

**Durable owner:** code comment on the step, plus this entry as the reasoning behind it.

### 2026-09-22 — A canonical command that could not be run

`BE_E2E` and `FE_E2E` in this plan's command table named the inner Nx invocation. The repository's resource guard
rejects a bare package-runner call that is not inside a HIPPO boundary, so both rows named commands that fail
before they start. The root `test:e2e:be` and `test:e2e:fe` scripts open the boundary themselves — `standard` for
the backend suite, `heavy` for the browser suite — and the rows now name those.

The rows were written from the shape of the other rows rather than from a run. Every other row in the table is a
`./hippo run ... -- ...` invocation, and these two were abbreviated to match the ones that are genuinely
self-guarded without checking which of the two kinds they were. A command table earns its place by being runnable;
one that has never been run is a guess in a table that looks authoritative.

**Durable owner:** the repaired rows and the note under the table.

### 2026-09-22 — `FE_E2E` on the reviewed revision

**296 passed, 0 failed, 10.0 minutes**, across `chromium`, `tablet-chromium`, and `mobile-chromium`.

Three runs were needed to get an honest reading, and the sequence is the point:

| Run | Conditions                                                    | Result     |
| --- | ------------------------------------------------------------- | ---------- |
| 7   | a second Phoenix server and a browser driving it concurrently | 5 failed   |
| 8   | clean: the manual-UI server stopped, nothing else driving     | 1 failed   |
| 9   | clean, after the `.last()` fix                                | 296 passed |

Run 7's five failures were contention, and run 8 proved it by dropping to one. But run 8's survivor was **not**
contention, and re-running until it passed would have buried it — it reproduced once in seven on an idle machine.
It is written up above as its own entry.

Two mechanical notes for anyone reading a failing browser run here. First, the manual-UI server did not stop when
its pane was sent `Ctrl-C`: a single interrupt opens the BEAM break menu, which stops serving while the process
lives on, still holding its HIPPO `service` lease. The abort needs a confirming `Enter`, and the lease not
releasing is the visible tell. Second, the suite's summary is easy to lose — Caddy's admin API logs a block of
JSON per candidate reload, so a `tail` of the last eighty lines shows nothing but reload chatter and the Nx
failure banner. Redirect the whole run to a file and read the summary out of it.

**Durable owner:** none; a recorded gate result.

### 2026-09-22 — A Prettier gate that never converges

The PR's `Formatting` job failed on both plan documents. Running `prettier --write` and pushing again would have
been the obvious move, and it would have failed again: this file does not have a fixed point under Prettier 3.9.
Each pass added four more spaces to the same three paragraphs, so `--write` then `--check` still reported a
violation, and a sampled MD5 looked like a cycle only because the growth was regular.

The trigger is a blank line. A delivery item's dated proof note continues the item's paragraph, and about thirty
of them do exactly that with no gap. Three had a blank line in front, which makes the note a second block inside
the list item rather than a continuation of the first — and that shape is what Prettier re-indents without ever
settling. Closing the three gaps made the file converge on the first pass and match the other thirty.

Two things are worth keeping from this. A formatter that disagrees with a file twice in a row is not necessarily
being obeyed the second time; `--write` followed by `--check` is the cheap way to notice, and it is worth running
locally before a push rather than learning it from CI. And the fix was a consistency repair that the gate found
for us: three notes were written in a shape the other thirty did not use.

**Durable owner:** the repaired documents; the rule of thumb belongs in this entry, not in a convention, because
it is Prettier's behaviour rather than this repository's.

### 2026-09-22 — Phase 9 merge and preflight

**Merge.** PR #81 landed on `origin/main` at `5b08a27f2`, carrying 34 commits. All five merge preconditions were
evidenced at the moment of merge rather than assumed: the `Quality gate` check green on the exact head, a posted
leak review naming that same head with `result: pass`, the branch `0` commits behind `main`, no open conversation,
and every surface gate green. The repository permits only rebase merges, so the proof is the commits on `main`
rather than a merge commit.

The leak review read the whole diff — 11,519 added lines across 104 files — and returned zero in all three
categories. Everything that matched a secret-shaped word was a reference rather than a value, every URL was either
the synthetic browser-suite origin or a public package address in the lockfile, and every long opaque string was a
lockfile integrity hash.

**Preflight.** Taken from the primary checkout on local `main`, reconciled to `origin/main` and reading `0 0`, with
a clean tree.

| Measure                      | Value   | Budget   |
| ---------------------------- | ------- | -------- |
| Samples at the routed origin | 12      | —        |
| Failures                     | 0       | 0        |
| p95                          | 35.9 ms | ≤ 500 ms |
| Slowest sample               | 43.1 ms | ≤ 2 s    |
| Median                       | 15.6 ms | —        |

Routed state before the release: slot `green`, readiness `ready`, revision `91e0201df`, blue free, Caddy routing on
its own port, 89 GiB disk free, HIPPO `state=normal` with no owners. The machine-local deployment inputs were
confirmed present by existence alone — the cookie, the secret key base, and both Web Push key files — because
`config/runtime.exs` requires the Web Push trio unconditionally in `:prod` and a compatibility slot fails to boot
without them exactly as an experience slot would.

**Durable owner:** none; recorded release evidence.

### 2026-09-22 — The release gate caught a checkout, not a defect

The first compatibility release attempt stopped after twelve seconds at `pre-artifact-gates` with
`errorCategory: "gate"`, `migrationState: "not-required"`, and `nextTransition: "diagnose"`. No artifact was built,
no migration ran, and the route never moved — production stayed on the previous revision throughout, which is the
shape this target promises when a gate fails and the reason gates run before the build rather than after it.

The cause: `tsc` could not resolve `happy-dom` in the primary checkout. The dependency was added on the task branch
and is in the merged lockfile, but this checkout's `node_modules` predated the merge. Every gate had been green all
day — in the _worktree_, where the install had happened. The branch was correct and the checkout was stale.

This is the same class of trap the integration convention names for `main` itself: a pull request lands from a
`worktrees/` checkout, so `origin/main` moves and the primary checkout silently does not. Reconciling the branch is
already in the convention; reconciling installed dependencies is the same problem one layer down, and nothing
reminds you because `git status` is clean either way. `npm install` after the fast-forward, before the release, is
the whole fix.

Worth saying plainly: the gate did its job. A release that had skipped straight to building would have produced an
artifact from a checkout that could not typecheck.

**Durable owner:** an idea brief proposing that the release preflight verify installed dependencies against the
lockfile, alongside the branch, tree, and revision assertions it already makes.

### 2026-09-22 — Phase 9, the compatibility release

`outcome: passed`, `migrationState: applied`, 9m39s, fifteen evidence IDs from `preflight` through `convergence`.
The routed origin now answers `ready` on slot **blue** at revision `5b08a27f2`, exactly one slot listens, and the
recorded rollback floor is green at `91e0201df`. No release worktree remains.

**The `replyTo` proof, and why it reads no production data.** The plan asks for a `curl` at the routed origin that
returns data rather than a document rejection. Document validation happens _before_ authentication, so an
anonymous session is enough to settle it and the resolver never runs:

| Probe                                          | Outcome                                                    |
| ---------------------------------------------- | ---------------------------------------------------------- |
| `replyTo { id senderDisplayName bodyPreview }` | validated, reached the resolver, refused `UNAUTHENTICATED` |
| `replyToDefinitelyNotAField { id }` (control)  | rejected: `Cannot query field ... Did you mean "replyTo"?` |

The control is the part that matters. Without it, an `UNAUTHENTICATED` answer proves only that something refused
the request; with it, the same endpoint is shown to reject an unknown field on the same type in the same request
shape. The rejection's own suggestion names `replyTo`, which is independent confirmation from the schema itself.
A first attempt with no session was refused `CSRF_REJECTED` at 403 by the pre-parse plug and proved nothing about
the field — worth recording, because that answer looks like a result and is not one.

**Responsiveness.** Post-promotion: 12 samples, zero failures, p95 278.1 ms, slowest 280.0 ms, median 17.5 ms —
inside the 500 ms and 2 s budgets, and visibly slower than the 35.9 ms pre-release baseline because the slot was
seconds old and its caches were cold.

**Correction, 2026-09-22.** No post-drain set was taken for this release. The delivery item was ticked claiming
both a post-promotion and a post-drain set; only the post-promotion one above exists. It has been unticked. The
missing set cannot be retaken — that slot was promoted and retired again by the experience release — so it is
recorded as not taken rather than reconstructed from a later measurement.

**A gap between this plan and the release procedure.** Phase 9 asks for mixed-revision safety proven _at the routed
origin_ by a browser that loads the room and sends a message. It cannot be proven there at this point in the
sequence: a compatibility release ships every feature flag off, so `BNEST_FAMILY_CHAT_ENABLED` is absent from the
routed slot and the room is not reachable at all. The previous slot carried it `true`, so the promotion also turned
a live feature off — the documented posture, and the reason the release guide says to follow _immediately_ with the
experience re-promotion.

The proof exists at the right layer instead: `A browser holding the pre-reply bundle loads the room from the new
revision` runs in `bnest-app-fe-e2e:test:e2e` against two real candidate revisions, and passed in the clean run.
That is the scenario the specification already carries an `@integration-exempt` note for, naming this exact
boundary. The plan item asked for the observation at an origin where the room is switched off; the discrepancy is
in the plan, not in the coverage.

**Durable owner:** an idea brief proposing that active-service plans state which flag posture each release stage
leaves routed, so an item cannot ask for a proof the stage's own posture forbids.

### 2026-09-22 — Phase 10, the experience release

`outcome: passed`, 5m40s, `migrationState: not-required` because it re-promotes the artifact Phase 9 already
built. The routed origin answers `ready` on slot **green** at revision `5b08a27f2` — the same revision Phase 9
routed, which is what the phase requires — with both `BNEST_FAMILY_CHAT_ENABLED` and
`BNEST_FAMILY_CHAT_REPLY_ENABLED` set `true`, exactly one slot listening, and blue retired.

**What the release itself proved, and where.**

| Evidence                     | What it observed                                                                                                                                                                                   |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `experience-candidate-proof` | `Two members prove draft, offline queue, and exact-once catch-up on the flag-enabled experience candidate`, run against the real green candidate prepared with both flags, before any route change |
| `routed-liveview`            | at the routed origin after promotion: `liveView: true`, `reconnected: true`, 10 clients across 3 groups                                                                                            |
| `promotion`, `cleanup`       | Caddy promoted, prior slot drained and retired                                                                                                                                                     |

The reconnect-without-refresh claim is therefore proven twice over: catch-up and exact-once delivery across two
contexts on the candidate, and a real reconnect at the routed origin.

**Responsiveness.** ~~Post-promotion 12 samples: zero failures, p95 278.1 ms, slowest 280.0 ms.~~ **Withdrawn
2026-09-22.** Those are Phase 9's post-promotion figures, repeated here as though a second set had been taken.
They are byte-identical to the entry above because they are the same twelve measurements. No post-promotion set
was taken for this release.

What was genuinely measured after the experience promotion: **post-drain, 12 samples, zero failures, p95 48.3 ms,
slowest 50.9 ms, median 19.3 ms**, inside both budgets. A further settled set taken during the corrections —
12 samples, zero failures, p95 154.0 ms, slowest 240.2 ms, median 17.3 ms — confirms the routed origin is still
inside budget, but it is a later observation and is not offered as the missing post-promotion set.

The error is worth naming precisely: two release stages were recorded from one measurement. Nothing about the
service was misrepresented — every sample ever taken returned 200 inside budget — but a reader counting sample
sets would have counted four where three exist, and the duplication is only visible because the figures happen to
be identical to the decimal. A measurement that is not taken has to read as not taken.

**The compatibility stage turns off features it was never releasing.** The routed slot before this work carried
`BNEST_FAMILY_CHAT_ENABLED = true`. A compatibility release ships every flag off, so promoting it disabled the
family chat room outright until the experience re-promotion — eight minutes here. That is not specific to this
plan; every two-stage release in the deployment log shows the same gap:

| Revision    | Compatibility → experience |
| ----------- | -------------------------- |
| `423164cce` | 44.6 min                   |
| `c24ecac7b` | 19.9 min                   |
| `f28196196` | 6.5 min                    |
| `91e0201df` | 16.4 min                   |
| `5b08a27f2` | 8.0 min                    |

The release guide's "immediately follow" is doing real work, and nothing enforces it. A flag that gates the feature
being released should go off in the compatibility stage; a flag that gates an unrelated feature already live has no
reason to.

**Durable owner:** an idea brief proposing that a compatibility release carry forward the flag posture of the slot
it replaces, except for the flags the release is itself introducing.

### 2026-09-22 — Two Phase 10 items this execution could not complete

Recorded as blocked rather than ticked, because neither can be honestly claimed.

**The routed pass on the real household surface.** The item asks for the feature exercised at the routed origin —
open the menu, reply, see the quote, jump back — and explicitly refuses a 2xx as proof. That needs an authenticated
session at the production origin, and this executor is not permitted to create an account or enter a password. The
nearest honest substitutes were taken and are recorded above: the flag-enabled candidate ran the two-member
browser proof before promotion, the routed origin answered a real reconnect, and the routed schema was shown to
answer `replyTo` with a control that discriminates. None of those is a person using the feature on the household
surface, and none is offered as one. **This item needs a human.**

**The rollback-floor proof.** The item asks that, against the Phase 9 revision, a browser holding the current
bundle load the room and render existing quotes. After the experience promotion the floor is the same revision with
both flags off, so the room is not reachable there at all — the proof the item describes cannot be observed at the
floor, for the same posture reason Phase 9's mixed-revision item hit. What the floor does guarantee is narrower and
was verified: it is the same artifact, already routed successfully once, and `deploy:rollback` restores it without
a rebuild.

Both are recorded in `delivery.md` as unticked with this entry named.

**Durable owner:** the idea brief above covers the posture half; the routed-pass half belongs to the user.

### 2026-09-22 — Durable-owner resolution

**Rebuilt 2026-09-22 after the execution check.** The first version of this entry said "Twenty carry a
`Durable owner:` line of their own. The remaining twenty-two are resolved by class", and neither number was
reachable. Counted against the file as it now stands, it holds **50** owner lines — 33 naming an owner, 17
recording a discard — spread across **32** of its **67** headings. The original counts were written from memory
rather than from the file, and a resolution record that cannot be counted is not a resolution record.

Counted against the file:

|                                             | Count |
| ------------------------------------------- | ----- |
| Headings at levels 2–4                      | 67    |
| Headings carrying their own owner line      | 32    |
| Owner lines naming an owner                 | 33    |
| Owner lines recording a discard (`none; …`) | 17    |

Some sections carry more than one owner line, because a long section resolves its sub-findings separately; that is
why 50 lines sit in 32 sections. The remaining 35 headings are resolved by class:

| Class                                                                                                                                                                                           | Resolution                                                                                                                                      |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Decision records `D1`–`D11`                                                                                                                                                                     | Owned by the plan. They record what was decided before implementation, and the plan is the durable artifact.                                    |
| Quality-gate audit sections — snapshot, ledger, scope exclusions, verification, verdict                                                                                                         | Owned by that gate's own record. They describe one run, not a lesson that outlives it.                                                          |
| Structural headings that only introduce the sections beneath them — the two manual-pass headings, the execution log heading, and the document's own top matter                                  | Carry nothing to route; their children carry the owners.                                                                                        |
| Narrative sub-sections of the manual passes and the Gherkin review — the matrix, the keyboard journey, the announced text, the two non-defects, the three review repairs, the Phase 0 preflight | Owned by the phase entries that contain them. Each defect they describe is fixed in the tree and named in a parent entry that carries an owner. |
| Branch-closure and pre-existing-check notes from planning                                                                                                                                       | Consumed by the plan they shaped.                                                                                                               |

Four routing failures the check found, and what happened to each:

1. **Nine owner lines named tech-doc files that do not exist** — `004-graphql-contract.md`,
   `005-composer-and-actions.md`, `003-browser-send-outbox.md`, `004-quote-and-jump.md`. This plan has
   `001`–`006` and none of those is among them; the names were invented from the topic rather than read off the
   directory. A learning routed to a file that does not exist has not reached an owner. All four now point at the
   documents that actually own their subject. `REPO`'s `internal-links` gate never caught them because they were
   written as inline code, not as links.
2. **Two governance proposals deferred by rules propagation were never raised** — that a plan's File Impact table
   must cover the release path when it introduces a runtime flag, and that the phase-checkpoint command set should
   name the typecheck target. The second sits behind one of this execution's most useful discoveries, that the
   frontend typecheck gate had been red for three phases. Both are now in
   `plans/ideas/q2-not-urgent-important/plan-and-checkpoint-contract-gaps.md`.
3. **The stale-README learning was routed to a brief that was never written.** The paragraph it describes was
   still live and still false — it said the family chat stays inactive in production, which stopped being true at
   the experience release. Fixed directly in `README.md` in this pass, which is a better owner than a brief.
4. **One conditional routing was never decided** — a note to be raised as a brief if the cross-phase RED pattern
   recurred and discarded if it did not. It did not recur in Phases 4 through 10. Discarded, recorded here.

**The deferred routings, resolved 2026-09-22.** Seventeen owner lines deferred their action to archival, and two
more deferred a raise the same way. The execution check was right that this left them unowned: archival is blocked
on grounds that have nothing to do with any of them, so "at archival" had become a place work went to wait
indefinitely.

None of them actually depended on archival, so they were done instead:

| Routing                            | Count | Disposition                                                                                             |
| ---------------------------------- | ----- | ------------------------------------------------------------------------------------------------------- |
| A correction to a tech-doc         | 15    | Made, in `001`, `002`, `003`, `004`, and `006`. Each owner line now names the date instead of the step. |
| A deferred idea brief              | 5     | Already satisfied by the seven briefs raised in this pass; each line now names the brief.               |
| The stale `README.md` paragraph    | 1     | Corrected in `README.md` directly, which owns it better than a brief would.                             |
| Conditional on a pattern recurring | 1     | It did not recur in Phases 4 through 10. Discarded.                                                     |

The fifteenth tech-doc correction was not in the check's count of fourteen, and neither was it in mine: its owner
line ended on one line and its `Raised at archival` on the next, so a line-wise scan found neither the promise nor
its deadline. It is the File Impact table's missing release path — the one whose absence would have promoted a
revision that reads a flag it is never given.

What the corrections changed is worth separating from how many there were. Three were straightforward additions of
something learned after the document was written. The other twelve **contradicted** what the document said: that
the `BEFORE DELETE` trigger is what makes a dangling reference unreachable (the foreign key gets there first), that
focus returns to the message on every menu close path (not the one path that matters), that the strip shows the
server's preview (not for a target chosen on screen), that the quote card is a plain `button` (it is a tab stop per
message that way), and a File Impact table listing thirteen test files where the plan touched forty-four. A
tech-doc that is wrong is worse than one that is incomplete, because the next reader has no reason to check it.

### 2026-09-22 — The execution check, and what it found in my own record

Terminal verdict: **BLOCKED**. Archival is not permitted, and the plan stays in `plans/in-progress/`.

Two blocking classes. AC-FCR-13's rollback-floor scenario has no evidence anywhere — `005-specification-changes.md`
deliberately keeps it out of `specs/` and names exactly one verifier, the Phase 10 proof that is itself blocked, so
no automated layer owns it and no substitute was offered. And the knowledge-capture step's central claim did not
survive counting, which is the entry rebuilt above.

Beneath those, the check found things worth more than the verdict. The ones that were my errors, and are now
corrected in place:

| Finding                                      | What it was                                                                                                                                                                                                                                                                                        |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Duplicated sample sets                       | Phase 9 and Phase 10 both reported p95 278.1 ms, slowest 280.0 ms — the same twelve measurements recorded as two release stages. Phase 9's post-drain set was never taken, and its item was ticked claiming it.                                                                                    |
| A coverage threshold that does not exist     | The command table asserted `FE_UNIT` carries a 99% line threshold and that a phase leaving a module uncovered fails its checkpoint. `test:unit:fe` runs a bare `vitest run`, and the config says coverage thresholds are intentionally not enforced. Three of the four modules named are frontend. |
| A status line that denied the work happened  | `delivery.md` still opened "Pending. No product implementation, dependency change… has started" after two production releases.                                                                                                                                                                     |
| A dependency authority that was contradicted | The plan's README said no dependency is added; `happy-dom` was added, and the decision was recorded everywhere except there.                                                                                                                                                                       |
| Two dispositions under the wrong headings    | My own tick script looked for the next `- [` and ran past a section heading when its item was the last in the section, so a recovery trigger read as having no disposition at all.                                                                                                                 |
| A migration proof that was never taken       | The item required the column present and existing messages unchanged; only candidate health had been recorded.                                                                                                                                                                                     |

That last one was checkable all along — read-only inspection of production schemas is explicitly permitted — so it
is now taken rather than amended away. Against the routed production database: `reply_to_message_id` is present and
nullable with no default; the partial index exists as
`CREATE INDEX family_chat_messages_reply_to ON family_chat_messages(reply_to_message_id) WHERE reply_to_message_id IS NOT NULL`;
and of 123 existing messages, 123 carry `NULL` and none carries a reply. Recorded by shape; no message content was
read.

The check also found that the Phase 9 substitute evidence is filed under the wrong scenario. The browser scenario
it names is real, bound, and green, but it promotes a candidate with the reply flag _off_ against a browser served
from a primary that pins the flag _on_ — the inverse direction — its `When` re-fetches the page rather than holding
a stale bundle, and both slots build from one source tree with a synthetic per-port revision identity. So
"two real candidate revisions" overstated it: one build, one bundle, two flag postures. The claim has been
corrected where it appears.

What I would take from this. Every one of these is a claim I wrote and did not re-read against the artifact it
described — a number from memory, a threshold assumed from a sibling suite, a status line never revisited, a script
whose output I checked for the thing it added and not for where it landed. The suites, the gates, and the releases
were all green throughout, and none of them could have caught any of it. A record is not evidence because it is
detailed; it is evidence when someone has checked it against the thing.

**Durable owner:** the corrections themselves, plus
`plans/ideas/q2-not-urgent-important/plan-and-checkpoint-contract-gaps.md` for the two governance proposals.
