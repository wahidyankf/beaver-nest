# Family Chat Reply Flag Retirement

Remove `BNEST_FAMILY_CHAT_REPLY_ENABLED` and its branches once the rollback window for quoted replies has closed.
Provenance: deliberately deferred by the `family-chat-message-reply` plan, 2026-09-22.

## Problem / Context

Quoted replies shipped behind a runtime flag so the reply-aware GraphQL field could reach every routed backend one
release before any bundle asked for it. That staging is done: revision `5b08a27f2` is routed with the flag on, and
the recorded rollback floor is the same revision with it off.

The flag now costs more than it buys. It is read in the controller, threaded to the room template, branched on in
the browser bundle, and carried by the release tool as a slot argument. Two of the specification's scenarios exist
only to describe the off posture. Every one of those is a branch a future change has to keep working, for a
posture nobody intends to return to.

Leaving it also leaves a trap: the flag is independent of `BNEST_FAMILY_CHAT_ENABLED`, and the two being separate
variables is load-bearing today but will read as an accident once the reason has passed.

## Why Now

Not now — that is the point of the quadrant. The flag should outlive at least one release cycle in which replies
are routed and nothing has needed the floor. Retiring it earlier removes the escape hatch before it has been shown
to be unnecessary; retiring it much later means every intervening change pays the branch tax.

## Prior Art / Precedents

- The repository has removed release flags before; the pattern is a plan whose first delivery unit deletes the
  branches and whose second deletes the specification's off-posture scenarios, so the corpus never describes
  behaviour the code no longer has.

## Proposed Direction (Sketch)

Delete the variable and collapse each branch to its enabled side: the controller assign, the template's
`data-family-chat-reply-enabled` attribute, the bundle's guard, and the release tool's slot argument. Remove the
two scenarios that describe the off posture, and the plan's compatibility-release scenario with them. Keep
`BNEST_FAMILY_CHAT_ENABLED`, which gates a different thing for a different reason.

## Rough Scope & Non-Goals

In scope: the flag, its branches, its scenarios, and the release tool argument.

Out of scope: the reply feature's behaviour, which does not change; the room flag; and the compatibility-release
mechanism itself, which the next feature will want.

## Risks & Open Questions

- How long is "the rollback window"? A number of days is arbitrary; a number of releases is more honest, and one
  clean release cycle is the smallest defensible answer.
- Removing the off-posture scenarios removes the only automated description of a bundle meeting an older server.
  Something should still cover that shape for the _next_ staged feature, which argues for generalising the
  compatibility scenario rather than deleting it outright.

## What Success Looks Like + Promotion Signal

Success: no `BNEST_FAMILY_CHAT_REPLY_ENABLED` anywhere, no scenario describing a posture the product cannot be in,
and the reply feature behaving exactly as it does today.

Promotion signal: one full release cycle with replies routed and the floor untouched promotes this brief to a plan.
