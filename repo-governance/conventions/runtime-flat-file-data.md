# Runtime Flat-File Data

Use local flat files only for small, private runtime data below `data/`. This convention applies to every application, tool, and agent that reads or writes that directory.

## Layout

- `data/prod/` contains legacy production migration sources until verified retirement; new authoritative production records live in machine-local SQLite storage.
- `data/test/runs/<run-id>/` is the flat-file fixture root for one test run. It pairs with `~/bnest/data/test/runs/<run-id>/` for SQLite and must never be shared between runs.
- `data/backup/` is the sole repository-contained production backup destination. Bnest may create only its marker and verified SQLite artifact/receipt pairs there; Dropbox may synchronize the ignored directory, but synchronization is not authoritative storage or complete disaster recovery.
- Each root contains `general/` for repository-wide shared data, `apps/<app-name>/` for application-owned shared data, `users/<user-id>/` for one user's records, and `system/` for operational state.
- Root-level `data/{general,apps,users,system}/` paths are legacy migration sources only. Do not create new records there or delete them without an explicit archival plan.

## File Rules

- Keep all runtime data ignored by Git; only approved directory placeholders may be tracked.
- A backup destination inside the repository must resolve exactly to `data/backup/` and pass `git check-ignore`; reject every other repository path, symbolic-link path, live-database overlap, and private-config overlap. Outside-repository overrides remain private machine-local configuration.
- Delete only artifacts whose strict receipt and destination marker prove Bnest ownership. Keep one newest verified pair for each of the latest seven WIB calendar dates, preserve unknown files and previous destinations, and never back up credentials, retired flat files, WAL/SHM files, browser storage, or Codex state.
- Configure each process with one resolved storage profile before it starts. Production SQLite defaults to `~/bnest/data/prod/`; filesystem tests must resolve a unique paired run below both test parents.
- Never let a test fall back to production. Abort before mutation when its root, marker, or run identity cannot be proven.
- A development schema audit may inspect `data/prod/` read-only under the [test-identity standard](../development/test-identities.md); it is not a test root and cannot supply fixtures or expose values.
- Keep each activity in its own subdirectory, for example `<runtime-root>/users/<user-id>/sifat-allah/progress.json`.
- Persist UTF-8 JSON with an explicit schema version, validate it when reading, and use atomic replacement when writing.
- Never derive a file path directly from browser or other external input.

Production flat files are migration sources, not an ongoing rollback mirror. Retire them only when every source checksum is accepted by the authoritative SQLite migration evidence and the routed service proves the expected database generation. Flat-file test fixtures remain supported where they exercise migration behavior.
