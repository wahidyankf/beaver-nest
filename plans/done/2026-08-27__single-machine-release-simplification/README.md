# Single-Machine Release Simplification

**Status:** Completed: 2026-08-27
**Created:** 2026-08-27  
**Started:** 2026-08-27  
**Scope:** Bnest's machine-local release workflow and its operational evidence

## Context

Bnest is a private, 24/7 service for about 5–10 family users across 1–3 families/groups, hosted on a machine that also runs 5–10 development workloads. The requested outcome is a release process simple enough to operate on that machine while keeping user disruption absent or automatically recoverable and avoiding unnecessary steady-state resource use. Users must not need to reload a page after a release or lose progress: if a brief connection interruption occurs, the open page must reconnect itself and restore the same usable domain state. This contract must also support future children's multiplayer sessions through resumable, ordered, idempotent state recovery rather than relying on one LiveView process. Releases are expected daily and may occur multiple times per day, so the routine path must be deterministic and AI-token-efficient. The plan records the baseline, alternatives, ports, absolute resources, test impact, migration strategy, recommendation, implemented transaction, and required live proof.

The current repository model is already single-machine blue/green deployment: Tailscale Serve forwards private HTTPS to loopback Caddy on port 4100, and Caddy routes to one Phoenix release slot on port 4000 or 4001. An inactive slot is started, checked directly for readiness and its requested revision, then Caddy is gracefully reloaded to it. The previous slot remains available through the five-minute WebSocket drain and is retired only after routed proof. See the [technical decision guide](tech-docs/README.md).

Repository source, governance, and the authorized machine-local lower pane confirm this design. The safe baseline returned Caddy and routed readiness at `200`; steady state was one green Phoenix listener on `4001` plus Caddy on `4100`, with blue `4000` free after drain. No machine-local path or production origin is recorded.

## Recommendation

The current recommendation is Tailscale Serve → Caddy → ephemeral blue/green Phoenix with one deterministic Nx release transaction. Run fixed gates against one clean `main` revision before building; apply only compatible lock-owned data expansion/migration; verify the inactive revision and user journeys; promote; prove routed automatic state recovery; then retire and clean after the bounded drain. The mechanism may be replaced if another alternative proves equal continuity/rollback, simpler deterministic operation, and lower measured resource cost.

The intended steady state is Tailscale Serve, Caddy, and one Phoenix release. A second Phoenix VM exists only from candidate preparation through routed proof and drain. Retain the active and one previous verified artifact for cold recovery, not two permanently warm application processes. The managed transaction owns warm rollback, post-drain retention, and deterministic re-prepare through revision-checked deployment primitives. A post-release `/chat` failure showed that anonymous recovery proof had omitted persisted in-progress chat restoration; the repaired release passed with that isolated authenticated case in the fixed gate. The recommendation is unchanged. See the [technical recommendation](tech-docs/README.md#recommendation-and-ranking), [port and resource comparison](tech-docs/alternatives.md#port-contract), and [migration design](tech-docs/migration-design.md).

## Scope

- Establish the current release topology, lifecycle, safeguards, and resource shape from repository evidence.
- Compare plausible one-machine operating models against continuity, simplicity, rollback, and resource constraints.
- Give every alternative its own port-labelled diagram, expected process/memory/disk formula, option-specific tests, WebSocket effect, and data/schema migration behavior.
- Treat Caddy as replaceable or removable when a chosen model preserves the availability properties users need with less total operating cost.
- Define a deterministic release state machine with ordered pre-artifact, candidate, routed, rollback, and cleanup gates.
- Define a deterministic Badakmini label-legibility prerequisite so clipped Mermaid text cannot obscure release decisions before push.
- Validate or revise the recommendation with safe runtime measurements and one managed live release.

## Non-goals

- Replace Tailscale Serve, Caddy, the data root, or credentials; execution changes only the active release slot through the existing stable route.
- Introduce cloud hosting, Kubernetes, public exposure, a database, containers, or new deployment infrastructure without a later decision.
- Design a concrete multiplayer game or database schema; this plan defines only the release continuity contract they must satisfy.
- Describe a single-process stop/start as uninterrupted; it can qualify only if its brief interruption passes automatic page recovery and no-progress-loss proof.

## Dependencies

- The live service must be healthy before any later release-process implementation begins; follow [live-service continuity](../../../repo-governance/development/live-service-continuity.md).
- Machine-local deployment paths, runtime root, release cookie, and secret-key-base file remain outside the repository and must never be recorded here.
- A later release choice must preserve mixed-version safety for the shared flat-file runtime root and compatible LiveView reconnect behavior.
- A later release choice must preserve acknowledged and in-progress user state across an automatic reconnect or page self-update; requiring a manual reload, re-entry, or repetition of completed work is a blocking failure.
- Future multiplayer state must be authoritative outside one socket process and resume by versioned session identity, ordered events, and idempotent commands without a reload.
- Development, production, rolling candidate, and test listeners must follow the [port contract](tech-docs/alternatives.md#port-contract) and refuse collisions.
- Current flat-file and future database changes must follow [expand–migrate–verify–contract](tech-docs/migration-design.md), keep the rollback artifact compatible, and run once under an explicit lock.
- A release artifact must be traceable to one unchanged clean `main` revision and must not be created until every declared pre-artifact gate passes for that revision.

## Navigation

- [Business requirements](brd.md) — outcome, affected roles, and operational risks.
- [Product requirements](prd.md) — assessment acceptance criteria, including Gherkin.
- [Technical decision guide](tech-docs/README.md) — current topology, verified sources, WebSocket continuity, and recommendation.
- [Release alternatives](tech-docs/alternatives.md) — per-option diagrams, ports, absolute resources, tests, cadence, and verdicts.
- [Release contract](tech-docs/release-contract.md) — deterministic gates, transitions, evidence, specification changes, and file impact.
- [Migration design](tech-docs/migration-design.md) — current flat-file and future database/schema lifecycle.
- [Delivery](delivery.md) — completed execution evidence and the final archival checkpoint.
- [Learnings](learnings.md) — safe observations and their disposition.

## Directory Map

- [Business requirements](brd.md) states operational value and risks.
- [Delivery](delivery.md) owns the ordered assessment work and checkpoints.
- [Learnings](learnings.md) records dated observations and their disposition.
- [Product requirements](prd.md) defines planning acceptance criteria.
- [Technical documents](tech-docs/README.md) owns the current condition, recommendation, alternatives, release contract, and migration design through its own directory map.
