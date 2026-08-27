# Business Requirements

## Goal

Give the Bnest maintainer a release process that is understandable and practical for daily or multiple-daily releases on one machine, protects 5–10 users across 1–3 families/groups from avoidable interruption, and coexists with 5–10 development workloads without holding unnecessary application capacity.

## Roles and Outcomes

| Role         | Needed outcome                                                                                                                                                      |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Family user  | Existing HTTP and LiveView sessions remain usable or recover automatically on the current page without a manual reload or loss of acknowledged or in-progress work. |
| Child player | A future multiplayer session reconnects to the same authoritative game, turn, participants, and event sequence without duplicate or missing actions.                |
| Maintainer   | Can prepare, promote, verify, roll back, and clean up a release through documented Nx targets without manually rewiring private HTTPS.                              |
| Host machine | Keeps one serving application in steady state; admits bounded release work only when capacity remains for the active service and concurrent development.            |
| AI operator  | Can follow one bounded state machine whose exit codes and structured summaries determine the next action without repeatedly rereading logs or inventing commands.   |

## Non-goals

This assessment does not promise literal zero interruption for every incompatible schema, protocol, or session change. Such changes require an explicit compatibility or maintenance strategy. It recommends an operating direction but does not authorize implementation.

## Availability Limitation

A release may cause a brief transport interruption only when the browser resolves it automatically. The page must reconnect or update itself, return to a usable state, and preserve the user's current route, acknowledged data, and recoverable in-progress work. Asking the user to reload, re-enter input, repeat completed learning work, or reconstruct a chat is not an acceptable release outcome.

For future multiplayer behavior, preserving state means reconstructing authoritative game state outside the replaced socket process. Reconnect must resume a versioned session, catch up ordered events, and apply near-cutover commands at most once. Merely keeping a WebSocket open or remounting a blank LiveView does not satisfy the outcome.

## Determinism Limitation

Routine releases must use an explicit revision and an ordered, fail-closed pipeline. Pre-artifact tests run before build; declared data migrations run once under a lock after artifact manifest verification; candidate-only checks run against the immutable artifact; routed checks run after activation. Each stage accepts declared inputs, is safe to retry for the same revision or refuses with a clear state, emits a concise machine-readable result, and never infers success from prose logs. A failure stops before the next mutation and selects a documented recovery edge.

## Risks

- A single Phoenix process cannot be replaced with no connection risk; a verified overlapping reader is currently the safety mechanism.
- Two concurrent versions share a mutable flat-file runtime root, so incompatible readers, writers, or locks would make promotion unsafe.
- Removing Caddy without an equivalent stable-listener, drain, and rollback capability could turn a simple app replacement into user-visible HTTPS and WebSocket disruption.
- Keeping both slots or old artifacts indefinitely would defeat the resource objective.
- Multiple daily releases can overlap drains, builds, or cleanup; parallel transactions or unbounded queues would multiply resources and rollback ambiguity.
- Five to ten concurrent development workloads can consume release headroom unpredictably; automation must defer rather than kill, pause, or reconfigure them.
- Some page-local state may not yet have a durable recovery contract; selecting a release model before inventorying that state could satisfy endpoint health while still losing user progress.
- Future multiplayer state stored only in LiveView assigns, one VM, or one container would be lost or split across revisions during reconnect.
- Development currently defaults to production blue port `4000`; a same-host development process must use the proposed dedicated port and fail closed on collisions.
- Future destructive database/schema changes can invalidate the rollback artifact; expand–migrate–verify–contract and a single migration owner are mandatory.
- Cached or reused evidence can be stale when inputs are incomplete; release gates may use Nx caching only after every relevant source, dependency, environment, and output is declared.
- A syntactically valid Mermaid diagram can still hide release transitions when a rendered label is clipped; plan execution must first make label limits deterministic and pre-push enforced.

## Current Decision State

The recommendation remains one deterministic release transaction over the existing ephemeral blue/green Caddy design after considering multiple daily releases, 5–10 users, 1–3 groups, and 5–10 simultaneous development workloads. Keep only one Phoenix process in steady state; create the second only for candidate verification and bounded drain; serialize/coalesce releases; and retain one prior artifact without keeping its process warm. This is a recommendation from current evidence, not a requirement to preserve existing mechanics. Replace any layer when measured evidence proves an alternative is simpler, cheaper, and equally safe for state continuity, migration, rollback, and shared-host capacity.

A named Tailscale Service with ephemeral slots is the first no-Caddy investigation; direct device Serve to one restarted Phoenix slot is the lowest-resource fallback. Both require measured benefit and complete automatic recovery proof. Permanent warm slots, custom OTP hot upgrades, and a container orchestrator are not recommended because they add steady-state resources or operational/test complexity without a demonstrated need.
