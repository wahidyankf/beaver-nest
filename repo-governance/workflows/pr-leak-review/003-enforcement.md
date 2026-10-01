# Enforcement

A precondition stated only in prose is a convention someone forgets. The leak review is enforced in three layers; each fails closed.

## The Screen

The [public-safety screen](../../../scripts/public-safety/README.md) runs at the `pre-push` hook, before anything else the hook does, and on every pull-request range. Its `public-safety-range` gate screens the range commit by commit: each commit's added lines at the line numbers they occupy, its file names, its message, and the ref IDs. A merge contributes what it resolved beyond the automatic merge. Content the range did not add is not screened again, so the screen binds from adoption onward. Its shapes include absolute home paths, private addresses, and internal hostnames, beside a credential scanner.

The screen matches shapes; the review reads context. Neither replaces the other.

## Hosted Checks

- **Range screen.** The `Quality gate` check from [`pr-quality-gate.yml`](../../../.github/workflows/pr-quality-gate.yml) replays the range screen over the pull request's base-to-head range on every head, because a local hook can be skipped and a hosted check cannot.
- **Record check.** [`leak-review.yml`](../../../.github/workflows/leak-review.yml) runs the [record check](../../../scripts/leak-review/README.md) and publishes the `leak-review` commit status on the live head: `success` only when the repository owner's latest undismissed review on that head carries a `pass` record naming this repository, this pull request, and that head. It runs when the pull request changes and when a review is submitted, so posting the record turns it green without a new commit.

The `main` ruleset must require both as status checks. A waiver of other gates never covers either.

## Repository Decisions

- Record marker: `ose-pr-leak-review`, which never changes afterward.
- Reviewer identity: the repository owner.
- Required checks: `Quality gate` and `leak-review`.
- Integration path: pull request, per the [integration path](../../conventions/integration-path.md).
