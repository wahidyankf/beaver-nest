# Release Authorization

Do not run a production release (`release:run`, in any mode) unless the user has explicitly authorized releasing the
revision, or a user-approved plan explicitly includes the release step being run.

## Requirements

- One authorization for a revision covers that revision's entire documented release sequence, including a required
  `--mode experience` re-promotion that restores a feature flag the compatibility release ships off by design (see
  the [release guide](../../docs/how-to-guides/releasing-bnest.md)). Do not pause between the steps of one documented
  sequence for a second confirmation.
- A deferred or queued outcome (HIPPO capacity, or another release holding the host lock) is not a failure; retry
  once its cause clears without asking again.
- A different revision, or a release not already covered by a standing authorization, needs its own confirmation.
- Do not infer release authorization from a request to fix, test, land, or merge code; landing a change and
  releasing it remain separately authorized.

Bounding authorization to the revision, not the individual step, keeps an already-approved release moving through
its full documented sequence without repeated interruption, while still requiring a human decision before a new
revision reaches production.
