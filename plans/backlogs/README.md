# Backlogs

This stage contains complete plans that are ready to queue but are not being executed. Each plan lives in one kebab-case folder without a date prefix.

Every plan must clearly communicate why it exists, the options and selected decision, and how it will be executed and proved. Each folder contains `README.md`, `brd.md`, `prd.md`, `delivery.md`, `learnings.md`, and exactly one technical shape: coherent `tech-docs.md`, or `tech-docs/README.md` with mapped companions whose reader jobs and ownership justify the split. Shape is only a communication mechanism and file length only a review signal. An `evidence/` folder is optional and should be created only when delivery produces committed evidence files.

Before starting work, confirm that the plan still matches current repository evidence and specifications. Move its folder unchanged to [`../in-progress/`](../in-progress/README.md), update its status, and update both stage indexes in the same change.

## Backlog Plans

- [Bn​est daily backups and schedules](bnest-daily-backups-and-schedules/README.md) — reusable contextual OTP/SQLite schedules, verified daily production backups, and typed admin settings.

## Directory Map

- [`bnest-daily-backups-and-schedules/`](bnest-daily-backups-and-schedules/README.md)
