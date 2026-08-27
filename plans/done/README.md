# Done

This stage preserves completed plans as historical delivery records. A completed plan folder uses `YYYY-MM-DD__<slug>`, where the date records completion rather than creation.

Before archiving, reconcile required and conditional delivery, acceptance, verification, and learnings. Follow [plan execution](../../repo-governance/workflows/plan-execution.md) to refuse destination collisions, record completion metadata, move the folder from [`../in-progress/`](../in-progress/README.md), update both stage indexes/maps in one change, and verify the archive itself. Do not treat completed plans as current architecture; use [`specs/`](../../specs/README.md) for as-built truth.

## Completed Plans

- [Bnest centralized data](2026-08-26__bnest-centralized-data/README.md) completed authenticated per-user persistence, non-destructive browser migration, and safe primary cutover.
- [Single-machine release simplification](2026-08-27__single-machine-release-simplification/README.md) completed deterministic one-machine Caddy release evidence, automatic recovery coverage, and the pending-chat regression repair.

## Directory Map

- [Bnest centralized data](2026-08-26__bnest-centralized-data/README.md) contains the completed login and centralized-data delivery record.
- [Single-machine release simplification](2026-08-27__single-machine-release-simplification/README.md) contains the completed release-process assessment and delivery record.
