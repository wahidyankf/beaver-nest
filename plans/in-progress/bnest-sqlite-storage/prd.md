# Product Requirements

## Personas

- **New household administrator:** wants a safe default and plain explanation before creating the first accounts.
- **Existing household administrator:** wants to move current data without re-entering or exposing it.
- **Family member:** expects existing Bnest behavior and sessions to continue unchanged.
- **Maintainer:** needs deterministic migration, recovery, and deployment evidence.

## User Stories

- As a new administrator, I can accept `~/.config/bnest/` or enter another server-local folder before account setup.
- As an existing administrator, I can review readiness and start or retry migration without seeing private record contents.
- As a family member, I can continue from the same authenticated route after the storage cutover.
- As a maintainer, I can reproduce the schema from a committed migration file and rerun the data backfill safely.

## Acceptance Criteria

### AC-01 — Default location

```gherkin
Scenario: New setup proposes the private default SQLite folder
  Given Bnest has no accounts and no storage configuration
  When the administrator opens setup
  Then the database folder is "~/.config/bnest/"
  And Bnest explains that the folder is on the server host
  And account creation remains blocked until storage is ready
```

### AC-02 — Custom location safety

```gherkin
Scenario: Administrator selects a valid custom database folder
  Given storage setup is authorized
  When the administrator enters a writable private server-local folder
  Then Bnest normalizes the folder and appends "bnest.sqlite3"
  And Bnest stores only the validated absolute location in private machine state

Scenario: Unsafe database folder is rejected without mutation
  Given storage setup is authorized
  When the folder is relative, symlinked, world-writable, inside the repository, or overlaps a migration source
  Then Bnest explains the safe correction
  And Bnest creates no database or storage configuration
```

### AC-03 — Reproducible schema

```gherkin
Scenario: Versioned SQLite migration creates the expected schema once
  Given an empty isolated database
  When the committed migration set is applied twice
  Then the schema version and indexes match the declared checksum
  And the second run makes no duplicate table, index, or migration record
```

### AC-04 — Existing data migration

```gherkin
Scenario: Existing administrator migrates every recognized flat-file record
  Given an administrator is logged in to a flat-primary installation
  And no incompatible release slot can write
  When the administrator starts storage migration
  Then Bnest inventories records in deterministic path order
  And each accepted item has immutable source and target checksum evidence
  And normal repository reads return the same validated record

Scenario: Interrupted migration resumes idempotently
  Given migration stopped after at least one accepted item
  When the administrator retries the same migration identifier
  Then accepted matching items are not rewritten or duplicated
  And remaining items continue from their recorded outcomes
```

### AC-05 — Authority switch

```gherkin
Scenario: SQLite becomes authoritative only after complete verification
  Given schema, backfill, parity, integrity, and isolated restore checks pass
  When Bnest commits the storage authority switch
  Then future reads use SQLite
  And future writes remain compatible with the rollback reader
  And chat, learning, theme, login, and logout survive an application restart
```

### AC-06 — Failure preservation

```gherkin
Scenario: Invalid or changed source blocks cutover without data loss
  Given a source is malformed, unsupported, or changes after inventory
  When Bnest verifies migration
  Then SQLite does not become authoritative
  And the source and current flat-primary service remain unchanged
  And the administrator sees a value-free retry category
```

### AC-07 — Authorization and privacy

```gherkin
Scenario: Non-admin cannot configure storage
  Given a non-admin family member is logged in
  When the user opens the storage settings route
  Then Bnest denies the operation
  And Bnest reveals no host path or migration inventory
```

### AC-08 — Active-service rollout

```gherkin
Scenario: Routed client reconnects across compatible SQLite rollout
  Given the current Caddy route is healthy and a connected user has acknowledged state
  When a revision-compatible candidate is promoted
  Then the routed revision and SQLite readiness are proven
  And the LiveView reconnects without a manual refresh
  And the acknowledged state and unsent draft remain available
```

## UI States

- New setup with default folder; custom-folder edit; validation pending; safe error; database initialization; ready for account setup.
- Existing migration with inventory pending; ready; copying; verifying; blocked; retryable; SQLite active.
- The primary action keeps one verb per state: **Check folder**, **Create database**, **Move data**, **Retry migration**, or **Continue account setup**.
- Progress is textual and announced through a polite live region; blocking failure uses an alert. No state relies on color alone.

## Scope Boundaries

In scope: server-local folder selection, configuration pointer, SQLite DDL, all supported record types, idempotent backfill, rollback compatibility, health/readiness, docs, specifications, tests, and Caddy rollout.

Out of scope: deletion of legacy records, database relocation after initialization, feature-level relational redesign, cloud storage, real-user tests, and public host-path disclosure.
