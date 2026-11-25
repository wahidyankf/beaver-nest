# 008. Remove the family-chat release flags and ship every release in one stage

Date: 2026-11-25

Status: Accepted (2026-11-25). Supersedes the release procedures of tech-docs 007/009 and the
[release-stage flag posture brief](../../../plans/ideas/q1-urgent-important/release-stage-flag-posture.md),
which are history and are not rewritten.

## Context

A Bnest release ran in two stages. The compatibility stage shipped the artifact with every feature flag off;
the experience stage re-promoted the same artifact with `BNEST_FAMILY_CHAT_ENABLED` and
`BNEST_FAMILY_CHAT_REPLY_ENABLED` on. The split existed for one documented reason: the server had to answer a
reply-aware GraphQL document whichever way the reply flag was set, so the reply bundle shipped one release ahead
of the revealing flag.

The posture brief measured the cost: every two-stage release left a 6–44 minute window in which the room was
absent from production while readiness stayed green, bounded only by how quickly an operator ran the second
command. Its proposed fix (carry the flag posture forward) was rejected: it couples each release to the slot it
replaces, needs an empty-host default, and requires the operator to declare what is new per release.

## Decision

Full flag removal, not carry-posture-forward:

- Delete `BNEST_FAMILY_CHAT_ENABLED`, `BNEST_FAMILY_CHAT_REPLY_ENABLED`, the
  `family_chat_enabled?/require_family_chat_enabled` gate, and the entire experience stage
  (`executeExperienceRelease`, `experienceGateManifest`, `experiencePreflight`,
  `prepareExperienceCandidate`, `--mode`). Passing `--mode` at all fails closed with an error naming the
  removal.
- Every release builds one artifact that serves the room and reply surfaces live from first promotion.
- The two-member draft/offline/exact-once proof survives as an ordinary gate (`release-family-chat-e2e`)
  against the ordinary candidate, before promotion.
- The real authorization boundary — `authenticated_browser` plus the resolver's `use_family_chat`
  capability — is untouched, so no unauthenticated surface opens.

## Why one stage stays safe

The split's one reason still holds trivially after removal: `family_chat_types.ex` exposes `replyTo`
unconditionally, the resolver handles `reply_to_message_id` unconditionally, and `operations.js` builds every
document from one source. With no flag, the bundle always requests `replyTo` and the same artifact always
answers it. Server-before-bundle ordering becomes vacuous — code and surface turn on atomically at the Caddy
cutover, like every other feature.

## Consequences

- Rollout: flags are runtime config baked into the booted slot, so the currently routed slot stays flag-gated
  until a new single-stage artifact promotes. Land, then run one ordinary `release:run --revision <new-sha>`;
  the room and replies go live at that promotion, with no second step. In-flight revisions built before this
  change remain flag-gated artifacts and must never be promoted with ad-hoc flags after the tooling stops
  accepting them.
- Rollback gap (the one real regression): rolling back past this change lands on a flag-gated revision whose
  environment omits the flags, so the room 404s again. Once one always-on release is routed, treat it as the
  rollback floor; before that, rollback equals old behavior.
- Cached bundles across cutover are safe in both directions (an old document without `replyTo` against a
  superset server; the new bundle is only ever served by the new server), but the transition release's
  verification still samples the room from a warm browser profile.
- Unchanged: migration/converge/rollback behavior, blue/green slot topology, Caddy cutover, `gateManifest`'s
  other entries and budgets, and the five-minute warm-prior-slot observation.
