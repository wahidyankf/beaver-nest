# Business Requirements — Backup Integrity

## Goal

The household can trust the word `verified`. The ledger is what the administrator reads on the Schedules page and what
anyone consults after a failure. If it says a backup was verified and the backup is gone, the household learns that
only on the day it needs the backup.

## Roles Served

- **Household operator (the repository owner):** reads the ledger, owns the Dropbox account and the machine, and is the
  only person who can run a restore.
- **Family members:** never see backups, but their chat, learning and preference data is what the backups protect.

## Problem

Two nightly production backups (the slots of 2026-09-30 and 2026-10-01 UTC) are recorded as verified while neither
artifact nor receipt exists on disk. Neighbouring nights are intact. Nothing in Bnest reported the gap; it was found
only by an incidental read-only inspection. The cause is unknown, so it may recur, and a recurrence would be as
silent.

## Outcomes

1. The cause of the loss is known and recorded with checkable evidence, or the plan records exactly what could not be
   established and why. The owner cannot read Dropbox's web history, so a Dropbox cause may legitimately end unproven.
2. A verified run with no matching artifact on disk is reported, by name and date and without private paths, no later
   than the next reconciliation, and the administrator sees it on the Schedules & backups page without running a
   command.
3. A failure mode that is shown to be possible is made impossible by a test that fails if it returns.
4. The owner has restored one real production backup into an isolated root and recorded that it is readable.

## Non-Goals

- Rebuilding the lost artifacts, or reconstructing the two nights.
- Building a new backup destination, off-site copy, or encryption scheme. An idea brief records the off-Dropbox second
  copy option once the cause is known, with no commitment to build it.
- Changing how often backups run or how many dates retention keeps.
- Any change to what is backed up.

## Business Risks

| Risk                                                | Consequence                                 | Mitigation                                                                        |
| --------------------------------------------------- | ------------------------------------------- | --------------------------------------------------------------------------------- |
| The investigation touches production data           | Breach of the read-only and test-data rules | Every production step is read-only, owner-approved, and sanitized                 |
| A fix ships before the cause is known and masks it  | The loss recurs under a different mechanism | The detector is built first and is independent of the cause                       |
| The release disturbs the 24/7 service               | Household loses chat or login               | Candidate cutover with numeric responsiveness budget and drain                    |
| The cause is the owner's Dropbox or a second device | No repository change fixes it               | The verdict has a "no code fix" branch that ships only detector, drill            |
| The cause is Dropbox and its history is unavailable | The cause stays unproven and may recur      | Detector, page label and drill ship anyway; an idea brief records the second copy |
| The page label slows or falsely alarms the admin    | The household stops trusting the page       | Same window rule as retention; check runs off the render path under a ceiling     |
| The restore drill proves a backup unrestorable      | Every backup since is suspect               | That is the point of the drill; the outcome is recorded and escalated             |
