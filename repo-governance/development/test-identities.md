# Test Identities

## Iron Rule

No automated or manual test may read, write, authenticate against, migrate, back up, lock, derive fixtures from, or otherwise touch a production user, production data, or a production user context. Every test must use synthetic identities and payloads inside validated per-run test roots. If isolation cannot be proven before the subject starts, fail closed. An exemption, debug session, local environment, or convenient fixture cannot relax this rule.

## Identity and Isolation

- Prefix every test username with `test-user-`; add suite and unique run identifiers, for example `test-user-auth-<run-id>`.
- Give each filesystem run a flat-file root at `data/test/runs/<run-id>/`, a SQLite root at `~/bnest/data/test/runs/<run-id>/`, and a dedicated browser profile/context. Both roots must carry the same run marker. Fail closed if either root is outside its exact parent, resolves beneath a production root, has a mismatched marker, or is shared.
- Start the test application process with both isolated roots before account bootstrap. Its account index and user-facing lists must read only that run's SQLite database; synthetic accounts must never appear in production.
- Store only synthetic payloads. Do not copy live chat, learning, preference, credential, cookie, or session values into fixtures or evidence.
- Test concurrent users with separate generated IDs and directories; never mutate an existing user's record to simulate another identity.
- Give parallel projects or workers distinct synthetic identities and therefore distinct user-owned paths. A shared marked run root does not make shared account data safe; no test may assert a mutable aggregate that another worker can change.

## Production Schema Inspection

Development may read `data/prod/` only through a read-only structural audit that compares schema versions, record types, field names, and value types with synthetic test records. This is inspection, not a behaviour test: never authenticate as a real user, invoke a real session, copy a production record into test data, or read a payload to derive a fixture.

The audit must not write, lock for mutation, normalize, migrate, or repair production. Its output contains only pass/fail by public record type and schema version—never usernames, user IDs, paths containing identifiers, counts, hashes, password verifiers, sessions, chat, learning, preferences, or field values. Follow [public-repository data safety](../conventions/public-repository-data-safety.md) for all evidence.

## Cleanup

Create a marker containing the synthetic run ID, owner process, and host inside both run roots. Cleanup runs in the suite's `finally`/`on_exit` path and removes only that exact validated pair after browsers and servers stop.

A scheduled stale-run cleanup may remove abandoned roots only beneath repository `data/test/runs/` and local `~/bnest/data/test/runs/` after validating each marker, owner inactivity, and the 24-hour retention threshold. Never delete from production or a shared root by username prefix, glob, or age alone.

If a failure needs retained evidence, preserve only safe logs, fixture names, and checksums outside the runtime root; never retain passwords, cookies, private payloads, or machine identifiers. Cleanup failure fails the test or quality gate and reports the exact retained synthetic path without deleting unrelated data.
