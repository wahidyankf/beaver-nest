# Restore Root and Backend E2E Snapshot Hardening

Two small test and cleanup gaps found while moving production to a Linux host, both left unfixed because neither
blocked the move.
Provenance: recorded 2026-10-24 from the review of the restore-validation pull request and the diagnosis of a failed
routine release.

## Problem / Context

- **A restore can leave its isolated root behind.** `isolated_restore_root!/0` in
  `apps/bnest-app/lib/bnest_app/backup/adapters/sqlite_database_snapshot.ex` creates the root before the `try` that
  removes it. A failure between the directory creation and the `try` leaves a `bnest-restore-` folder under the
  system temporary directory. The review of the restore-validation change noted it; the code path has no
  fault-injection seam, so a test cannot reach it today.
- **The backend e2e snapshot helper copies a live lock lease.** `captureStorageAuthority` in
  `apps/bnest-app-be-e2e/tests/support/storage-authority.ts` copies the whole runtime root, including the storage
  lock folder. `restoreStorageAuthority` later puts that copy back, so a lease that was live at capture time returns
  after the run. The browser e2e helper had the same defect: it made a routine release fail with "storage drain lock
  timed out", and its fix keeps the lock folder out of the copy. The backend helper still copies it.

## Why Now

Not urgent. The backend helper has not failed a release yet. It is the same shape that did fail in the browser suite,
so the next change to the order of the e2e steps can expose it.

## Prior Art / Precedents

- The browser helper fix (pull request 197) skips the lock folder and carries five tests. It is the model for the
  backend helper.
- [Browser suite timing reliability](browser-suite-timing-reliability.md) records the same "storage drain lock timed
  out" failure among its causes and suspects a lease that outlives its test. Pull request 197 fixed that mechanism for
  the browser helper; this brief carries the fix to the backend helper and adds the restore root. Fold the two if that
  brief is promoted first.

## Proposed Direction (Sketch)

1. Give the backend helper the same exclusion and the same tests as the browser helper, ideally by sharing one
   implementation.
2. Add a seam to the restore-root creation, for example an injectable directory maker, so a test can fail between
   creation and cleanup, then move the creation inside the guarded block.

## Rough Scope & Non-Goals

In scope: the two items above, each with a failing test first. Out of scope: any change to what a restore validates, and
any change to the lock protocol itself.

## Risks & Open Questions

- Whether sharing one helper across two e2e projects is worth a new library boundary or two copies are cheaper.
- Whether the lock folder should instead be created outside the runtime root, which would remove the need for any
  exclusion.

## What Success Looks Like + Promotion Signal

Success: both gaps are closed by tests that fail before the change. The first backend e2e failure that mentions a drain
lock, or any `bnest-restore-` folder left in the system temporary directory of a production host, promotes the
matching item to a plan.
