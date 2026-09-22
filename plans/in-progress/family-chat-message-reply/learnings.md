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

_Empty. No execution has started. Entries are appended dated and sanitized as `delivery.md` is worked through, and
every one is resolved to a durable owner or discarded with a reason before archival._
