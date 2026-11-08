# Architecture Decision Records

Decision records for Beaver Nest. Files are named `NNN-<slug>.md`; numbers are never reused; only the status line of an
accepted record changes.

## Directory Map

- [001. Fresh real SQLite database for every database-touching test](001-fresh-database-per-test.md) (Accepted) spawns,
  migrates, seeds and deletes one real database per integration test and per E2E scenario, behind a test-only,
  header-guarded control surface that is compiled out of production.
