# Product Requirements Document

## Product Overview

Evolve Bnest from browser-persisted experiences into a private, login-protected application with centralized local flat-file data. The implementation must add persistence behind the existing front-end flows, so existing state is imported and preserved before the new store becomes authoritative.

## Personas and Roles

- **Child:** needs a private login and continuity of their permitted Bnest state.
- **Parent:** needs a private login and access to their permitted household experiences.
- **Admin:** needs to provision role assignments and verify safe recovery without direct file manipulation.
- **Maintainer:** needs deterministic migration, test fixtures, and rollback without production data in source control.

A user may have multiple roles from `children`, `parents`, and `admin`. Authorization evaluates the complete role set plus the explicit record-ownership or sharing policy; no role grants cross-user data access merely by existing.

## User Stories

- As an approved user, I must log in before I can use Bnest.
- As an approved user on my current browser, I can import existing chat and learning state without losing its browser copy.
- As an approved user, I see only data assigned to my identity.
- As an administrator, I can see whether migration completed or needs retry without seeing another user's content.
- As a maintainer, I can recover an interrupted migration from its manifest and backup.

## Product Requirements

1. Every Bnest route and server data operation requires an authenticated session, except explicitly defined login, logout, bootstrap, and health endpoints.
2. Each authenticated user has one or more roles from `children`, `parents`, and `admin`; role assignments are many-to-many and auditable.
3. The application derives a stable internal user ID from the authenticated session; browser input never selects a filesystem path or another user.
4. The persistence layout is:

   ```text
   data/
   ├── users/<user-id>/
   ├── apps/beaver-nest/
   └── system/
   ```

5. `data/users/<user-id>/` contains user-owned Bnest records and that user's imported browser-source envelopes.
6. `data/apps/beaver-nest/` contains Bnest-wide data and configuration; migrated `data/general/` content is retained as a versioned legacy copy before any normalized application record uses it.
7. `data/system/` contains only system-wide migration manifests, schema metadata, and audit-safe hashes; it contains no credentials or user-authored payloads.
8. On the first authenticated visit from a browser with Bnest snapshots, the application offers import and records source key, schema version, payload hash, timestamp, and outcome. It does not clear `sessionStorage` or `localStorage` automatically.
9. Every write validates a versioned schema and uses an atomic replacement strategy. Imports are idempotent by source identity and checksum.
10. A failed or interrupted import preserves both source and already accepted destination data, reports its state, and can be retried safely.
11. Browser state remains a compatibility fallback only until its import is acknowledged and centrally re-read; the centralized record is then the authoritative continuation point.

## Proposed Acceptance Criteria

```gherkin
Feature: Centralized Bnest data

  Scenario: User must log in before accessing Bnest
    Given a visitor has no authenticated Bnest session
    When the visitor opens a protected Bnest route
    Then Bnest directs them to login
    And Bnest does not read or write user data

  Scenario: Existing browser state is copied safely after login
    Given an approved user has authenticated in a browser with a valid Bnest snapshot
    When the user confirms import
    Then Bnest stores a checksummed copy under that user's data directory
    And the original browser snapshot remains unchanged

  Scenario: Users are isolated in centralized storage
    Given two approved users each have centralized Bnest data
    When one user opens Bnest
    Then Bnest reads only that user's data
    And no filesystem path comes from browser input

  Scenario: A user may hold multiple roles without gaining implicit data access
    Given an authenticated user has both "parents" and "admin" roles
    When Bnest authorizes a data operation
    Then it evaluates the user's complete role set
    And it still requires explicit ownership or sharing permission for another user's data

  Scenario: Interrupted migration is recoverable
    Given Bnest has recorded an import manifest before completing an import
    When the import is interrupted
    Then the source and accepted destination records remain available
    And retrying the import does not duplicate or overwrite accepted data
```

## Scope and Risks

In scope: authentication boundary, user ownership, flat-file layout, browser import, legacy-folder import, backup, restore, and migration observability.

Out of scope: public accounts, deleting legacy sources, cloud synchronization, and unrelated interface redesign.

Key risks are unresolved authentication bootstrap, storage corruption, duplicate import, and user-data exposure. The technical and delivery documents make backup, checksum, atomic write, and path-ownership gates mandatory.
