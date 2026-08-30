# Product Requirements

## Product Story

As a Bnest administrator, I want the production database backed up every day and one settings dashboard for contextual schedules and admin-owned parameters, so I can manage operational behavior without shell access or hidden URLs.

## Acceptance Criteria

### AC-01 — Configure and prove the destination

```gherkin
Scenario: Use the Dropbox-synced default
  Given no backup override exists
  When a scheduled or initial backup resolves its destination
  Then Bnest uses repository-root data/backup
  And shows the independently verified result without exposing the path elsewhere

Scenario: Save a safe override
  Given a current admin opens Schedules & backups through Admin settings
  When they save a valid destination override
  Then Bnest stores the private configuration atomically
  And creates one idempotent initial backup run
```

### AC-02 — Persist the daily schedule

```gherkin
Given an admin atomically saved the enabled state and daily WIB time in its schedule panel
When the application process restarts before the schedule is due
Then the schedule remains enabled in SQLite
And the next run remains the same UTC instant
And one verified backup is produced for that scheduled slot
```

### AC-03 — Catch up without replay

```gherkin
Given the application was unavailable across more than one daily slot
When the scheduler starts again
Then it claims only the latest missed slot once
And advances the next run to the next future day
And does not create historical snapshots for every missed day
```

### AC-04 — Use only authoritative SQLite

```gherkin
Given retired flat-file paths or repository data exist
When a production backup runs
Then the source is the configured authoritative production SQLite database
And the backup is made with VACUUM INTO
And the candidate passes independent integrity and logical proof
```

### AC-05 — Claim once and recover safely

```gherkin
Given old and candidate releases overlap or a runner lease expires
When both coordinators observe the same scheduled slot
Then SQLite accepts only one run claim for that slot
And no two backup tasks overlap
And a transient failure receives at most three persisted attempts
And the last verified artifact remains unchanged
```

### AC-06 — Show all persistent daily schedules

```gherkin
Given application-owned daily schedules are persisted
When a current admin follows Schedules & backups from the admin home
Then every enabled or disabled daily schedule is listed
And Family schedules and Admin/system schedules appear in separate groups
And each entry shows cadence, next run, current state, and last safe result
And the production backup entry links to its typed settings panel
And the journey does not require manually entering a URL
```

### AC-07 — Deny every non-admin

```gherkin
Given a visitor is unauthenticated, revoked, or lacks the current admin role
When they view home or navigate directly to an admin settings route
Then home renders neither Admin settings nor Schedules & backups
And Bnest returns the existing not-found response before schedule or config reads
And reveals no schedule, run, path, or backup metadata
```

### AC-08 — Retain only owned verified artifacts

```gherkin
Given the current marked destination contains owned backups across more than seven WIB dates or more than one pair on a date
And also contains unknown, partial-unowned, or mismatched files
When a new backup becomes verified
Then Bnest keeps only the newest verified owned pair for each of today and the previous six WIB dates
And leaves every unknown or unowned file untouched
And never deletes artifacts from a previous destination
```

### AC-09 — Reuse one scheduler across contexts

```gherkin
Given another allowlisted daily handler is registered as family or admin_system
When its persisted schedule becomes due
Then the existing coordinator claims and supervises its run
And the existing run ledger records its safe outcome
And the admin dashboard places it in the matching context group
And no backup-specific scheduler, table, or runner is introduced
```

### AC-10 — Centralize admin-owned configuration

```gherkin
Given multiple domains declare typed admin settings panels
When a current admin opens Admin settings from admin home
Then every declared configuration area is discoverable there
And each panel validates and persists through its owning domain
And no arbitrary key, handler, context, module, or function can be submitted
And saving one panel cannot partially save another owner’s panel
```

### AC-11 — Expire schedules deterministically

```gherkin
Given a schedule expires never, at an admin-entered WIB date/time stored as UTC, or after N occurrences
When the coordinator reconciles it across restart or overlapping releases
Then an absolute expiry prevents claims at or after its instant
And an occurrence expiry counts each unique scheduled slot once
And retry attempts do not increase the occurrence count
And the final allowed occurrence is still dispatched while further claims are blocked
```

## Experience Requirements

- `/admin/settings` and `/admin/settings/schedules` use existing authenticated and admin-only pipelines.
- The current admin home includes visible **Admin settings** and **Schedules & backups** entries; both are absent for every non-admin role.
- Admin settings inventories all code-declared panels; Schedules & backups separates **Family schedules** and **Admin/system schedules**, including empty states.
- Schedule rows show **Never expires**, an absolute expiry, or occurrence progress; only registry-approved schedules expose expiry editing.
- Backup settings shows the `@data/backup/` default, an optional destination override, and fixed **Keep one per day for 7 days** policy.
- Desktop uses the selected schedule ledger; tablet becomes one column; mobile becomes labeled cards.
- Status never relies on color alone and asynchronous changes are announced politely.
- Folder validation focuses a concise error summary; failures provide safe corrective guidance.
- 200% zoom has no horizontal page scrolling, focus survives LiveView patches, and reduced motion is respected.

## Out of Scope

- Editing cadence kind, handler, context, retry policy, or executable code; creating arbitrary jobs; automatic restore; backup download; remote-object storage; encryption keys; or non-WIB schedules.
- A family-facing schedules page; a later feature may present only `family` rows through the same policy-bound scheduler read API.
- Replacing existing domain storage with a generic settings key/value table.
