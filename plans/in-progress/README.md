# In Progress

This stage contains only plans being actively executed. Keep the plan status, `delivery.md` checklist, and `learnings.md` log synchronized with actual work.

Start work by moving one folder from [`../backlog/`](../backlog/README.md) without renaming it. Complete work only after required outcomes, acceptance conditions, verification, learnings, and conditional tasks are reconciled. Then follow [plan execution](../../repo-governance/workflows/plan/plan-execution.md) for the collision-safe dated move and same-change stage-index/map updates.

## Active Plan

- [`backup-integrity/`](backup-integrity/README.md) is in execution (Phases 1 and 2 first). It establishes why two verified production backups are absent from disk and adds a detector, a Schedules-page label and a restore drill.

Completed records live in [`../done/`](../done/README.md), and additional candidates are queued in
[`../backlog/`](../backlog/README.md).

## Directory Map

- [`backup-integrity/`](backup-integrity/README.md) — establishes why two verified production backups are absent from disk, adds a detector for a verified run without an artifact (a Mix task, a log line, telemetry and a label on the Schedules page), and gives the owner a restore drill.
