# Backlogs

This stage contains complete plans that are ready to queue but are not being executed. Each plan lives in one kebab-case folder without a date prefix.

Every plan folder contains `README.md`, `brd.md`, `prd.md`, `tech-docs.md`, and `delivery.md`. It also carries `learnings.md` as a transient execution log. An `evidence/` folder is optional and should be created only when delivery produces committed evidence files.

Before starting work, confirm that the plan still matches current repository evidence and specifications. Move its folder unchanged to [`../in-progress/`](../in-progress/README.md), update its status, and update both stage indexes in the same change.

## Backlog Plans

- [Bnest centralized data](bnest-centralized-data/README.md) proposes login-protected, per-user Bnest persistence with non-destructive browser and legacy-data migration.
- [Family app foundation](family-app-foundation/README.md) proposes authenticated access, durable shared data, document processing, backups, and releases beyond the current as-built Bnest system.

## Directory Map

- [Bnest centralized data](bnest-centralized-data/README.md) contains the queued login and centralized-data plan.
- [Family app foundation](family-app-foundation/README.md) contains the queued foundation plan.
