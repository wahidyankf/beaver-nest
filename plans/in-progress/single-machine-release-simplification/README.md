# Single-Machine Release Simplification

**Status:** In progress — implementation design documented; implementation is not approved  
**Created:** 2026-08-27  
**Started:** 2026-08-27  
**Scope:** Bnest's machine-local release workflow and its operational evidence

## Context

Bnest is a private, 24/7 family service. The requested outcome is a release process simple enough to operate on one machine while keeping user disruption absent or automatically recoverable and avoiding unnecessary steady-state resource use. Users must not need to reload a page after a release or lose progress: if a brief connection interruption occurs, the open page must reconnect or update itself and restore the same usable state. The routine path must also be deterministic and AI-token-efficient: a fixed revision passes fixed, fail-closed gates before an artifact is created, and automation returns concise structured outcomes instead of requiring free-form diagnosis between normal stages. This iteration documents the baseline, alternatives, recommendation, deterministic implementation shape, and required proof. It does not authorize source or active-route changes.

The current repository model is already single-machine blue/green deployment: Tailscale Serve forwards private HTTPS to loopback Caddy on port 4100, and Caddy routes to one Phoenix release slot on port 4000 or 4001. An inactive slot is started, checked directly for readiness and its requested revision, then Caddy is gracefully reloaded to it. The previous slot remains available through the five-minute WebSocket drain and is retired only after routed proof. See [technical documentation](tech-docs.md).

The repository confirms this design in source and governance. Runtime state was not inspected in this session: `proxy:status` correctly refused to run because this shell lacks the required machine-local `BNEST_DEPLOY_ROOT`. That proves neither a healthy nor an unhealthy service; it is an explicit observation gap.

## Recommendation

Keep the existing Tailscale Serve → Caddy → ephemeral blue/green Phoenix topology, but replace the manual operator sequence with one deterministic Nx release transaction. Run fixed gates against one clean `main` revision before building; start the inactive slot only after they pass; verify its revision and user journeys; promote through Caddy; prove routed automatic page recovery and preserved progress; then retire the old process and clean temporary state after the bounded drain.

The intended steady state is Tailscale Serve, Caddy, and one Phoenix release. A second Phoenix VM exists only from candidate preparation through routed proof and drain. Retain the active and one previous verified artifact for cold recovery, not two permanently warm application processes. The current command set supports warm rollback while the previous slot is still prepared; deterministic re-prepare of the retained artifact after retirement is a documented implementation gap. This is the recommended balance because it reuses implemented safeguards, avoids custom hot-upgrade machinery, and limits duplicate resources to the release window. See the [technical recommendation](tech-docs.md#recommendation-and-ranking).

## Scope

- Establish the current release topology, lifecycle, safeguards, and resource shape from repository evidence.
- Compare plausible one-machine operating models against continuity, simplicity, rollback, and resource constraints.
- Treat Caddy as replaceable or removable when a chosen model preserves the availability properties users need with less total operating cost.
- Define a deterministic release state machine with ordered pre-artifact, candidate, routed, rollback, and cleanup gates.
- Define a deterministic Badakmini label-legibility prerequisite so clipped Mermaid text cannot obscure release decisions before push.
- Validate or revise the recommendation with safe runtime measurements before requesting implementation approval.

## Non-goals

- Change the running route, Tailscale Serve, Caddy, release launcher, data root, or credentials in this iteration.
- Introduce cloud hosting, Kubernetes, public exposure, a database, containers, or new deployment infrastructure without a later decision.
- Describe a single-process stop/start as uninterrupted; it can qualify only if its brief interruption passes automatic page recovery and no-progress-loss proof.

## Dependencies

- The live service must be healthy before any later release-process implementation begins; follow [live-service continuity](../../../repo-governance/development/live-service-continuity.md).
- Machine-local deployment paths, runtime root, release cookie, and secret-key-base file remain outside the repository and must never be recorded here.
- A later release choice must preserve mixed-version safety for the shared flat-file runtime root and compatible LiveView reconnect behavior.
- A later release choice must preserve acknowledged and in-progress user state across an automatic reconnect or page self-update; requiring a manual reload, re-entry, or repetition of completed work is a blocking failure.
- A release artifact must be traceable to one unchanged clean `main` revision and must not be created until every declared pre-artifact gate passes for that revision.

## Navigation

- [Business requirements](brd.md) — outcome, affected roles, and operational risks.
- [Product requirements](prd.md) — assessment acceptance criteria, including Gherkin.
- [Technical documentation](tech-docs.md) — current topology, recommendation, and alternatives.
- [Delivery](delivery.md) — present checkpoint and deferred discovery/decision work.
- [Learnings](learnings.md) — safe, temporary observations awaiting disposition.

## Directory Map

- [Business requirements](brd.md) states operational value and risks.
- [Delivery](delivery.md) owns the ordered assessment work and checkpoints.
- [Learnings](learnings.md) records dated observations and their disposition.
- [Product requirements](prd.md) defines planning acceptance criteria.
- [Technical documentation](tech-docs.md) contains the current condition, recommendation, and alternative analysis.
