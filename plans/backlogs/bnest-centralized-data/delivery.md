# Delivery Plan

## Executor Legend

- `[AI]` — executable by the repository agent within existing authorization and safety boundaries.
- `[HUMAN]` — requires a maintainer decision, credentials, physical action, or external-state authority.

## Acceptance Traceability

Every task names the PRD Gherkin acceptance criterion it establishes or proves. `[AC-01–AC-11]` means the task is cross-cutting and supports every listed criterion.

- `[AC-01]` Protected login before Bnest access.
- `[AC-02]` Safe copy of existing browser state after login.
- `[AC-03]` Centralized storage is isolated by user.
- `[AC-04]` Multi-role access still needs explicit ownership or sharing permission.
- `[AC-05]` Interrupted migration is recoverable without losing accepted data.
- `[AC-06]` Login persists in the same browser until logout or revocation.
- `[AC-07]` One user can use independent simultaneous browser sessions.
- `[AC-08]` Verified import moves durable Bnest data off client storage without downtime.
- `[AC-09]` Initial username/password account setup occurs once; registration then closes.
- `[AC-10]` Login verifies a salted Argon2id hash without retaining plaintext passwords.
- `[AC-11]` Tests use marked synthetic roots and `test-user-` identities without touching real data.

## Preconditions

- [ ] `[AI] [AC-01–AC-11]` Re-read current C4, Gherkin, storage keys, runtime-data rules, UI assets, and test-identity standard. Record conflicts with the `data/prod/` plus mirrored `data/test/runs/<run-id>/` transition before implementation.
- [ ] `[HUMAN] [AC-01, AC-04, AC-06, AC-07, AC-09, AC-10]` Decide approved-user bootstrap, credential recovery, cookie security, session revocation, username character/length policy, and administrator responsibilities. Confirm no automatic expiry, browser-local logout, one-time setup, no self-registration, and whether future all-session revoke/password-reset capabilities are needed. The non-secret decision must be implementable by AI.
- [ ] `[HUMAN] [AC-03, AC-04]` Define the `children`, `parents`, and `admin` capability matrix, multi-role evaluation, and any explicit parent-to-child sharing rules. State the default-deny outcome for each undefined action.
- [ ] `[AI] [AC-02, AC-05, AC-08]` Inventory every runtime `data/` entry and allow-listed browser key: `bnest.chat.v1`, `bnest.sifat-allah.v1`, and `phx:theme`. Record reader, writer, accepted form/version, owner, target, client-cleanup condition, and safe outcome without putting private production content in Git or fixtures.
- [ ] `[HUMAN] [AC-05]` Define backup location, retention, restore operator, and a tested rollback owner; record the decision without credentials or live data.
- [ ] `[AI] [AC-11]` Define the `data/test/runs/<run-id>/` marker, unique run ID, browser-profile path, retention threshold, and fail-closed checks. Boot Bnest against that root and prove before account creation that its account index/family list cannot resolve `data/prod/`.

## Phase 1 — Storage Contract and Safety Harness

- [ ] `[AI] [AC-02, AC-05, AC-08, AC-11]` Update runtime-data guidance so `data/prod/` is live, `data/test/runs/<run-id>/` is the only filesystem-test root, both mirror `general/apps/system/users`, and root-level runtime folders remain legacy sources.
- [ ] `[AI] [AC-02–AC-11]` Define schema versions, server-generated user/import/session IDs, Bnest storage keys, manifest/session/account/username-index fields, and checksum format. Include the final chat, Sifat Allah, theme, account, and session record shapes; add isolated tests rejecting unsupported versions and client-selected destinations.
- [ ] `[AI] [AC-01–AC-03]` Add the selected `chat.feature` and `sifat_allah.feature` changes and all bindings named in `tech-docs.md` → Planned Specification Changes. Run behavior coverage and leave the bindings red before implementation.
- [ ] `[AI] [AC-01–AC-11]` Add `authentication.feature` and `centralized_data.feature`, then every listed unit, integration, and E2E binding/test path. Include setup-once, Argon2id login, persistent/two-browser sessions, post-read-back client cleanup, and isolated synthetic test users. Run behavior coverage and leave every new step binding red before implementation.
- [ ] `[AI] [AC-02, AC-05–AC-11]` Create ignored placeholders for `data/prod/{general,apps/beaver-nest,system,users}` and `data/test/runs/`. Confirm no root-level `data/{general,apps,system,users}/` entry was moved, deleted, or overwritten.
- [ ] `[AI] [AC-02–AC-11]` Implement both test helpers: create `data/test/runs/<run-id>/.bnest-test-run.json` and profile, start Bnest with that root, then create `test-user-<suite>-<run-id>`; reject `data/prod/`/shared roots; stop browser/server, revalidate marker, and delete only the exact run. Fail the target on cleanup failure.
- [ ] `[AI] [AC-11]` Implement the read-only Mix audit and expose it only through `bnest-app:schema:audit`. Compare public record type/version/field names/value types between production and synthetic mirror; output safe pass/fail categories. Reject writes, real-user authentication, payload copy, sensitive output, and fixture generation.
- [ ] `[AI] [AC-02–AC-10]` Implement server-owned path derivation, validation, atomic replacement, locking/concurrency behavior, and structured failures. Reject browser-selected paths before any file operation and username/user-ID path confusion before account lookup.
- [ ] `[AI] [AC-02, AC-03, AC-05, AC-08, AC-11]` Use a mirrored run root to prove malformed paths/JSON, duplicate imports, interruptions, cleanup order, and concurrency cannot overwrite accepted data. Add negative tests for `data/prod/`, shared run, missing/wrong marker, cleanup outside `data/test/runs/`, and cleanup before shutdown.

### Phase 1 Checkpoint

- [ ] `[AI] [AC-02, AC-05, AC-08]` Isolated backup, import, read-back, client-key cleanup, and restore tests pass with source and accepted destination preserved.
- [ ] `[AI] [AC-02, AC-05, AC-08]` Confirm live Bnest data belongs under `data/prod/`, test data under one mirrored run, all root-level legacy sources remain intact, and a completed browser migration leaves no Bnest persisted key client-side.
- [ ] `[AI] [AC-03]` Confirm no implementation accepts browser-selected paths.
- [ ] `[AI] [AC-11]` Confirm every test account begins `test-user-`, every target uses its own marked `data/test/runs/<run-id>/` and profile, its family list reads only that mirrored account index, no test account appears in production, and cleanup/failure behavior touches no sibling or production path.
- [ ] `[AI] [AC-11]` Run `npm exec -- nx run bnest-app:schema:audit` against `data/prod/` and one synthetic mirror. Confirm safe structural pass/fail output, unchanged production checksums, and no real identity, payload, or production-derived fixture in artifacts or evidence.

## Phase 2 — Login and Ownership Boundary

- [ ] `[AI] [AC-01, AC-03, AC-04, AC-06, AC-07, AC-09, AC-10]` Reconcile every named authentication scenario and binding in `tech-docs.md` → Planned Specification Changes. Update canonical wording only for a documented as-built difference.
- [ ] `[AI] [AC-09, AC-10]` Implement only the selected **Nest Cards** direction from `assets/README.md`: setup stepper, account form, role chips, family summary, irreversible-close review, and later login state. Match desktop/tablet/mobile composition and existing Bnest tokens; do not implement rejected alternatives.
- [ ] `[AI] [AC-09, AC-10]` Build the mutually exclusive setup/login UI in `login_live.ex`: bootstrap only when no account exists; collect required initial username/password/role accounts including one admin; atomically close setup afterward; show no self-registration link. Use visible labels/focus, a labeled password reveal, programmatically associated errors, keyboard-operable role state, reduced motion, and no unexpected loss of entered non-password values.
- [ ] `[AI] [AC-10]` Add and lock a maintained Argon2id dependency in `mix.exs`/`mix.lock`. Benchmark the OWASP baseline on the deployment-equivalent hardware, record only non-secret parameters, and reject a setting that makes login unusable.
- [ ] `[AI] [AC-09, AC-10]` Implement normalized-username lookup and stable user-ID account records. Hash each submitted password with the reviewed Argon2id dependency and accepted baseline; write only its encoded salted verifier. Reject duplicate usernames; never log, render, fixture, or persist a plaintext password.
- [ ] `[AI] [AC-01, AC-06, AC-07]` Implement the approved credential/session design: persistent HTTP-only browser cookie, server-verified per-browser session record, logout, and protected LiveView routes. Create a separate session record for each browser login; keep credentials and session secrets outside `data/`.
- [ ] `[AI] [AC-04]` Represent roles as a set, evaluate the approved capability matrix server-side, and default-deny actions with no matching capability.
- [ ] `[AI] [AC-03]` Make every user-data read/write path derive from authenticated identity. Add a negative test for every request parameter that attempts another user's path.
- [ ] `[AI] [AC-01, AC-04]` Add the maintainer-approved administrator bootstrap and recovery flow without storing credentials under `data/`.
- [ ] `[AI] [AC-01, AC-03, AC-04, AC-06, AC-07, AC-09–AC-11]` Prove with unit, integration, and E2E adapters that setup closes after bootstrap, duplicate username/plaintext leakage is rejected, Argon2id verification works, unauthenticated access cannot read/write state, the same browser stays logged in, and logging out browser A leaves the same user's browser B usable. Use only generated test identities and isolated profiles.

### Phase 2 Checkpoint

- [ ] `[AI] [AC-01, AC-06, AC-07, AC-09, AC-10]` Setup creates required accounts once and closes registration; a current user logs in through username/password; reload/restart retains that browser's session; browser A logout does not end browser B's same-user session.
- [ ] `[AI] [AC-03, AC-04]` Cross-user reads and writes fail in every applicable adapter, even for a multi-role user without explicit sharing permission.
- [ ] `[AI] [AC-09, AC-10]` At 1440×900, 768×1024, and 375×812, compare implementation with the selected hi-fi assets; verify keyboard order, visible focus, labels/errors, checked role state, password non-retention, reduced motion, and the irreversible-close warning.
- [ ] `[AI] [AC-11]` Inspect the stopped run root and browser-profile cleanup result. Prove two-browser coverage used two contexts for the same synthetic user and no path, account, or session existed in live data.

## Phase 3 — Browser and Legacy Import

- [ ] `[AI] [AC-02, AC-03, AC-08]` Support export/import only for `bnest.chat.v1`, `bnest.sifat-allah.v1`, and explicit `phx:theme` light/dark. Reject unknown keys, oversized snapshots, unsupported forms, and browser-selected destinations with an actionable safe error.
- [ ] `[AI] [AC-02, AC-05, AC-08]` Before each import, create backup and manifest records containing source path/key, checksum, destination, outcome, and retry-safe import ID in checksummed user-owned envelopes.
- [ ] `[HUMAN] [AC-02, AC-05, AC-08]` From the authorized browser and live legacy source, confirm import scope after backup exists. Do not provide browser credentials, cookies, private URLs, or payloads to the repository agent.
- [ ] `[AI] [AC-02, AC-08]` Re-read centralized data after import; mark it accepted only when checksum and schema validation succeed, then delete only the accepted Bnest browser key. A failed read-back retains the key and any previous accepted server record.
- [ ] `[AI] [AC-02, AC-05]` Copy every inventoried root-level runtime source into its mapped `data/prod/` destination before normalization; put Bnest legacy material under `data/prod/apps/beaver-nest/legacy/` and compare checksums.
- [ ] `[AI] [AC-02, AC-05, AC-08]` Retain browser keys only for incomplete imports and retain all legacy files; expose safe status and retry. After acceptance, retain server envelope/backup/manifest while the Bnest browser key is gone.

### Phase 3 Checkpoint

- [ ] `[AI] [AC-02, AC-05, AC-08]` Successful, duplicate, malformed, and interrupted imports preserve source data and accepted destinations; only accepted-and-read-back Bnest keys are cleared.
- [ ] `[AI] [AC-02, AC-08]` Every source-inventory entry is retained, copied/read-back/cleared in that order, or safely reported for retry; no allow-listed key is silently skipped.
- [ ] `[AI] [AC-05]` Imports produce deterministic manifest, backup, and retry state that supports a restore rehearsal.

## Phase 4 — Cutover and Recovery Evidence

- [ ] `[AI] [AC-02, AC-03, AC-08]` Put centralized reads/writes behind chat and learning flows. Keep a browser key only until accepted central data is re-read, then ensure JavaScript no longer writes chat/quiz/theme state to client storage.
- [ ] `[AI] [AC-01–AC-03, AC-06–AC-11]` Add targeted E2E journeys for setup-once, login, same-browser persistence, simultaneous sessions, import/client cleanup, continuation, and isolation. Run the affected E2E target with a unique `data/test/runs/<run-id>/`, browser profile, and `test-user-` accounts.
- [ ] `[AI] [AC-05]` Rehearse restore from a migration manifest and backup using isolated data; verify the restored record is readable and its checksum matches the accepted record.
- [ ] `[AI] [AC-01–AC-03, AC-06–AC-11]` With Playwright MCP and a marked `data/test/runs/<run-id>/`: bootstrap test accounts once, verify closed registration, persistent/two-browser login, browser-local logout, synthetic import/read-back/client cleanup, and cross-user denial. Prove production family/account data is unchanged, then stop contexts/server and clean the exact run.
- [ ] `[AI] [AC-01–AC-11]` Update only selected C4/Gherkin contracts, app/E2E READMEs, runtime-data guidance, directory maps, and operations docs to final as-built state; do not copy plan-only PRD scenarios into `specs/`.
- [ ] `[AI] [AC-01–AC-11]` Record architecture-impact assessment, automated target results, three-viewport UI/accessibility evidence, synthetic-root cleanup evidence, and manual public-boundary smoke results in this plan.

### Phase 4 Checkpoint

- [ ] `[AI] [AC-01–AC-11]` `npm exec -- nx run bnest-app:test:quick`, affected `bnest-app:test:integration`, and targeted `bnest-app-e2e:test:e2e` pass; bootstrap/Argon2id, backup/restore, persistent-login, independent-browser-session, client-cleanup, three-viewport accessibility, private-login smoke, and exact synthetic cleanup also pass.
- [ ] `[HUMAN] [AC-02, AC-05, AC-08]` Decide whether a later explicit archival plan is needed; do not delete immutable server sources or root-level legacy runtime folders in this plan.

## Rollback Rules

- [ ] `[HUMAN] [AC-05]` Stop new centralized writes before a live rollback.
- [ ] `[AI] [AC-02, AC-05, AC-08]` Preserve manifests, accepted records, any incomplete-import browser keys, and legacy files; capture safe checksums and paths as rollback evidence.
- [ ] `[HUMAN] [AC-05]` Restore live data from the last verified backup or continue from the retained source representation.
- [ ] `[AI] [AC-01–AC-11]` Record the failure and route reusable learning to specifications, governance, or a new plan before marking this plan done.
