# Development Caddy Deployment

Use this workflow to promote a verified Bnest Phoenix release without requiring a browser refresh. It composes the [continuity](../development/live-service-continuity.md) and [Tailnet proxy](development-tailnet-proxy.md) workflows.

## Preconditions

- Caddy is managed by `proxy:install` and Tailscale Serve already forwards HTTPS to loopback port `4100`. During first migration, Caddy initially proxies the legacy blue server without an active health check; the first promoted release enables it.
- `BNEST_DEPLOY_ROOT`, `BNEST_RUNTIME_ROOT`, `BNEST_DEPLOY_COOKIE_FILE`, and `BNEST_DEPLOY_SECRET_KEY_BASE_FILE` name machine-local state outside the repository. Do not store their values, hostnames, cookies, or key-base material in Git. Keep the deployed key base compatible with the active service so browser sessions survive the cutover.
- Build from an isolated Git worktree. The active backend remains independent from that worktree.

## Procedure

1. Build the immutable release with `release:build`, then prepare the inactive `blue` or `green` slot with `deploy:prepare`. On the first migration, prepare `green`; it has no distributed release peer yet.
2. Check direct candidate readiness and run applicable Nx gates and isolated E2E coverage. `deploy:prepare` requires the candidate health response to carry the requested `X-Bnest-Revision`, so it cannot promote a stale process on the slot port.
3. Promote with `deploy:promote -- --slot <slot>`. The target validates and gracefully reloads Caddy; its old WebSocket upstream drains for at most five minutes.
4. Verify local Caddy HTTP, Tailnet HTTPS, the release revision, and a connected LiveView. A compatible client reconnects automatically; an incompatible client reloads itself once.
5. On any failure, run `deploy:rollback`; only then diagnose. After the drain window and verification, retire the previous slot and stop every other unneeded non-production candidate.

## Recovery

Never stop Caddy to change its configuration. If promotion or verification fails, keep the previous backend running and reload Caddy to its recorded previous slot. A failed candidate is not eligible for retry until its health failure is understood.
