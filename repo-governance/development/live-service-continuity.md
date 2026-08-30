# Live-Service Continuity

Apply this standard whenever a repository-owned application is actively reachable by a user while work continues. An explicit no-downtime requirement is blocking, not aspirational.

Bnest's routed development service is a 24/7 household service. Elixir/OTP supports that goal through supervision and process isolation, but it cannot keep the only application process available while its runtime is replaced. Treat Bnest as active even when no traffic is visible; never infer an idle or maintenance window from time of day, process activity, or development context.

## Invariants

- The active local and routed endpoints must not be left refusing connections, timing out, returning unexpected 5xx responses, or exposing an incomplete authentication/data cutover.
- A successful status code is availability evidence, not responsiveness evidence. Continuously sample the exact routed user-facing origin throughout preflight, compute gates, candidate qualification, promotion, and drain. Unless a plan selects a tighter budget, Bnest requires zero routed failures, p95 latency at or below 500 ms, and every sample at or below 2 seconds; a looser budget requires an explicit governance change rather than an implementation-time exception.
- A commit or push changes repository history only; it does not update a running backend or prove which revision it serves. Before reporting an active-service change complete, verify the routed backend serves the intended revision or observable behavior. If it does not, complete a no-downtime candidate cutover first.
- Preserve the last usable reader and writer until the replacement passes its normal read-back and critical user journey.
- Never edit dependency, configuration, runtime, or supervision inputs beneath the only active code-reloading server. Those changes can invalidate the running compiler before a planned restart.
- Keep a stable backend independent from the watched working tree. Start and verify a replacement on a separate loopback port before switching Caddy's upstream with a graceful reload.
- When two versions can reach one mutable store, their schemas and locking must be mutually compatible; otherwise only the active version may write.
- Retain the previous healthy backend until local HTTP, routed HTTPS, and applicable LiveView/WebSocket checks pass against the replacement. Configure a bounded WebSocket drain; clients may reconnect automatically but must never require a manual refresh for a compatible release.
- Preserve acknowledged multi-client state outside one LiveView or socket process. Reconnect with a stable session identity, ordered catch-up sequence, and idempotent command identity; treat presence and connection ownership as ephemeral rather than authoritative state.
- After final verification and any required drain, stop every unneeded non-production server, watcher, candidate, and temporary proxy. Keep only the active route and explicitly retained rollback capacity; unfinished cleanup means the work is incomplete.

## Blocking Gate

Before a material change, identify the active server and proxy, record safe baseline health and routed responsiveness, and decide whether the change can affect compilation, startup, routing, authentication, storage, or a current journey. For Bnest, the baseline includes at least 12 exact-origin samples and the representative routed journey; the work names the numeric p95 and maximum-latency budget before execution. If it can affect the active service and no independent healthy backend exists, establish one before editing. A single-process stop/start is not a zero-downtime deployment.

If any active check fails or the routed responsiveness budget is exceeded, stop unrelated implementation immediately. Restore or route back to the last healthy backend, verify the user journey and budget, capture a safe learning, and only then resume. Never continue a plan while the live surface remains degraded.

Use the [server restart](../workflows/development-server-restart.md) and [tailnet proxy](../workflows/development-tailnet-proxy.md) workflows for the concrete lifecycle. Plans involving cutover must make continuity and rollback explicit in delivery checkpoints.
