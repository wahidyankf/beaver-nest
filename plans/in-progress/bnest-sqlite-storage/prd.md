# Product Requirements

## Personas

- **New household administrator:** wants storage to work at a safe default without a separate storage screen.
- **Existing household administrator:** may override the default before migration, but otherwise wants the move to run without UI.
- **Family member:** expects existing Bnest behavior and sessions to continue unchanged.
- **Maintainer:** needs deterministic migration, recovery, and deployment evidence.

## User Stories

- As a maintainer, I can migrate to `~/.config/bnest/` through managed tooling without visiting storage UI.
- As an administrator, I can optionally replace the default with another server-local folder before migration starts.
- As a family member, I can continue from the same authenticated route after the storage cutover.
- As a maintainer, I can reproduce the schema from a committed migration file and rerun the data backfill safely.

## Acceptance Criteria

### AC-01 — Default location

```gherkin
Scenario: Managed migration uses the private default without storage UI
  Given Bnest has no storage configuration
  And the storage UI has not been visited
  When managed migration starts
  Then Bnest uses "~/.config/bnest/bnest.sqlite3"
  And migration does not require a browser confirmation
```

### AC-02 — Custom location safety

```gherkin
Scenario: Administrator optionally selects a valid custom database folder
  Given an authenticated user with the admin role opened storage settings
  And migration has not started
  When the administrator enters a writable private server-local folder
  Then Bnest normalizes the folder and appends "bnest.sqlite3"
  And Bnest stores only the validated absolute location in private machine state

Scenario: Unsafe database folder is rejected without mutation
  Given an authenticated user with the admin role opened storage settings
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
Scenario: Managed migration moves every recognized flat-file record
  Given a flat-primary installation has no custom storage location
  And no incompatible release slot can write
  When managed storage migration runs without a UI visit
  Then Bnest inventories records in deterministic path order
  And Bnest writes the database under "~/.config/bnest/"
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
  When the managed migration commits the storage authority switch without UI confirmation
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

- Optional pre-migration screen with default folder, custom-folder edit, validation pending, safe error, and locked-after-start state.
- Optional status screen with inventory pending, copying, verifying, blocked, retryable, and SQLite active; migration itself does not depend on this screen.
- The primary action keeps one verb per state: **Check folder**, **Create database**, **Move data**, **Retry migration**, or **Continue account setup**.
- Progress is textual and announced through a polite live region; blocking failure uses an alert. No state relies on color alone.

## Scope Boundaries

In scope: server-local folder selection, configuration pointer, SQLite DDL, all supported record types, idempotent backfill, rollback compatibility, health/readiness, docs, specifications, tests, and Caddy rollout.

Out of scope here: deletion of legacy records, which is queued in the separately gated [flat-file retirement plan](../../backlogs/bnest-flat-file-retirement/README.md); database relocation after initialization; feature-level relational redesign; cloud storage; real-user tests; and public host-path disclosure.
