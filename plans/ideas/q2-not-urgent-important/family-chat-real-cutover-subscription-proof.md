# Real-Production-Cutover GraphQL Subscription Continuity Proof

Prove that a live family-chat GraphQL subscription actually survives a real `release:run` Caddy promotion in
production — not just an isolated test environment — with a bounded resubscribe and exact-once gap catch-up.

_Recorded 2026-09-20, on formal v1 descope of [family-chat-room](../../done/2026-09-20__family-chat-room/README.md)'s
AC-FC-10. Explicit user decision: accept as residual risk for v1 rather than build now._

## Problem / Context

AC-FC-10 (`prd.md`) specifies four scenarios for continuity-safe active releases. Two of them — "Connected clients
recover without refresh" and "A commit during socket cutover is caught up exactly once" — require holding
authenticated GraphQL sockets open across a real production Caddy promotion driven by the actual `release:run`
pipeline, observing the prior-slot socket close, the promoted-revision resubscribe within 10 seconds, and exact-once
delivery of a message committed during the gap.

Every real release this delivery ran instead proved `routed-liveview` continuity (zero failed routed HTTP samples,
budgeted latency) — `delivery.md`'s Phase 7–9 release log, e.g. the two 2026-09-20 production releases for revision
`f2819619617f5d62be6348ef6d73932c075a6056`. Phase 8 separately proved the subscribe/resubscribe/catch-up _mechanism_
itself, but against an isolated FE_E2E test environment (`delivery.md:572-594`), not the real production cutover.
Neither constitutes the proof these two scenarios describe, and a `plan-execution-checker` audit confirmed the gap
directly: it's genuinely never been exercised, across every release this plan performed.

## Why Now

Not urgent. The family-chat feature is live in production, both fixes it has needed so far were caught by other
means (manual production testing, not a subscription-continuity failure), and the substitute proofs give reasonable
confidence in the underlying mechanism. Nothing currently forces this.

The signal to act would be: an actual production incident where a client failed to reconnect or missed a message
during a real release cutover, or a second active-service Bnest feature reusing the same subscription pattern where
the combined blast radius justifies building the proof infrastructure once for both.

## Prior Art / Precedents

- **Phase 8's isolated FE_E2E proof** (`delivery.md:572-594`) is the direct mechanical precedent: it proves the
  resubscribe/catch-up logic works correctly in principle, using synthetic promotion events rather than a real
  Caddy cutover.
- **The IndexedDB fix's release-evidence pattern** (`delivery.md`'s Phase 9 "(routed)" notes) shows what a real
  production release's evidence trail looks like when everything it claims actually ran — the bar this idea would
  need to clear.
- **tech-doc 009**'s two-step compatibility/experience release model is the release pipeline this proof would need
  to run against; it does not currently define a telemetry or service-account mechanism for this use case.

## Proposed Direction (Sketch)

Three pieces, each independently useful and each currently missing:

1. **A service-account auth path for the family-chat GraphQL socket.** Today's socket requires a real authenticated
   session; release tooling has no identity to hold one with.
2. **An isolated probe room.** The release migration hard-codes exactly one real family room; posting synthetic
   proof traffic into it risks polluting the one real household's history. A dedicated, excluded-from-retention
   probe room would let release tooling hold a socket and commit synthetic messages without touching real data.
3. **A telemetry/evidence mechanism** recording the resubscribe latency and gap-catch-up result as a named evidence
   stage on the release JSON result, the same way `routed-liveview` and `experience-release-e2e` already do —
   requires a tech-doc 009 amendment to specify it.

Once those three exist, wire a new evidence stage into `release:run` that holds a probe-room socket across the real
promotion and asserts the same properties Phase 8's isolated test already asserts.

## Rough Scope & Non-Goals

**In scope:** the service-account auth path, the probe room, the telemetry mechanism, and the new release evidence
stage, scoped narrowly to what this one proof needs.

**Not in scope:** broadening service-account auth into a general-purpose API-key/service-identity system beyond
what the probe socket needs; touching the one real family room; re-litigating tech-doc 009's release model itself.

## Risks & Open Questions

- **A probe room is still synthetic traffic in production.** It needs its own retention/cleanup story so it doesn't
  quietly accumulate rows forever, and clear labeling so it's never mistaken for a real household.
- **Service-account auth is new attack surface** on a socket that currently only ever authenticates real household
  members. Scope it as narrowly as possible (this one probe room, nothing else) to keep the blast radius small.
- **Open:** is a synthetic-traffic proof against a real cutover meaningfully stronger evidence than the existing
  isolated FE_E2E proof, given the mechanism under test is identical either way? Worth answering before committing
  to the service-account/probe-room investment.

## What Success Looks Like + Promotion Signal

Success is a release evidence stage that proves, against the real production Caddy promotion, that an authenticated
subscription survives cutover with bounded resubscribe and exact-once catch-up — closing AC-FC-10's two deferred
scenarios for real.

**Promote to a plan when** either trigger fires — a real production incident implicating this gap, or a second
active-service feature that would reuse the same probe infrastructure and justify building it once.
