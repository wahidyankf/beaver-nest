# Specification Delta and Adapter Map

## Boundary Decision

Bn​est remains one production application, `bnest-app`, but its observable contracts divide into two canonical surfaces:

- `specs/apps/bnest/app-be/` owns GraphQL, authentication/authorization at the server boundary, SQLite, Scheduler,
  Backup, push delivery, and internal services.
- `specs/apps/bnest/app-fe/` owns routes and rendered UI, IndexedDB, connection status, reconnect orchestration, push UX,
  responsive behavior, and accessibility.
- `specs/apps/bnest/README.md` is the aggregate map and declares `bnest-app` as owner of both surfaces.

Each scenario has exactly one canonical owner. Cross-boundary journeys are decomposed at an observable contract boundary,
not copied into both roots. Backend E2E may invoke GraphQL and then inspect its response/side effect; frontend E2E may
drive the browser and observe UI, but it does not restate backend-only guarantees.

This takes the separated frontend/backend corpus principle from the
[OSE behavior map](https://raw.githubusercontent.com/wahidyankf/ose-public/main/specs/apps/ose/www/behaviours/README.md)
and explicit corpus ownership from its
[backend coverage config](https://raw.githubusercontent.com/wahidyankf/ose-public/main/apps/ose-www-be-e2e/behaviour-coverage.json).
Bn​est keeps its own namespace, aggregate owner, adapters, and enforcement.

## Governance Change Before Corpus Movement

The current BDD rule requires every application adapter to consume one identical corpus. Before any spec move, apply
`repo-governance/workflows/rules-propagation.md` with a frozen ledger for this exact rule change:

```diff
- An application has one recursive corpus shared by unit, integration, and one E2E project.
+ One application may declare boundary-specific canonical corpus roots.
+ The production owner aggregates every root and runs all applicable unit/integration adapters.
+ Each dedicated E2E project declares exactly one owned root and proves its complete adapter coverage.
+ Every scenario has one canonical root; cross-root duplication is a failure.
```

Known point of use: `[E] repo-governance/development/behaviour-driven-development.md`. The propagation ledger decides
whether `README.md`, quality maps, hooks, or validators also require minimum edits. The terminal result must be
`PASS_CHANGED` and the repository gate must pass before the existing corpus moves. Do not edit unrelated governance.

## Canonical Specification Tree

### Aggregate

- `[N] specs/apps/bnest/README.md` — production owner, BE/FE maps, adapter/target ownership, and no-duplication rule.
- `[D] specs/apps/bnest/app/README.md` — replaced by the aggregate and two surface maps.
- `[D] specs/apps/bnest/app/architecture.md` — split into the two surface-specific as-built models.
- `[D] specs/apps/bnest/app/behaviours/README.md` — replaced by boundary maps.

### Backend surface

- `[N] specs/apps/bnest/app-be/README.md`
- `[N] specs/apps/bnest/app-be/architecture.md`
- `[N] specs/apps/bnest/app-be/behaviours/README.md`
- `[N] specs/apps/bnest/app-be/behaviours/authentication.feature`
- `[N] specs/apps/bnest/app-be/behaviours/centralized_data.feature`
- `[N] specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature`
- `[N] specs/apps/bnest/app-be/behaviours/family_chat_operations.feature`
- `[N] specs/apps/bnest/app-be/behaviours/scheduled_backups.feature`
- `[N] specs/apps/bnest/app-be/behaviours/sqlite_storage.feature`

### Frontend surface

- `[N] specs/apps/bnest/app-fe/README.md`
- `[N] specs/apps/bnest/app-fe/architecture.md`
- `[N] specs/apps/bnest/app-fe/behaviours/README.md`
- `[N] specs/apps/bnest/app-fe/behaviours/authentication.feature`
- `[M] specs/apps/bnest/app/behaviours/chat.feature → specs/apps/bnest/app-fe/behaviours/chat.feature`
- `[N] specs/apps/bnest/app-fe/behaviours/centralized_data.feature`
- `[N] specs/apps/bnest/app-fe/behaviours/family_chat.feature`
- `[N] specs/apps/bnest/app-fe/behaviours/scheduled_backups.feature`
- `[M] specs/apps/bnest/app/behaviours/sifat_allah.feature → specs/apps/bnest/app-fe/behaviours/sifat_allah.feature`
- `[N] specs/apps/bnest/app-fe/behaviours/sqlite_storage.feature`

The old mixed `authentication.feature`, `centralized_data.feature`, `scheduled_backups.feature`, and
`sqlite_storage.feature` are deleted only after their scenarios are assigned once to the new files and all adapters are
green. A mapping ledger records every old scenario name, destination path, and unchanged/edited name. No scenario is
silently dropped or temporarily duplicated.

### Existing-corpus assignment rule

| Existing feature            | Backend owner                                                                                          | Frontend owner                                                                                  |
| --------------------------- | ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| `authentication.feature`    | Password hashing, session persistence/independence, capability policy, cross-user data isolation       | Redirect/login/setup/logout and visible home behavior                                           |
| `centralized_data.feature`  | Input validation, idempotency, stale-write rejection, persisted continuation/recovery                  | Browser-source discovery, confirmation, key cleanup, visible resume outcome                     |
| `chat.feature`              | None as a separate canonical feature; internal support is exercised by the production owner's adapters | Entire existing user-owned Codex browser journey, including reconnect and role-visible behavior |
| `scheduled_backups.feature` | Destination policy, schedule persistence/catch-up, snapshot, claims/retries, retention, registry       | Admin settings discovery, form authorization, contextual inventory, typed link                  |
| `sifat_allah.feature`       | None as a separate canonical feature                                                                   | Entire existing learning browser journey                                                        |
| `sqlite_storage.feature`    | Migration, authority, safety, relocation, retirement, continuity contract                              | Admin storage selection/access and routed reconnect UI                                          |

When one old scenario currently asserts both columns, split it into two newly named scenarios with different observable
Then clauses and delete the old scenario in the same atomic cutover. This is not duplication: the backend scenario ends
at the API/service/process boundary, while the frontend scenario ends at rendered browser behavior. The mapping ledger
must show the old name, both new names where split, and why neither repeats the other's outcome.

## Family Chat Backend Contracts

`family_chat_graphql.feature` owns:

```diff
+ Query authorized room list and Ruang Keluarga by slug.
+ Page messages with no cursor, beforeId, or afterId; reject both cursors and limits above 50.
+ Send an idempotent user message and return the original commit on retry.
+ Reject unauthenticated, forbidden, invalid, and missing-room operations with safe GraphQL errors.
+ Publish one post-commit room subscription event and catch up a missed event.
+ Read and mutate current Web Push configuration/subscription through GraphQL.
+ Require cookie/CSRF for mutations and session-derived identity for the socket.
+ Disable GraphiQL in production.
```

`family_chat_operations.feature` owns:

```diff
+ Seed Ruang Keluarga and preserve old-release compatibility.
+ Post an idempotent system message through the internal service only.
+ Commit messages and push delivery rows atomically.
+ Retry, retire, retain, and purge push delivery state.
+ Route Scheduler through registered handlers and public Push/Backup services.
+ Converge prod-sqlite-backup-daily to 18:00 UTC after compatible activation.
+ Refuse low-capacity backup, prove concurrent writes, and restore all family-chat state.
+ Keep release slots on independent local PubSub and reject nonzero Caddy stream-close delay.
+ Route replacement handshakes only to the promoted slot while the prior process remains warm and unrouted.
```

Backend unit/integration bindings remain ExBDD under `apps/bnest-app/test/behaviour/`. The driver is split into explicit
BE modules instead of one outcome lookup table. Real SQLite/loopback proof uses isolated marked roots and `test-user-`
identities. Backend E2E calls the exact routed GraphQL HTTP/WebSocket origin.

## Family Chat Frontend Contracts

`family_chat.feature` owns:

```diff
+ Redirect /family-chat to /family-chat/ruang-keluarga and render Ruang Keluarga.
+ Send online with Waiting, Sending, Retrying, Sent, and Couldn't send states.
+ Persist at most 100 per-user/per-room queued messages in IndexedDB.
+ Resume on reopen, react to online, use bounded jittered backoff, and expire at seven days.
+ Pause on authentication expiry and clear the user's queue on logout.
+ On Caddy promotion, close the prior-slot socket, reconnect to the promoted slot within ten seconds, subscribe first,
  catch up, deduplicate, and drain FIFO without refresh.
+ Preserve upward-scroll anchor and announce new messages without moving focus.
+ Expose push permission/disable UX and never cache authenticated data.
+ Remain accessible at desktop, tablet, mobile, and 200 percent zoom.
```

Frontend unit bindings use Vitest from `apps/bnest-app/assets/test/behaviour/` and directly exercise queue, backoff,
reconciliation, state projection, and cache policy without browser/network/filesystem access. Browser implementation is
owned by `bnest-app-fe-e2e` through Playwright.

## C4 Deltas

### `[N] specs/apps/bnest/app-be/architecture.md`

Add GraphQL HTTP/socket, Absinthe schema/resolvers, fixed subscription pool, Family Chat, slot-local room PubSub, Push
Notifications, Backup service, persistent Scheduler, SQLite room/message/outbox tables, browser push providers,
independent Caddy slots, config-reload socket evacuation, and the two scheduler-to-service dependency directions.
Preserve identity, Codex, learning, existing storage, and release relationships; do not imply distributed PubSub.

### `[N] specs/apps/bnest/app-fe/architecture.md`

Add Phoenix room shell, browser GraphQL client, IndexedDB outbox, service worker static cache, push handlers, and the
subscribe/catch-up/drain sequence. State that committed transcript is never offline storage and that logout/auth expiry
isolate the user namespace.

The old architecture is deleted only in the same change that both new models and the aggregate map become valid.

## E2E Project Split

`bnest-app-e2e` retires only after both replacements pass:

- `bnest-app-be-e2e` owns `specs/apps/bnest/app-be/behaviours/` and exercises routed GraphQL HTTP and Phoenix/Absinthe
  WebSocket operations, including envelope, auth, validation, idempotency, subscription lifecycle, and side effects.
- `bnest-app-fe-e2e` owns `specs/apps/bnest/app-fe/behaviours/` and moves the current Playwright browser/PWA harness,
  then adds family-chat UI, IndexedDB, offline, accessibility, and a Caddy-reload cutover journey that proves prior-socket
  close, promoted-slot subscription, catch-up, and exact-once rendering.

Both E2E projects contain a checked-in `behaviour-coverage.json` naming their one corpus root, adapter binding paths, and
driver. `bnest-app` contains the aggregate declaration for both roots and its BE ExBDD/FE Vitest adapters. Coverage tools
validate that declared roots exist, do not overlap, and together equal the aggregate map.

The root `test:e2e` command becomes a deterministic aggregate: BE first, then FE, each through its own self-guarded Nx
target, leased port, and isolated runtime root. `test:quick` includes typecheck/lint/unit/behavior coverage but never
integration or E2E runtime.

## Generator Assessment

Prior generator discovery found no installed/local Nx generator that can split an existing mixed ExBDD/Playwright corpus
into this repository-specific BE/FE topology. Delivery records that assessment and performs the split manually. It must
not invoke an unrelated generator merely to satisfy a scaffolding convention.

## Proof Matrix

| Concern                   | BE unit/integration     | FE Vitest               | BE E2E                 | FE E2E                | Manual                             |
| ------------------------- | ----------------------- | ----------------------- | ---------------------- | --------------------- | ---------------------------------- |
| GraphQL schema/auth/data  | Required                | Not applicable          | Routed HTTP/socket     | Consumer journey only | Every operation plus subscription  |
| SQLite transaction/backup | Real isolated SQLite    | Not applicable          | Observable API effects | Not applicable        | Restore and load proof             |
| Queue/backoff/reconcile   | API failure classes     | Required                | Failure fixtures       | Browser/IndexedDB     | Offline/reopen pass                |
| Scroll/accessibility      | Not layout-capable      | State helpers           | Not applicable         | Required              | Viewports, zoom, screen reader     |
| Push lifecycle            | Real store/loopback     | UX/service-worker state | GraphQL operations     | Browser permission UI | OS display outside plan completion |
| Release reconnect         | Compatible server proof | State machine           | Routed socket          | Two contexts          | Caddy cutover                      |

After each feature/adapter change, the manual Gherkin implementation review checks each scenario one by one: Given only
establishes relevant state, When crosses the intended boundary, Then inspects independent evidence, and no driver uses
no-ops, success literals, expected-result lookup, or manufactured asserted values.
