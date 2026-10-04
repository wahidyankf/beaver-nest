# Off-Dropbox Backup Second Copy

Keep a second copy of the nightly database backup somewhere that is not the Dropbox-synced folder. Provenance: approved
by the owner as an idea brief on 2026-10-03 (decision OD-4 of the `backup-integrity` plan) and written on 2026-10-04
from the owner-confirmed cause verdict `C-UNPROVEN`. Building a second copy is not committed.

## Problem / Context

Two nightly backups were lost between 2026-10-02 and 2026-10-03 (WIB): the runs of 2026-09-30T19:00Z and
2026-10-01T19:00Z are verified in the ledger but absent from the backup folder, while 5 of the 7 retained runs are
present. The read-only investigation of the `backup-integrity` plan could not prove why. The verdict is `C-UNPROVEN`,
and the owner confirmed it on 2026-10-04: no repository-side cause was proven, a Dropbox-side deletion, move or
conflict (`C-DROPBOX`) stays open because the folder's event history is not available, and a test run that resolved the
real destination (`C-TEST`) stays open because no record of a test run in the loss window is retained.

The exposure is the same whichever of the two open candidates is true. Every backup lives in one directory that a
third-party sync client also manages, and nothing outside that directory records that a backup was ever there. The
ledger and the reconciliation detector the plan adds will now report a lost night, but they can only report it: the
backup itself is gone.

## Why Now

Not urgent. The detector turns a silent loss into a reported one, and the restore drill proves that a surviving backup
restores. Neither brings a lost backup back. The brief is recorded now, while the loss is a fresh and concrete case,
and so that a later reader finds the reasoning without re-deriving it.

## Prior Art / Precedents

No internet research applies. The repository's own precedent is the destination rules in
`repo-governance/conventions/runtime-flat-file-data.md`: one marked destination, one newest pair per date, retention of
the seven latest dates.

## Proposed Direction (Sketch)

After a backup is verified and promoted, copy the artifact and its receipt to a second destination that no Dropbox
client manages, with its own marker and its own retention of the seven latest dates. The second destination would be
configured the same way as the first, would be written only by the backup task, and would be reconciled by the same
detector, so a lost copy on either side is reported by date.

## Rough Scope & Non-Goals

In scope: a second configured destination, its marker and retention, and reporting a missing copy on either side.

Out of scope: encryption at rest, a hosted object store, restoring automatically, and any change to the first
destination or to what a backup contains.

## Risks & Open Questions

- Which location is genuinely independent of the Dropbox client on this host, and who owns its capacity and its own
  failure? A second copy on the same disk only moves the question.
- The second copy holds the same household chat content as the first, so the same data-safety posture applies to it.
- A second destination doubles the places a misconfigured test could write to; the isolation pins the plan adds would
  need to cover it.
- If the cause is later proved to be a repository-side defect, the second copy may be unnecessary.

## What Success Looks Like + Promotion Signal

Success: after any one night's backup is deleted from either location, the other still restores, and the detector names
the date that is missing.

Promotion signal: a further backup lost from the Dropbox folder, a Dropbox event history that proves the folder
removed the files, or the owner choosing to invest in a second location promotes this brief to a plan. A proven
repository-side cause with a fix retires it.
