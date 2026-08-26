# Runtime Flat-File Data

Use local flat files only for small, private runtime data below `data/`. This convention applies to every application, tool, and agent that reads or writes that directory.

## Layout

- `data/prod/` is the only live runtime root.
- `data/test/runs/<run-id>/` is the only filesystem root for one test run. It mirrors production and must never be shared between runs.
- Each root contains `general/` for repository-wide shared data, `apps/<app-name>/` for application-owned shared data, `users/<user-id>/` for one user's records, and `system/` for operational state.
- Root-level `data/{general,apps,users,system}/` paths are legacy migration sources only. Do not create new records there or delete them without an explicit archival plan.

## File Rules

- Keep all runtime data ignored by Git; only approved directory placeholders may be tracked.
- Configure each process with one resolved runtime root before it starts. Production must resolve `data/prod/`; filesystem tests must resolve a unique `data/test/runs/<run-id>/`.
- Never let a test fall back to production. Abort before mutation when its root, marker, or run identity cannot be proven.
- A development schema audit may inspect `data/prod/` read-only under the [test-identity standard](../development/test-identities.md); it is not a test root and cannot supply fixtures or expose values.
- Keep each activity in its own subdirectory, for example `<runtime-root>/users/<user-id>/sifat-allah/progress.json`.
- Persist UTF-8 JSON with an explicit schema version, validate it when reading, and use atomic replacement when writing.
- Never derive a file path directly from browser or other external input.

Flat files are an interim local-storage mechanism. Revisit this convention when the planned private database volume becomes available.
