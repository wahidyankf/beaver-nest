# Product Requirements

Product copy in this plan is written in Bahasa Indonesia because the household using Bnest speaks it and the current learning screen already does. Every explanation, identifier, scenario, and specification around that copy stays in English under the [language convention](../../../repo-governance/conventions/language.md).

## Personas

- **Child learner (`children`):** wants short, clearly finishable sessions, immediate feedback, a visible sense of moving forward, and coins that accumulate toward something.
- **Parent (`parents`):** wants to add a subject the child needs this week, verify recitation in person, and see whether a child is actually returning.
- **Maintainer (`admin`):** wants the engine, its API, and its migration to be inspectable and reversible without stopping the service.

## User Stories

- As a child, I open one course, see which topic I am on, and start the next mission without choosing anything.
- As a child, I answer a question and immediately know whether I was right and what happens next.
- As a child, I see what is due for review today and can clear it in one short session.
- As a child, I see my coins go up when I master something, and the same mission never pays me twice.
- As a child, I do not repeat a mission I already mastered just because it also appears in another course.
- As a parent, I see which recitations are waiting for me and approve or reject one for a specific child.
- As a parent, I add a new subject by committing content files, and it appears after a sync without an application change.
- As a maintainer, I can query the same facts through GraphQL that the UI renders, and use them to verify a browser journey.
- As a maintainer, I can attach a new feature to `mission.mastered` without editing the mastery path.
- As a maintainer, I can drop every read model and rebuild it from the log when a projection is wrong, instead of writing a data migration.

## Acceptance Criteria

### AC-01 — Content sync

```gherkin
Scenario: Authored content enters the log exactly once
  Given a learning corpus of courses, topics, and missions in the repository
  When the content sync runs twice against the same corpus
  Then the first run appends one defining event per item
  And the second run appends nothing and changes no projected row
  And every projected mission records the checksum of its defining event

Scenario: An invalid corpus never reaches a learner
  Given one mission in the corpus declares a kind its payload does not satisfy
  When the content sync runs
  Then the sync rejects the whole corpus with a value-free reason
  And no event is appended
  And the previously projected content continues to serve learners

Scenario: Removing content retires it instead of deleting it
  Given a learner has attempted a mission
  And that mission is removed from the repository corpus
  When the content sync runs
  Then a retirement event is appended and the projected mission is marked retired
  And the learner's progress and attempt history remain readable
  And the mission's defining event remains in the log
```

### AC-02 — Reusable missions, single mastery

```gherkin
Scenario: A mastered mission is not repeated in another course
  Given mission "shared/tajwid/idgham" belongs to a topic in course "quran-dasar" and a topic in course "tahsin"
  And the learner has mastered that mission through "quran-dasar"
  When the learner opens "tahsin" at "/learn/tahsin" on desktop, tablet, and mobile
  Then that mission is shown as already mastered
  And the runner offers the next unmastered mission instead
```

### AC-03 — Mission kinds and pass rules

```gherkin
Scenario Outline: Each mission kind is completed by its declared pass rule
  Given a mission of kind "<kind>" with pass rule "<rule>"
  When the learner satisfies "<rule>" at "/learn/m/<mission>"
  Then the mission state becomes mastered
  And an attempt row records the outcome and the mission content checksum

  Examples:
    | kind            | rule            |
    | reading         | acknowledge     |
    | video           | acknowledge     |
    | multiple_choice | streak_two      |
    | short_text      | first_correct   |
    | flashcard       | streak_two      |
    | parent_check    | parent_verified |

Scenario: An unsatisfied pass rule keeps the mission open
  Given a multiple-choice mission with pass rule "streak_two"
  And the learner has answered it correctly once
  When the learner answers it incorrectly
  Then the mission is not mastered
  And the correct streak returns to zero
```

### AC-04 — Spaced review

```gherkin
Scenario: Review surfaces only what is due for this learner
  Given the learner mastered two missions with different review schedules
  And only one of them is due
  When the learner opens "/learn/review" on desktop, tablet, and mobile
  Then only the due mission is offered
  And an empty due list renders the finished state, not an error

Scenario: A wrong answer during review reschedules the mission sooner
  Given a mastered mission is due for review
  When the learner answers it incorrectly
  Then its review step decreases
  And its next review time moves earlier than the previous interval
```

### AC-05 — Parent verification

```gherkin
Scenario: A parent verifies an in-person mission for a child
  Given a child submitted "hafalan/juz-30/an-naba" for verification
  When a user holding "parents" opens "/learn/verify" and approves that submission
  Then the attempt records the approving user and the decision time
  And the mission becomes mastered for that child

Scenario: A child cannot verify their own in-person mission
  Given a child submitted an in-person mission for verification
  When that same child attempts to record the verification
  Then Bnest refuses the operation
  And the mission remains pending verification

Scenario: A child cannot open the verification queue
  Given a user holding only "children" is logged in
  When the user opens "/learn/verify"
  Then Bnest denies the route
  And no other learner's name, progress, or submission is revealed
```

### AC-06 — Coin earning

```gherkin
Scenario: First mastery credits the mission reward once
  Given mission "sifat-allah/wujud/wajib-meaning" awards 5 coins
  And the learner has not mastered it
  When the learner masters it
  Then the learner's balance increases by 5
  And the ledger holds exactly one earning entry for that learner and mission

Scenario: Repeating a mastered mission credits nothing
  Given the learner already mastered a coin-bearing mission
  When the learner answers it again correctly, including after a reconnect or a retried submission
  Then the balance does not change
  And no second earning entry exists
```

### AC-07 — Event log as the source of truth

```gherkin
Scenario: Every state change exists first as an event
  Given a learner masters a coin-bearing mission
  When the transaction commits
  Then the learner's stream holds a "mission.mastered" and a "coins.earned" event
  And every projected row for that change traces to one of those events
  And a failed transaction leaves neither the events nor the projected rows

Scenario: Content changes are recorded as events
  Given a mission's text is changed in the authored corpus
  When the content sync runs
  Then a new "mission.defined" event is appended to the content stream
  And an attempt recorded before the change still refers to the earlier content checksum

Scenario: A sync with no difference appends nothing
  Given the authored corpus matches the projected content state
  When the content sync runs
  Then no event is appended
  And no projected row changes

Scenario: The log cannot be edited or deleted
  When any writer attempts to update or delete a stored event
  Then the database refuses the operation
  And the log is unchanged

Scenario: Concurrent writers cannot both append the same stream position
  Given two commands load the same learner state at the same stream version
  When both attempt to append
  Then exactly one append succeeds
  And the other reloads, re-decides, and appends after it
```

### AC-07b — Rebuild from the log

```gherkin
Scenario: Projections rebuild byte-identically
  Given a learner has answered, mastered, reviewed, earned coins, and had a submission verified
  And content has been defined, reordered, and retired
  When every projection is dropped and the log is replayed from the first event
  Then every projection table matches its checksum before the rebuild
  And no value is taken from the system clock during the replay

Scenario: A subscriber resumes where it stopped
  Given a durable subscriber stopped part-way through the log
  When it starts again
  Then it continues from the event it had not finished
  And handling the same event twice changes no stored value
```

### AC-08 — API scope and authorization

```gherkin
Scenario: A learner reads only their own progress
  Given a user holding only "children" is authenticated
  When the user queries another learner's progress through "/api/graphql"
  Then the request is denied with a value-free error
  And no progress, coin balance, or display name of the other learner is returned

Scenario: The API cannot change content
  Given an authenticated user of any role
  When the user attempts any course, topic, or mission mutation
  Then the operation does not exist in the schema

Scenario: The explorer is unavailable outside development
  Given "dev_routes" is disabled
  When a request opens the GraphiQL path
  Then Bnest does not serve an explorer
  And "/api/graphql" still answers an authenticated operation

Scenario: The endpoint refuses an unauthenticated request
  Given no session cookie is present
  When a request posts a valid query to "/api/graphql"
  Then Bnest denies it
  And reveals no schema detail in the response body
```

### AC-09 — Learner interface

```gherkin
Scenario: A child moves from course to mission without deciding anything
  Given a learner has an unfinished course
  When the learner opens "/learn" on desktop, tablet, and mobile
  Then the course shows its topic trail and progress
  And one primary action continues the next unmastered mission

Scenario: An answered question gives immediate feedback and advances
  Given the learner is on a multiple-choice mission at "/learn/m/:mission_id"
  When the learner selects an answer
  Then every choice locks and the outcome is announced in text and shape, not colour alone
  And the runner advances without another tap after the feedback pause

Scenario Outline: Every runner state renders on every supported viewport
  Given the runner is in the "<state>" state
  When the learner views it on desktop, tablet, and mobile
  Then the state is fully readable at 200% zoom, reachable by keyboard, and honours reduced motion

  Examples:
    | state              |
    | loading            |
    | question           |
    | answered-correct   |
    | answered-incorrect |
    | awaiting-parent    |
    | topic-complete     |
    | empty-review       |
    | error              |
```

### AC-10 — Sifat Allah parity on the generic runner

```gherkin
Scenario: The existing revision corpus passes against the generic runner
  Given "specs/apps/bnest/app/behaviours/sifat_allah.feature" is unchanged except for its route
  When the corpus runs against the generic mission runner
  Then every scenario passes, including automatic advance, locked answers, browser Back to the mission dashboard, immediate queue movement, and the exam skipping learned questions
  And no scenario is deleted or weakened to make the runner pass
```

### AC-11 — Sifat Allah progress migration

```gherkin
Scenario: Every learner's revision state survives the cutover
  Given stored "sifat-allah-progress" records exist for household learners
  When the learning migration runs
  Then each learned, mastered, and difficult entry becomes an equivalent progress row
  And each learner's mastered and difficult counts match their pre-migration values

Scenario: The engine is authoritative with the previous source unavailable
  Given the migration has been verified
  When a fresh process starts in an isolated fixture with the previous progress source removed
  Then the learner can open the mission, answer, master, and review through the product journey
  And the engine fails closed instead of falling back to the previous source

Scenario: A blocked source stops the cutover without data loss
  Given one stored progress record is malformed or changed after inventory
  When the migration verifies
  Then the engine does not become authoritative
  And the source record remains unchanged with a value-free retry category
```

### AC-12 — Active-service rollout

```gherkin
Scenario: The routed household keeps working across the learning rollout
  Given the current Caddy route is healthy and a connected learner is mid-mission
  When a revision-compatible candidate is promoted
  Then the routed revision and readiness are proven at the exact origin
  And the LiveView reconnects without a manual refresh and keeps the current mission
  And routed sampling records zero failures, p95 at or below 500 ms, and every sample at or below 2 seconds
```

## UI States

The mission runner owns one state machine: `loading`, `question`, `answered-correct`, `answered-incorrect`, `awaiting-parent`, `topic-complete`, `empty-review`, and `error`. Course and topic screens own `loading`, `list`, `empty`, and `error`. The verification queue owns `loading`, `pending-list`, `empty`, `decided`, and `error`.

One primary verb per state, in product copy: **Mulai**, **Lanjut**, **Periksa**, **Coba lagi**, **Setor ke orang tua**, **Setuju**, **Belum**, and **Selesai**. Outcome is carried by text, icon shape, and position as well as colour. Progress and coin changes are announced through a polite live region; a blocked or failed action uses an alert that takes focus. Celebration and advance animation respect `prefers-reduced-motion` by collapsing to an instant state change with the same text.

## Product Risks

- **A generic runner feels colder than the screen it replaces.** Control: the trail, immediate feedback, automatic advance, and celebration are acceptance criteria (AC-09, AC-10), not decoration, and the existing corpus is the bar.
- **Coins turn into pressure rather than motivation.** Control: this plan has no streak, no loss, no expiry, and no comparison between children; the balance only grows (BRD non-goals).
- **A child sees a sibling's record.** Control: per-learner authorization is enforced at the API and the route, and denial reveals nothing (AC-05, AC-08).
- **A parent is the bottleneck for `parent_check`.** Control: pending submissions are visible in one queue with the child and mission named, and a pending mission never blocks other missions in the topic.
- **Review becomes an unbounded chore.** Control: the review screen offers only what is due and renders a finished state when the queue is empty (AC-04).
- **Content authoring is invisible to a non-technical parent.** Control: this is accepted and stated as a non-goal; the authoring guide in the project README is the mitigation, and an in-app editor is deliberately deferred.

## Scope Boundaries

In scope: the event log and its projections, the content sync command, mission kinds, mastery and review, coin earning, projection rebuild, GraphQL read and progress mutations, learner and parent routes, the generic runner, the Sifat Allah cutover and progress migration, specifications, tests, and rollout.

Out of scope here: coin redemption, content authoring UI, cross-topic prerequisites, media hosting, public API access, real-user testing, deletion of retired records, and any change to chat, theme, identity, storage, or backup behaviour.
