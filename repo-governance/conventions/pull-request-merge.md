# Pull Request Merge

Merging is an external, irreversible action on the trunk, and its authority comes from the hardened preconditions below rather than from a prompt at the moment of merging. Once all of them hold, `[AI]` merges by default; a `[HUMAN]` gate applies only where a plan's own step says so. Preconditions are evaluated per merge, and satisfying them for one pull request says nothing about the next. This authority covers the merge alone: the commits and pushes that built the branch stay separately authorized under the [commit-authorization convention](commit-authorization.md).

## Preconditions

All five must hold at the moment of merge:

- **Exact-head quality gate.** The `Quality gate` check from [`pr-quality-gate.yml`](../../.github/workflows/pr-quality-gate.yml) is green for the pull request's current head SHA and its current base branch. A run against an earlier head or a different base is stale evidence and authorizes nothing.
- **Data-safety review of that same head.** One review of the pull request's current diff finds no content prohibited by the [data-safety convention](public-repository-data-safety.md): credentials, personal or machine identifiers, private network or infrastructure identifiers, or artefacts carrying them. Pin the head SHA before reading and record it with the result. A push that moves the head voids the result; review the new head once, never accumulate a streak of clean runs. Report a finding by category, location, and remediation, and never by repeating the value.
- **Branch currency.** The branch is current with `main`, brought forward by rebase, and GitHub reports no conflict.
- **Conversations.** Every review conversation is resolved, or dismissed by the user. A review is not required, but conversations one produced still bind.
- **Surface gates.** Every gate the changed reachable behaviour requires has a passing terminal result. When no reachable behaviour changed, say so explicitly rather than leaving the question open.

The `main` ruleset requires no approving review, because the sole maintainer cannot approve their own pull request and requiring one would block every merge. These preconditions, not a reviewer, are what stands in for that.

## What Safety Means Here

A pull request is safe when two of those hold: its diff leaks nothing, and the `Quality gate` check passes on its exact head. Nothing else stands between a change and the trunk — no approving reviewer, and no human reading every line before merge. The remaining preconditions are integration hygiene: they keep history linear, conversations closed, and changed surfaces exercised, and they are not the safety claim.

This is why the repository's testing and development practices carry weight rather than ceremony. Whatever the gate does not exercise, nothing checks. [Test-driven development](../development/test-driven-development.md), the [specification corpus](../development/specification-maintenance.md), unit coverage, integration and end-to-end suites, and the manual evidence the [software-quality map](../development/software-quality-enforcement.md) requires are what give the gate something to fail on. Weakening any of them does not merely lower quality; it silently widens what this convention is willing to call safe.

## Draft Lifecycle

Open every pull request as a draft with `gh pr create --draft`. Iterate on the branch while it stays a draft, driving the exact-head gate green. Flip it to ready only when the work meets its done definition. Readiness is a statement that the work is finished; it is not a merge authorization, and no precondition is satisfied by it.

## Findings and Bypass

A suspected exposure stops merge handling: contain and rotate the credential, then follow the [data-safety convention](public-repository-data-safety.md) for history already written. A green gate, a resolved conversation, or an earlier clean review never authorizes merging a contaminated pull request.

Never bypass a failing or pending gate, an unresolved conversation, or branch protection. A user may waive a specific gate for a specific merge by naming it; that waiver covers nothing else, and it never covers the data-safety review. Repairing a gate failure follows the [push-hook verification convention](push-hook-verification.md): fix the cause.
