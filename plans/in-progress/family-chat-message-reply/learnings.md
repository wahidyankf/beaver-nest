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

**Durable owner:** the file list in `tech-docs/006-file-impact-and-release.md`, corrected at archival.

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

**Durable owner:** `tech-docs/001-data-model-and-migration.md`'s dangling-reference section, corrected at archival to
state both guards and which one fires first.

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

**Durable owner:** `tech-docs/004-graphql-contract.md`, at archival — the quote's server-side shape stated
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

**Durable owner:** `tech-docs/001-data-model-and-migration.md` and `tech-docs/004-graphql-contract.md`, at archival.

**Deviation — the boundary tests run in process.** `delivery.md` asked for "a loopback listener the test starts,
owns, and stops". `repo-governance/development/api-testing.md` permits either that or in-process, and the rest of
this suite is in-process. `test/integration/bnest_app_web/family_chat_graphql_test.exs` runs the genuine endpoint,
router, session/CSRF plugs, and `Absinthe.Plug`, asserting status, content type, variable coercion, and the
`data`/`errors` envelope. Binding a second listener beside a 24/7 service buys nothing the `bnest-app-be-e2e`
project does not already prove at the real socket.

**Durable owner:** `tech-docs/006-file-impact-and-release.md`, corrected at archival.
