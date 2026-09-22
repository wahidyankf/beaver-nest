# Specification Changes

What this plan makes durable in `specs/`, and what stays inside the plan. Executable specifications are the as-built
truth; this document is the proposal, and `specs/` is only updated during execution with the result.

## Which PRD Outcomes Become Durable Contracts

PRD Gherkin is the plan's acceptance language. It is not an automatic request to copy every scenario into `specs/`.

| PRD criterion                                       | Disposition | Target                                                              |
| --------------------------------------------------- | ----------- | ------------------------------------------------------------------- |
| AC-FCR-01 menu entry points                         | contract    | `app-fe/behaviours/family_chat.feature`                             |
| AC-FCR-02 menu contents and availability            | contract    | `app-fe/behaviours/family_chat.feature`                             |
| AC-FCR-03 composer reply strip                      | contract    | `app-fe/behaviours/family_chat.feature`                             |
| AC-FCR-04 a reply commits its link                  | contract    | `app-be/behaviours/family_chat_graphql.feature`                     |
| AC-FCR-05 impossible targets refused                | contract    | `app-be/behaviours/family_chat_graphql.feature`                     |
| AC-FCR-06 every arrival path renders it             | contract    | both `family_chat_graphql.feature` and `app-fe/family_chat.feature` |
| AC-FCR-07 replies stay flat                         | contract    | `app-be/behaviours/family_chat_graphql.feature`                     |
| AC-FCR-08 bounded jump                              | contract    | `app-fe/behaviours/family_chat.feature`                             |
| AC-FCR-09 offline replies                           | contract    | `app-fe/behaviours/family_chat.feature`                             |
| AC-FCR-10 keyboard traversal and quote announcement | contract    | `app-fe/behaviours/family_chat.feature`                             |
| AC-FCR-11 additive migration                        | contract    | `app-be/behaviours/family_chat_operations.feature`                  |
| AC-FCR-12 notifications unchanged                   | contract    | `app-be/behaviours/family_chat_operations.feature`                  |
| AC-FCR-13 mixed-revision safety                     | contract    | `app-fe/behaviours/family_chat.feature`                             |
| AC-FCR-13 rollback floor                            | contract    | `app-fe/behaviours/family_chat.feature`                             |

**Corrected 2026-09-22 (D12).** AC-FCR-13's rollback-floor proof was listed below as plan-only, on the grounds
that it "asserts a property of a release procedure at a moment in time, not of the deployed system", so encoding it
would create "a test with no runnable subject between releases". That reasoning does not survive contact with this
plan. Phase 10 released _the same reviewed revision_ as Phase 9 with `BNEST_FAMILY_CHAT_REPLY_ENABLED` flipped on,
so the floor and the experience revision are one build differing by one flag — a posture the browser suite already
stands up for its experience-release scenarios. The subject is runnable, it has been made runnable, and the
scenario is now a contract row above.

It is the strongest of the three release scenarios rather than the weakest, because it is the only one that keeps
its bundle. Its sibling, `A browser holding the pre-reply bundle loads the room from the new revision`, navigates
in its `When`, so the browser is served fresh by whichever slot is routed and never actually holds the previous
revision's bundle. The rollback-floor scenario never navigates: the room is loaded from a flag-on slot, the route
is moved under it, and the floor is then made to answer a reply committed after the rollback — which the browser
can only render with the reply-aware document it still holds.

### Plan-only outcomes, with their reasons and verification tasks

| PRD criterion                                  | Why it stays plan-only                                                                                                                                                                                                                                                                                                                              | Verified by                                                             |
| ---------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| AC-FCR-10's screen-reader announcement wording | No WAI-ARIA guidance exists for announcing a quoted reply, so the exact sentence is this plan's design decision, not a standing system property. A Gherkin scenario asserting one authored sentence would freeze a wording that the first real screen-reader pass may correct. The _presence_ of an accessible name is a contract; its text is not. | Phase 8's screen-reader walkthrough, recorded in `learnings.md`         |
| AC-FCR-10's no-horizontal-scroll matrix        | Rendered geometry needs a real layout engine at three viewports. The existing corpus already carries this property for the room as a whole; repeating it per feature would duplicate a check that cannot fail differently here.                                                                                                                     | Phase 8's manual UI matrix, plus the existing structural overflow check |
| AC-FCR-11's refusal to reverse the migration   | `specs/` describes the running system's observable behaviour. A migration's down path is never executed by the running system, so it is not a system property.                                                                                                                                                                                      | Phase 2's `INTEGRATION` scenarios in `family_chat_migration_test.exs`   |
| AC-FCR-14 routed responsiveness                | Release evidence against the live origin, not a behaviour the corpus can own. Already handled as delivery evidence by the repository's release convention.                                                                                                                                                                                          | Phases 0, 9, and 10's 12-sample sets                                    |

## `[E]` `specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature`

```diff
  Rule: Idempotent message send
    Scenario: A member sends a durable message
    Scenario: Retrying the same client message ID returns the original commit
+   Scenario: Retrying a client message ID with a different reply target returns the first commit

+ Rule: Replying to a message
+   Scenario: A member sends a reply and the commit carries its quote
+   Scenario: A message sent with no reply target has no quote
+   Scenario: A quote is shortened to a bounded preview
+   Scenario Outline: A reply target the server cannot honour is rejected before commit
+   Scenario: A reply to a reply quotes only its immediate parent

  Rule: Sender display name reflects the current account, not a historical snapshot
    Scenario: Re-querying an older message shows the sender's current display name
+   Scenario: A quoted sender name follows the current account too

  Rule: Post-commit subscription and catch-up
    Scenario: A subscriber receives exactly one event per committed message
+   Scenario: A subscribed reply arrives carrying its quote
    Scenario: A subscriber catches up a missed event through afterId
+   Scenario: A reply caught up through afterId carries its quote
```

- **New scenarios in detail.**
  - _A member sends a reply and the commit carries its quote._ An authenticated member, given a committed message in
    `ruang-keluarga`, sends a message naming that message's server ID; the mutation returns one committed message
    whose quote names that ID, its sender, and a preview of its body.
  - _A message sent with no reply target has no quote._ The same member sends without a target; the returned message
    has no quote. This exists so the field's absence is asserted rather than assumed.
  - _A quote is shortened to a bounded preview._ Given an original of 400 graphemes, the quote returns at most 160
    followed by an ellipsis. Proves truncation is a server property, not a rendering accident.
  - _A reply target the server cannot honour is rejected before commit._ Outline over a non-existent ID, an ID in
    another room, and a non-integer; each returns a validation error, stores nothing, and publishes nothing.
  - _A reply to a reply quotes only its immediate parent._ Given A, and B replying to A, a reply to B carries a quote
    of B that carries no quote of its own. This is the flatness contract at the boundary where it is observable.
  - _A quoted sender name follows the current account too._ Given a reply to a message committed under an earlier
    display name, changing the account's name changes the name shown in the quote. Pairs with the existing scenario
    directly above it so the two can never drift apart.
  - _A subscribed reply arrives carrying its quote_ and _A reply caught up through afterId carries its quote._ The
    same reply, over the two paths that are not the initial query. These are separate scenarios because they are
    served by different code paths and have failed independently in this room's history.
  - _Retrying a client message ID with a different reply target returns the first commit._ Names the first-write-wins
    consequence of leaving the reply target out of the idempotency key, so the behaviour is a decision on the record.
- `= Preserve` — every existing scenario in this file is unchanged. `A member sends a durable message`,
  `Retrying the same client message ID returns the original commit`, and
  `Re-querying an older message shows the sender's current display name` all remain true because the mutation
  argument and the message field are both optional and additive.
- `→ Bindings` — `apps/bnest-app/test/behaviour/steps/family_chat_backend_steps.exs` `[E]`;
  `apps/bnest-app-be-e2e/tests/steps/family-chat.steps.ts` `[E]`;
  `apps/bnest-app-be-e2e/tests/support/subscriptions.ts` `[E]` for the two subscription scenarios.
- `✓ Proof` — `BEHAVIOUR` and `BE_E2E_COVERAGE` prove the changed corpus. The focused runtime journey is: two
  `test-user-` sessions subscribe, the first replies to the second's message, and the second observes the quote on
  the subscription and again after a reconnect through `afterId`.

## `[E]` `specs/apps/bnest/app-be/behaviours/family_chat_operations.feature`

```diff
  Rule: Seed and release compatibility
    Scenario: A fresh migration seeds Ruang Keluarga ready for posting
    Scenario: An old release ignores the additive family chat schema
+   Scenario: An old release ignores the additive reply column

  Rule: Atomic message and delivery commit
    Scenario: Sending a message commits the message and every delivery row atomically
+   Scenario: A reply commits exactly the delivery rows an ordinary message does
```

- **New scenarios in detail.**
  - _An old release ignores the additive reply column._ Given the column exists, a revision built before it reads and
    writes every other column unchanged. This is the scenario the compatibility release depends on, stated as a
    system property rather than left as a release-time hope. It is deliberately a sibling of the existing
    additive-schema scenario rather than an edit to it, so the original claim keeps its own meaning.
  - _A reply commits exactly the delivery rows an ordinary message does._ Given one other active subscription, a
    reply produces exactly one pending delivery row. Proves AC-FCR-12's real content: that replying changed nothing
    about notification bookkeeping.
- `= Preserve` — every existing scenario is unchanged, including the whole push retry, retention, purge, scheduler,
  capacity, and restore corpus. Nothing in this plan touches them.
- `→ Bindings` — `apps/bnest-app/test/behaviour/steps/family_chat_backend_steps.exs` `[E]`.
- `✓ Proof` — `BEHAVIOUR`. The focused runtime journey is a reply committed with one other subscription active,
  inspected for exactly one pending delivery row.

## `[E]` `specs/apps/bnest/app-fe/behaviours/family_chat.feature`

```diff
+ Rule: Message actions
+   Scenario Outline: A member opens the message action menu
+   Scenario: Closing the menu returns focus to the message it came from
+   Scenario: A press that turns into a scroll does not open the menu
+   Scenario: Only one menu is open at a time
+   Scenario: A committed message offers both actions
+   Scenario Outline: A message that is not yet committed cannot be replied to
+   Scenario: A system message can be replied to like any other
+   Scenario: Copying a message puts its text on the clipboard
+   Scenario: A refused clipboard is reported, not swallowed

+ Rule: Composing a reply
+   Scenario: Choosing Reply puts the target above the message input
+   Scenario: A long quoted message is shortened in the strip
+   Scenario Outline: The member abandons the reply
+   Scenario: The reply target does not survive a reload
+   Scenario: Sending clears the reply target

+ Rule: Reading a reply
+   Scenario Outline: A reply carries its quote through each arrival path
+   Scenario: A reply to a reply shows only one level of quote
+   Scenario: The original is already on screen
+   Scenario: The original is above the loaded window
+   Scenario: The original is beyond the jump bound
+   Scenario: Highlighting respects reduced motion

+ Rule: Keyboard reach of the message history
+   Scenario: The whole journey works from the keyboard alone
+   Scenario: Tab does not walk through every message in the room
+   Scenario: A quote exposes an accessible name naming its sender

  Rule: Resume, online reaction, backoff, and seven-day expiry
    Scenario: A queued message survives a real browser reload while offline
+   Scenario: An offline reply queues with its target
+   Scenario: A queued reply survives closing the app
+   Scenario: A queued reply commits with its link on reconnect
+   Scenario: A queued record written before this feature still sends

  Rule: Reconnect across Caddy promotion
    Scenario: A connected client reconnects to the promoted slot without a page reload
+   Scenario: A browser holding the pre-reply bundle loads the room from the new revision
```

<details>
<summary>Layer ownership for the new frontend scenarios</summary>

Scenarios proven at `FE_UNIT` rather than `FE_E2E` each carry an `@fe-vitest-unit` tag and an explicit
`# Exemption(e2e):` comment naming the alternative target and scenario, matching this file's existing convention:

- **`FE_UNIT`, exempted from E2E** — the hold-timer and movement-tolerance decisions, the disabled-Reply rule per
  delivery state, clipboard success and refusal, the reply-strip lifecycle, the shortened strip preview, the bounded
  page-loading arithmetic of the jump, and all four offline-queue scenarios. Each is a decision the existing
  browserless harness already exercises for its neighbours, and none of them depends on layout, focus, or a real
  clipboard permission prompt.
- **`FE_E2E`, no exemption** — opening the menu by each of the four real triggers, focus returning to the message on
  close, only one menu open at a time, the keyboard-only end-to-end journey, Tab entering the history exactly once,
  the accessible name on a quote, the four arrival paths rendering the quote, jumping when loaded and when not, the
  reduced-motion variant, and the pre-reply-bundle compatibility scenario. These need a real focus engine, a real
  layout, real pointer events, or a real second revision, and a unit-layer proxy for any of them would be a check
  that can be green while the room is unusable.

</details>

- `= Preserve` — every existing scenario is unchanged. The route, send-status, bounded-outbox, auth-expiry,
  visibility-resume, subscription-handshake, and experience-release rules are untouched;
  `A queued message survives a real browser reload while offline` still holds because the outbox record gains an
  optional field rather than a required one.
- `→ Bindings` — `apps/bnest-app-fe-e2e/tests/steps/family-chat-reply.steps.ts` `[N]`;
  `apps/bnest-app-fe-e2e/tests/support/family-chat-reply.ts` `[N]`;
  `apps/bnest-app-fe-e2e/tests/support/family-chat-composer.ts` `[E]`;
  `apps/bnest-app/assets/test/unit/family_chat/message_actions.test.ts` `[N]`;
  `apps/bnest-app/assets/test/unit/family_chat/composer.test.ts` `[E]`;
  `apps/bnest-app/assets/test/unit/family_chat/outbox.test.ts` `[E]`;
  `apps/bnest-app/assets/test/unit/family_chat/history.test.ts` `[E]`.
- `✓ Proof` — `FE_UNIT` and `FE_E2E_COVERAGE` prove the changed corpus. The focused runtime journey is: a member
  opens the room with the keyboard only, arrows to a message, presses Enter, chooses Reply, types, sends, then
  activates the quote on the sent reply and lands on the original.

## C4 Changes

### `[E]` `specs/apps/bnest/app-be/architecture.md`

- **Component View, prose beneath the diagram.** The paragraph that enumerates the family chat GraphQL surface
  (`family_chat_rooms`, `family_chat_room`, `family_chat_messages`, `send_family_chat_message`,
  `family_chat_message_committed`) gains the mutation's optional `reply_to_message_id` argument and the message's
  `reply_to` quote field. **Why:** that paragraph is the canonical statement of this component's interface, and an
  interface that grew an argument without it becoming stated is exactly the drift `specs/` exists to prevent.
- **Component View, the `familychat -->|Rooms and messages| repository` relationship.** Unchanged in shape; the
  constraint list records that quote resolution is a read-time derivation inside the `familychat` component, never a
  stored copy and never a resolver-layer query. **Why:** it is the one architectural property of this feature a
  future change could silently violate.
- **Container View — no change, deliberately.** The container diagram models one `Local SQLite database` data-store
  node and does not enumerate tables or columns, so an additive column changes nothing it states. Recorded here so
  the absence reads as checked rather than forgotten.
- **Behaviour Traceability — no change, deliberately.** That section is prose declaring which adapters implement the
  recursive corpus; it names no individual scenario, so new scenarios need no entry.

### `[E]` `specs/apps/bnest/app-fe/architecture.md`

- **Component View, the `family_chat` node and its prose.** The browser-owned module inventory
  (`assets/js/family_chat/*`) gains the action menu, reply-target, and jump modules, and the route's shell
  description gains the reply flag it passes to the browser. **Why:** the prose already names this module set as the
  boundary of browser-owned behaviour, and three new modules land inside it.
- **Architectural Constraints.** Two constraints are added beside the existing family-chat bullets: the message
  history exposes exactly one tab stop with arrow-key movement between messages; and a quote is always derived from
  the referenced message at read time, never cached in the browser or the service worker. **Why:** the first changes
  a property of an existing surface rather than adding one, and the second is the frontend half of the
  no-snapshot decision, which the service-worker caching constraint directly above it would otherwise appear to
  contradict.
- **Container View — no change, deliberately.** The service worker keeps the same responsibilities; the reply target
  rides inside the existing outbox record rather than creating a new browser-owned store.

## Ordering

Specifications and C4 are updated **before** implementation, in the same change, in Phase 1 of
[`delivery.md`](../delivery.md). `specs/` then records the final as-built result: if implementation diverges from
what this document proposes, `specs/` follows the implementation and the divergence is recorded in `learnings.md`.
Every changed Gherkin file and its bindings go through the manual
[gherkin-implementation-review](../../../../repo-governance/workflows/gherkin-implementation-review.md) in Phase 8.
