# Product Requirements

## Personas and Stories

- As a family member, I keep using Bnest after old storage is removed.
- As an administrator, I can trust that only data already present in SQLite is deleted.
- As a maintainer, I can run and retry one deterministic retirement task without selecting paths manually.

## Acceptance Criteria

### AC-R01 — Entry proof

```gherkin
Scenario: Retirement waits for complete SQLite proof
  Given SQLite is authoritative
  And active and rollback artifacts read and write SQLite
  And every recognized flat-file source has accepted checksum evidence
  And an isolated SQLite restore passes normal reads
  When retirement eligibility is checked
  Then Bnest permits exact-source retirement
```

### AC-R02 — Incomplete migration blocks deletion

```gherkin
Scenario: Unproven source is preserved
  Given a recognized flat-file source has no matching accepted SQLite target
  When retirement eligibility is checked
  Then no legacy file is deleted
  And the result reports a value-free incomplete-migration category
```

### AC-R03 — Exact deletion

```gherkin
Scenario: Proven legacy sources are deleted exactly once
  Given every recognized source checksum matches its accepted target and retirement manifest
  When the retirement task runs
  Then each exact proven source file is deleted
  And unknown files and shared runtime roots remain unchanged
  And retry reports the accepted deletion receipts without broad deletion
```

### AC-R04 — Changed source protection

```gherkin
Scenario: Source changed after migration is not deleted
  Given a recognized source checksum differs from its migration receipt
  When the retirement task reaches that source
  Then that source remains unchanged
  And retirement remains incomplete with a safe changed-source category
```

### AC-R05 — SQLite-only continuity

```gherkin
Scenario: Bnest remains usable after flat-file retirement
  Given proven legacy sources were deleted
  When the SQLite-only application restarts and a compatible candidate is promoted
  Then login, logout, chat, learning, theme, and browser import use SQLite
  And the routed LiveView reconnects without a manual refresh
  And no Bnest operation recreates a legacy flat file
```

### AC-R06 — Storage UI authorization

```gherkin
Scenario: Only an admin can view storage retirement status
  Given an authenticated user does not have the admin role
  When the user opens storage settings
  Then Bnest denies the route before rendering storage details
  And no filesystem path, migration status, or deletion receipt is revealed
```

## Scope Boundaries

In scope: SQLite-only reader/writer floor, exact proof manifest, permanent deletion of supported Bnest legacy source files, empty-directory cleanup, configuration/code contraction, restart, restore, tests, specifications, and Caddy rollout.

Out of scope: arbitrary files, shared roots, secure erase claims, SQLite records/evidence, external backups, database relocation, and feature redesign.
