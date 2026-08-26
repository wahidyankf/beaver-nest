# Test Identities

Use synthetic identities for every automated or manual test that creates an account, session, or user-owned runtime record. Never reuse a real person's username, account, browser profile, session, or data root.

## Identity and Isolation

- Prefix every test username with `test-user-`; add suite and unique run identifiers, for example `test-user-auth-<run-id>`.
- Give each filesystem run `data/test/runs/<run-id>/` and a dedicated browser profile/context. Fail closed if the root is outside that run directory, resolves beneath `data/prod/`, or is shared.
- Start the test application process with its `data/test/runs/<run-id>/` root before account bootstrap. Its account index and user-facing lists must read only that root; synthetic accounts must never appear in production.
- Store only synthetic payloads. Do not copy live chat, learning, preference, credential, cookie, or session values into fixtures or evidence.
- Test concurrent users with separate generated IDs and directories; never mutate an existing user's record to simulate another identity.
- Give parallel projects or workers distinct synthetic identities and therefore distinct user-owned paths. A shared marked run root does not make shared account data safe; no test may assert a mutable aggregate that another worker can change.

## Production Schema Inspection

Development may read `data/prod/` only through a read-only structural audit that compares schema versions, record types, field names, and value types with synthetic test records. This is inspection, not a behavior test: never authenticate as a real user, invoke a real session, copy a production record into test data, or read a payload to derive a fixture.

The audit must not write, lock for mutation, normalize, migrate, or repair production. Its output contains only pass/fail by public record type and schema version—never usernames, user IDs, paths containing identifiers, counts, hashes, password verifiers, sessions, chat, learning, preferences, or field values. Follow [public-repository data safety](../conventions/public-repository-data-safety.md) for all evidence.

## Cleanup

Create a marker containing the synthetic run ID inside the run root. Cleanup runs in the suite's `finally`/`on_exit` path and removes only that exact validated run root after browsers and servers stop.

A scheduled stale-run cleanup may remove abandoned roots only beneath `data/test/runs/` after validating the marker and retention threshold. Never delete from production or a shared root by username prefix, glob, or age alone.

If a failure needs retained evidence, preserve only safe logs, fixture names, and checksums outside the runtime root; never retain passwords, cookies, private payloads, or machine identifiers. Cleanup failure fails the test or quality gate and reports the exact retained synthetic path without deleting unrelated data.
