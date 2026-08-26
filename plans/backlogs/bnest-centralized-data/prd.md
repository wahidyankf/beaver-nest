# Product Requirements Document

## Product Overview

Evolve Bnest from browser-persisted experiences into a private, login-protected application with centralized local flat-file data. The implementation must add persistence behind the existing front-end flows, so existing state is imported and preserved before the new store becomes authoritative.

## Personas and Roles

- **Child:** needs a private login and continuity of their permitted Bnest state.
- **Parent:** needs a private login and access to their permitted household experiences.
- **Admin:** is one of the accounts created during setup and uses only the same self-owned capabilities defined for this plan; later account administration is out of scope.
- **Maintainer:** needs deterministic migration, test fixtures, and rollback without production data in source control.

A user may have multiple roles from `children`, `parents`, and `admin`. Authorization evaluates the complete role set plus the explicit record-ownership or sharing policy; no role grants cross-user data access merely by existing.

## User Stories

- **US-01 — Protected access:** As an approved user, I must log in before I can use Bnest and remain signed in on this browser until I log out or the browser clears its cookie.
- **US-02 — Safe import:** As an approved user on my current browser, I can migrate existing chat and learning state without loss, then continue from server-owned data rather than client persistence.
- **US-03 — Private data:** As an approved user, I see only data assigned to my identity.
- **US-04 — Safe migration status:** As an approved user, I can see whether my own migration completed or needs retry without exposing its content.
- **US-05 — Recoverable migration:** As a maintainer, I can recover an interrupted migration from its manifest and immutable source copy.
- **US-06 — Concurrent personal access:** As an approved user, I can use Bnest in more than one browser at the same time without ending my other browser sessions.
- **US-07 — One-time account setup:** As the initial maintainer, I can create the required usernames, passwords, and roles once through a setup UI; nobody can self-register afterward.
- **US-08 — Safe test identity:** As a maintainer, I can run authentication and migration tests without using or risking a real account, browser profile, session, or data directory.

## Product Requirements

1. Every Bnest route and server data operation requires an authenticated session, except explicitly defined login, logout, bootstrap, and health endpoints. The server session has no time-based expiry; its persistent browser cookie survives reload/restart until logout or browser clearing/eviction.
2. Each authenticated user has one or more roles from `children`, `parents`, and `admin`; the account record stores the complete unique role set created during one-time setup.
3. The application derives a stable internal user ID from the authenticated session; browser input never selects a filesystem path or another user.
4. The persistence layout is:

   ```text
   data/
   ├── prod/
   │   ├── general/
   │   ├── apps/beaver-nest/
   │   ├── system/
   │   └── users/<user-id>/
   └── test/runs/<run-id>/
       ├── general/
       ├── apps/beaver-nest/
       ├── system/
       └── users/<user-id>/
   ```

5. `<runtime-root>/users/<user-id>/` contains user-owned Bnest records and that user's imported browser-source envelopes. Production resolves `<runtime-root>` to `data/prod/`; one filesystem test resolves it to its unique `data/test/runs/<run-id>/`.
6. Each runtime root mirrors `general/`, `apps/beaver-nest/`, `system/`, and `users/`. Bnest-wide data belongs in `apps/beaver-nest/`; repository-wide shared data belongs in `general/`.
7. `<runtime-root>/system/` contains only bootstrap/account/username/session records, migration manifests, schema metadata, and audit-safe hashes; it contains no plaintext credentials or user-authored payloads. Browser envelopes and immutable legacy recovery copies stay in the owning user/application namespace.
8. On the first authenticated visit, the application offers import only for the known Bnest keys `bnest.chat.v1`, `bnest.sifat-allah.v1`, and explicit `phx:theme` light/dark preference. It records source key, accepted source version or format, payload hash where present, timestamp, and outcome. It never clears a key before server checksum, normalization, and read-back succeed; after that acceptance it removes Bnest's persisted browser keys because the immutable server envelope and normalized server record are authoritative.
9. Every write validates a versioned schema and uses an atomic replacement strategy. Imports are idempotent by source identity and checksum.
10. A failed or interrupted import preserves both source and already accepted destination data, reports its state, and can be retried safely.
11. Browser state remains a compatibility fallback only until its import is acknowledged and centrally re-read; the centralized record is then the authoritative continuation point.
12. Each login creates a separately revocable browser session. One user may have simultaneous sessions in multiple browsers; logout in one browser does not end another browser's session. Mutable records use revision checks: a stale browser cannot overwrite newer accepted data and receives a refresh-required result instead. All-session revocation is out of scope.
13. After a verified migration, durable chat, Sifat Allah progress/quiz state, and explicit theme preference are read and written only beneath `data/prod/users/<user-id>/`; Bnest no longer persists those values in `sessionStorage` or `localStorage`. A browser not yet migrated retains its old keys only as a safe import source until that browser's first successful import, so the rollout never makes existing state unavailable.
14. When no bootstrap journal exists, one-time setup creates all initial username/password/role accounts, including an `admin`, through a crash-recoverable transaction. Before confirmation it warns that setup will close and this plan has no later account creation, role edit, disablement, or password recovery. A lost credential leaves that account unavailable; restoring a migration recovery source must not roll back unrelated data as password recovery. Later lifecycle capabilities require an explicit plan.
15. Passwords are accepted only by the setup/login form, never logged or written as plaintext. The account record stores a per-password salted Argon2id password-hash string and its parameters; SHA-256 or another fast hash is not a password verifier.
16. Every filesystem-backed automated or AI-operated manual test starts a dedicated Bnest process against `data/test/runs/<run-id>/` and an isolated browser profile before creating synthetic `test-user-<suite>-<run-id>` accounts. Its mirrored account index and family list exist only in that run; test users never appear in production. Pure in-memory unit tests create no runtime folder. Development may inspect `data/prod/` only through a read-only structural schema audit that reveals no identity, path, count, hash, credential/session material, or payload and never supplies test fixtures.

## Proposed Acceptance Criteria

These Gherkin scenarios express acceptance for this plan. They do not automatically become canonical `specs/` scenarios or prescribe a one-to-one rewrite. [Planned specification changes](tech-docs/specification-changes.md) selects the durable user-facing contracts; `delivery.md` proves the remaining operational and migration outcomes.

```gherkin
  Feature: Centralized Bnest data

  @AC-01
  Scenario: User must log in before accessing Bnest
    Given a visitor has no authenticated Bnest session
    When the visitor opens a protected Bnest route
    Then Bnest directs them to login
    And Bnest does not read or write user data

  @AC-02
  Scenario: Existing browser state is copied safely after login
    Given an approved user has authenticated in a browser with valid Bnest chat, learning, or explicit theme state
    When the user confirms import
    Then Bnest stores a checksummed immutable envelope under that user's data directory
    And the original browser snapshot remains unchanged until centralized read-back succeeds

  @AC-03
  Scenario: Users are isolated in centralized storage
    Given two approved users each have centralized Bnest data
    When one user opens Bnest
    Then Bnest reads only that user's data
    And no filesystem path comes from browser input

  @AC-04
  Scenario: A user may hold multiple roles without gaining implicit data access
    Given an authenticated user has both "parents" and "admin" roles
    When Bnest authorizes a data operation
    Then it evaluates the user's complete role set
    And it still requires explicit ownership or sharing permission for another user's data

  @AC-05
  Scenario: Interrupted migration is recoverable
    Given Bnest has recorded an import manifest before completing an import
    When the import is interrupted
    Then the source and accepted destination records remain available
    And retrying the import does not duplicate or overwrite accepted data

  @AC-06
  Scenario: Login persists in the same browser
    Given an approved user has logged in on one browser
    When they reload or reopen Bnest before logout or browser cookie clearing
    Then Bnest restores that browser's authenticated session without another login
    And Bnest reads only that user's data

  @AC-07
  Scenario: One user has independent simultaneous browser sessions
    Given an approved user has logged in on browser A
    When the same user logs in on browser B
    Then both browsers can use that user's permitted Bnest data
    And logging out of browser A does not end browser B's session
    And a stale write from either browser cannot overwrite a newer accepted record

  @AC-08
  Scenario: Verified migration removes Bnest client persistence without downtime
    Given an approved user has legacy chat, learning, or theme data in their current browser
    When Bnest copies it, validates it, and reads the centralized representation successfully
    Then that user continues from centralized chat, learning, and preference records
    And Bnest removes only its accepted persisted browser keys after server read-back
    And a browser that has not migrated remains able to import its untouched legacy source

  @AC-09
  Scenario: Initial setup creates accounts only once
    Given no Bnest account records exist
    When the initial maintainer creates the required username, password, and role accounts in setup
    Then Bnest creates at least one admin account and completes bootstrap
    And Bnest warned that later account management and password recovery are unavailable in this plan
    And setup and public self-registration are unavailable afterward

  @AC-10
  Scenario: Username and password login never retains a plaintext password
    Given an initialized Bnest account has a username and password
    When that user logs in through the Bnest login UI
    Then Bnest verifies a salted Argon2id password hash for the normalized username
    And Bnest stores, logs, and renders no plaintext password

  @AC-11
  Scenario: Tests cannot mutate a real user or data root
    Given an authentication or migration test needs an account and user-owned data
    When the test prepares its isolated runtime and browser context
    Then it creates a unique username beginning with "test-user-"
    And it writes only synthetic data beneath "data/test/runs/<run-id>/"
    And the test family list reads only that run's mirrored account index
    And no synthetic account appears in the production family list
    And a production schema audit compares only record types, versions, field names, and value types
    And no test authenticates as a real user or copies production data into a fixture
    And cleanup removes only that exact validated run root after the test stops
    And "data/prod/" or a shared run root makes the test fail before mutation
```

## Scope and Risks

In scope: authentication boundary, user ownership, flat-file layout, browser import, legacy-folder import, immutable recovery sources, restore, and migration observability.

Out of scope: public accounts, post-bootstrap account/role/password management, parent-child sharing, deleting legacy sources, cloud synchronization, and unrelated interface redesign.

Key risks are irreversible setup without password reset, storage corruption, duplicate import, and user-data exposure. The technical and delivery documents require explicit setup warning, verified recovery sources, checksums, atomic writes, and path-ownership gates.
