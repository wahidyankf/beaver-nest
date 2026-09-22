# Release Stage Flag Posture

Stop a compatibility release from switching off features it was never releasing, and let its preflight notice a
checkout whose installed dependencies no longer match the lockfile. Provenance: execution learning captured
2026-09-22 during `family-chat-message-reply` delivery.

## Problem / Context

A Bnest release runs in two stages. The compatibility stage ships the artifact with every feature flag off; the
experience stage re-promotes the same artifact with them on. The release guide tells the operator to follow the
first "immediately" with the second, and nothing enforces it.

The consequence is that the compatibility stage turns off features that were already live and have nothing to do
with the release. On 2026-09-22 the routed slot carried `BNEST_FAMILY_CHAT_ENABLED = true`; the compatibility
promotion replaced it with a slot that omits the variable entirely, so the family chat room was gone from
production until the experience promotion eight minutes later. Nothing failed, no probe went red, and the readiness
endpoint answered `200` throughout — the feature was simply absent.

This is not particular to one release. Every two-stage release in the deployment log shows the same gap:

| Revision    | Compatibility → experience |
| ----------- | -------------------------- |
| `423164cce` | 44.6 min                   |
| `c24ecac7b` | 19.9 min                   |
| `f28196196` | 6.5 min                    |
| `91e0201df` | 16.4 min                   |
| `5b08a27f2` | 8.0 min                    |

A second, smaller gap surfaced in the same session. The first release attempt stopped at `pre-artifact-gates`
because `tsc` could not resolve a dependency that the merged lockfile contains: the pull request had landed from a
`worktrees/` checkout, and the primary checkout's `node_modules` predated the merge. The gate caught it correctly
and nothing was built — but the preflight already asserts branch, clean tree, and `HEAD == origin/main`, and this
belongs in the same list. `git status` is clean either way, so nothing signals it.

Both observations are shape only; no private value, hostname, or user data appears here.

## Why Now

Bnest is a 24/7 household service, and the flag gap is an availability defect that the continuity budget cannot
see: readiness stays green while a feature is missing. The window is operator-paced, so it is bounded only by how
quickly a person runs the second command — 44 minutes on one past release. The change is small and the evidence is
already collected.

## Prior Art / Precedents

- [Zero-downtime local rollouts](zero-downtime-local-rollouts.md) records the sibling lesson that a healthy proxy
  does not imply an available application. This brief is the release-stage version of the same blind spot.
- The repository's own [integration path](../../../repo-governance/conventions/integration-path.md) already names
  the stale-primary-checkout trap for `main`; the dependency half is that trap one layer down.

## Proposed Direction (Sketch)

Two independent changes, either useful without the other.

1. **Carry the posture forward.** A compatibility release reads the flag posture of the slot it replaces and keeps
   it, turning off only the flags the release is itself introducing. The reply flag would still have shipped off,
   because this release introduced it; the room flag would have stayed on, because it was already live and
   unrelated. The operator names what is new, rather than the tooling assuming everything is.
2. **Add a dependency assertion to preflight.** Alongside the branch, tree, and revision checks, verify that the
   installed tree satisfies the lockfile, and fail with that as the stated reason rather than as a typecheck error
   several gates later.

## Rough Scope & Non-Goals

In scope: the release tool's slot preparation and preflight, and the release guide's wording.

Out of scope: the flag mechanism itself, the two-stage release shape (which exists for good reason — the server
must answer a new document before any bundle asks for it), and any change to what the experience stage does.

## Risks & Open Questions

- Carrying posture forward makes a release depend on the state it replaces, which is a new coupling. A first
  release onto an empty host has no previous slot to read; the posture there has to default to off.
- Is "the flags this release introduces" derivable, or must the operator state it? Deriving it from the diff is
  attractive and probably too clever; an explicit argument is duller and honest.
- The dependency assertion must not tempt anyone into running an install inside the release, which would mutate
  the checkout the release asserts is clean.

## What Success Looks Like + Promotion Signal

Success: a compatibility promotion leaves every already-live feature reachable, and a stale checkout is named by
preflight rather than by a gate failure minutes later.

Promotion signal: a second release that disables an unrelated live feature, or any release whose two stages are
separated by more than a few minutes, promotes this brief to a plan.
