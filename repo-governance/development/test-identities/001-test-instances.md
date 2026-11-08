# 001 Test Instance Layout and Teardown

Read with the [Test identities](../test-identities.md) entrypoint, which owns the rules. This module says where each
test instance lives, what marks it, and who removes it and when.

## Layout

```text
data/test/runs/<run>/                                              run base flat root (marker), no data
data/test/runs/<run>/instances/<inst>/                             flat instance root, flat_primary phase only (marker)
~/bnest/data/test/runs/<run>/                                      run base SQLite root (marker), no data
~/bnest/data/test/runs/<run>/instances/<inst>/                     instance root (marker)
~/bnest/data/test/runs/<run>/instances/<inst>/db/                  test database, bnest.sqlite3
~/bnest/data/test/runs/<run>/instances/<inst>/backup-repository/   isolated git repository for backup tests
```

- The run base holds no data: no users, no account files, and no `*.sqlite3` file.
- A backup repository lives beside `db/`, never inside it, because backup refuses a destination inside the live database
  directory.
- The instance marker carries `schemaVersion: 1`, `recordType: "bnest-test-instance"`, `runId`, `instanceId`, `owner:
"bnest-test-harness"`, and `createdAt`. Write it before the database file exists, so a crash cannot leave an unmarked
  instance directory.
- Create a flat instance root only for the `flat_primary` phase. A `sqlite_primary` instance has none, which keeps
  Dropbox, which syncs `data/`, from syncing many short-lived files.
- The test backup config file in the run base's `storage-config/` is one fixed file. Each spawn and each delete removes
  it.

## Teardown

Validate the markers and the exact paths before removing anything. Never delete by prefix, glob, or age alone.

| When                        | Who                                                                                                                              | What                                                                                                                                                                                                                                                                                                                            |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| After each integration test | ExUnit `on_exit` registered by the spawning setup: `FreshDatabaseCase`, `ConnCase`, or the ExBdd before and after scenario hooks | Drop the instance: stop storage, remove the storage pointer and the instance directories, and restore the "no instance" state.                                                                                                                                                                                                  |
| After each E2E scenario     | Playwright-bdd `After` hook in `lifecycle.steps.ts`; a worker-scoped auto fixture repeats the delete if the hook never ran       | Close the scenario's browser contexts first, then delete the instance over HTTP.                                                                                                                                                                                                                                                |
| End of an integration run   | ExUnit `after_suite`                                                                                                             | Count the leftover instance directories. A leftover fails the run. Then remove the run's root pair.                                                                                                                                                                                                                             |
| End of an E2E run           | `globalTeardown` while the server is still up, then `run-e2e.mts` in its `finally` after Playwright and the servers exit         | `globalTeardown` reads the server state, deletes any current instance, and asserts that the base is data-free. `finally` lists the instance directories in both roots, sets exit code 1 if any remain, then removes the validated root pair.                                                                                    |
| Crash or kill               | `cleanupStaleTestData()` at the start of each `run-e2e.mts` run and on a schedule                                                | Remove run directories older than 24 hours that have a valid marker and a dead owner process. Instances go with their run. Also sweep the legacy `~/bnest/data/test/{family-chat,backup-config,backup-repository}` directories older than 24 hours. They have no marker, so only their age and their exact parent qualify them. |
| Failed teardown             | Any actor above                                                                                                                  | Report the exact retained synthetic path and fail the test. Delete nothing outside the validated pair.                                                                                                                                                                                                                          |
