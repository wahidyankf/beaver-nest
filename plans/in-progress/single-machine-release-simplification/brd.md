# Business Requirements

## Goal

Give the Bnest maintainer a release process that is understandable and practical on one machine, protects family users from avoidable interruption, and does not hold unnecessary application capacity when no release is happening.

## Roles and Outcomes

| Role         | Needed outcome                                                                                                                                                      |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Family user  | Existing HTTP and LiveView sessions remain usable or recover automatically on the current page without a manual reload or loss of acknowledged or in-progress work. |
| Maintainer   | Can prepare, promote, verify, roll back, and clean up a release through documented Nx targets without manually rewiring private HTTPS.                              |
| Host machine | Keeps one serving application in steady state; permits temporary overlap only when it is needed to prove and switch a replacement safely.                           |
| AI operator  | Can follow one bounded state machine whose exit codes and structured summaries determine the next action without repeatedly rereading logs or inventing commands.   |

## Non-goals

This assessment does not promise literal zero interruption for every incompatible schema, protocol, or session change. Such changes require an explicit compatibility or maintenance strategy. It recommends an operating direction but does not authorize implementation.

## Availability Limitation

A release may cause a brief transport interruption only when the browser resolves it automatically. The page must reconnect or update itself, return to a usable state, and preserve the user's current route, acknowledged data, and recoverable in-progress work. Asking the user to reload, re-enter input, repeat completed learning work, or reconstruct a chat is not an acceptable release outcome.

## Determinism Limitation

Routine releases must use an explicit revision and an ordered, fail-closed pipeline. Pre-artifact tests run before build; candidate-only checks run against the immutable artifact; routed checks run after promotion. Each stage accepts declared inputs, is safe to retry for the same revision or refuses with a clear state, emits a concise machine-readable result, and never infers success from prose logs. A failure stops before the next mutation and selects a documented recovery edge.

## Risks

- A single Phoenix process cannot be replaced with no connection risk; a verified overlapping reader is currently the safety mechanism.
- Two concurrent versions share a mutable flat-file runtime root, so incompatible readers, writers, or locks would make promotion unsafe.
- Removing Caddy without an equivalent stable-listener, drain, and rollback capability could turn a simple app replacement into user-visible HTTPS and WebSocket disruption.
- Keeping both slots or old artifacts indefinitely would defeat the resource objective.
- Some page-local state may not yet have a durable recovery contract; selecting a release model before inventorying that state could satisfy endpoint health while still losing user progress.
- Cached or reused evidence can be stale when inputs are incomplete; release gates may use Nx caching only after every relevant source, dependency, environment, and output is declared.
- A syntactically valid Mermaid diagram can still hide release transitions when a rendered label is clipped; plan execution must first make label limits deterministic and pre-push enforced.

## Current Decision State

The recommended direction is one deterministic release transaction over the existing ephemeral blue/green Caddy design. Keep only one Phoenix process in steady state; create the second only for candidate verification and bounded drain; retain one prior artifact without keeping its process warm. Validate the recommendation against actual host resource measurements and automatic page-recovery proof before implementation approval.

Direct Tailscale Serve to one Phoenix slot is the fallback recommendation only if Caddy has a measured material cost and a bounded restart proves every page recovers without progress loss. Permanent warm slots, custom OTP hot upgrades, and a container orchestrator are not recommended because they add steady-state resources or operational/test complexity without a demonstrated need.
