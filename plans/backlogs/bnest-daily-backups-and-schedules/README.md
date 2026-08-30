# Bnest Daily Backups and Schedules

- **Status:** Backlog
- **Created:** 2026-08-30
- **Last reviewed:** 2026-08-30 against current `main`
- **Readiness:** Ready for execution; plan quality gate passed 2026-08-30

## Context

Bn​est's production SQLite database is authoritative but has no application-managed recurring backup. Administrators also cannot see which daily jobs the application owns, whether they ran, or when they will run next.

## Scope

- Persist reusable daily schedules, their `family` or `admin_system` context, and safe run history in SQLite.
- Use built-in Elixir/OTP supervision for scheduling and execution.
- Back up only the authoritative production SQLite database each day to repository-root `data/backup/` by default, with an admin-configurable safe override.
- Add an admin-only settings dashboard that inventories admin-owned configuration areas and provides typed, domain-owned forms.
- Add a schedules-and-backups section that separates family from admin/system jobs and exposes only safe admin-editable parameters.
- Add visible **Admin settings** and **Schedules & backups** entry points on the admin home; direct URL entry is never the normal journey.
- Retain at most one verified owned pair for each of the latest seven WIB calendar days and prove safe blue/green operation, retry, recovery, and rollback.

## Non-goals

- Flat-file, browser, credential, Codex, or repository backup.
- Automated restore, remote transfer, encryption/key management, arbitrary cron expressions, or user-created executable jobs.
- Visibility for any role other than a current server-authorized admin.

## Approach

An OTP coordinator uses a process timer only to wake up. SQLite remains authoritative for contextual schedule definitions, unique run claims, leases, retry state, and safe outcomes. Every allowlisted daily handler in either context reuses the same coordinator, tables, and supervised runner. The backup handler creates a transactionally consistent SQLite snapshot with `VACUUM INTO`, verifies it independently, writes a value-free receipt, and retains only artifacts tied to the current destination marker.

The admin home renders a role-gated **Admin settings** tile plus a **Schedules & backups** shortcut. `/admin/settings` indexes all code-declared admin configuration areas; `/admin/settings/schedules` groups **Family schedules** and **Admin/system schedules** and owns backup parameters. The documented alias `@data/backup/` means repository-root `data/backup/`; completed immutable snapshots there are Dropbox-synced, ignored by Git, and distinct from the live SQLite database outside Dropbox.

No new external dependency is planned. `02:00 WIB` is persisted as the fixed UTC+07:00 daily instant; support for zones with daylight-saving transitions would require a separate decision.

## Dependencies

- Existing SQLite authority, storage proof/relocation logic, admin-role enforcement, LiveView, and Caddy candidate release flow.
- A new approved `bnest-persistent-schedules-v1` release adapter; the current release controller intentionally rejects undeclared non-empty migration sets.
- A private writable repository `data/backup/` default or safe admin-selected override.
- No package-manifest or lockfile change.

## Selected UI

![Selected admin schedule ledger](assets/ui-ledger-hifi-desktop.svg)

## Navigation

- [Business requirements](brd.md)
- [Product requirements](prd.md)
- [Technical design](tech-docs.md)
- [Delivery plan](delivery.md)
- [Learnings](learnings.md)
- [UI assets](assets/README.md)

## Directory Map

- [`assets/`](assets/README.md) — lo-fi alternatives and selected responsive hi-fi design.
- [`brd.md`](brd.md) — business goals, roles, rules, measures, and risks.
- [`delivery.md`](delivery.md) — executable implementation, verification, rollout, and completion tasks.
- [`learnings.md`](learnings.md) — decisions, findings, delivery questions, and revisit triggers.
- [`prd.md`](prd.md) — product story, acceptance criteria, experience requirements, and exclusions.
- [`tech-docs.md`](tech-docs.md) — scheduler, backup, schema, UI, authorization, and rollout design.
