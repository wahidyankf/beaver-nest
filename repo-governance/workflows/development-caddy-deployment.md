# Development Caddy Deployment

Use this workflow to promote a verified Bnest Phoenix release without requiring a browser refresh. It composes the [continuity](../development/live-service-continuity.md) and [Tailnet proxy](development-tailnet-proxy.md) workflows.

## Preconditions

- Caddy is managed by `proxy:install` and Tailscale Serve already forwards HTTPS to loopback port `4100`. During first migration, Caddy initially proxies the legacy blue server without an active health check; the first promoted release enables it.
- `BNEST_DEPLOY_ROOT`, `BNEST_RUNTIME_ROOT`, `BNEST_DEPLOY_COOKIE_FILE`, `BNEST_DEPLOY_SECRET_KEY_BASE_FILE`, and bare-HTTPS `BNEST_PRODUCTION_ORIGIN` name machine-local state outside the repository. Do not store their values, hostnames, cookies, or key-base material in Git. Candidate preparation derives `PHX_HOST` from the validated origin so WebSocket checks stay strict. Keep the deployed key base compatible with the active service so browser sessions survive the cutover.
- An unset shell does not mean these values are unavailable: on an already-provisioned host, a persistent deploy root, cookie file, and key-base file exist outside the repository even between sessions. Before reporting a release blocked on missing deploy configuration, discover the running deployment (for example, the active blue/green launchd or systemd unit definitions) and derive the deploy root and file paths from it; `BNEST_DEPLOY_WORKTREE` needs no manual value because `release:run` creates and removes its own temporary worktree.
- The current active route must be healthy before release work starts. Check `proxy:status` and the routed `/health/ready` endpoint; recover a failed active service before building or promoting anything.
- Build from an isolated, temporary Git worktree. The active backend remains independent from that worktree, and `main` is the only persistent branch.
- Routine releases fail closed under the release and shared resource locks when either is owned, the inactive slot is occupied, exported memory pressure is not normal, the compressor reports unavailable, or the 9 GiB available non-compressed estimate, four-unit release plus two-unit safety, and 13 GiB disk envelope is unavailable. CPU admission uses interval CPU-time deltas; compressor payload is evidence rather than fullness. Production uses ports `4000`/`4001`, Caddy uses `4100`, E2E leases `4010`–`4019`, and development leases `4020`–`4029`.
- A release manifest declares its migration set and checksum. A non-empty set is blocked until an approved, lock-protected expand–migrate–verify adapter preserves the previous reader; slot startup must never run migrations implicitly.

## Release sequence

1. Release an identified clean `main` revision only; a commit or push is not a deployment. Run required gates and commit/push only when authorized. Use the managed `release:run` target for routine releases so gate order, locking, capacity, migration proof, promotion, routed proof, drain, retention, and cleanup remain one transaction.
2. Build the immutable artifact with `release:build` from a detached temporary worktree outside the normal checkout, recording its revision. Delete that worktree immediately after build; never retain one or a branch for later use.
3. Select the inactive `blue` or `green` slot and run `deploy:prepare` with the revision. First migration uses `green`. Direct candidate health must include the requested `X-Bnest-Revision`, preventing a stale slot promotion.
4. Before cutover, run applicable Nx gates and isolated E2E. For UI or LiveView changes, validate a connected LiveView at the exact served origin. For Codex runtime changes, confirm the candidate locates its executable and uses a permanent checkout.
5. Promote with `deploy:promote -- --slot <slot>`. The target validates the candidate and gracefully reloads Caddy. Old WebSockets can drain for five minutes; compatible LiveViews reconnect without a manual refresh.
6. Verify routed local Caddy HTTP and Tailnet HTTPS, their reported revision, and a connected synthetic LiveView. Completion requires the routed backend—not only the candidate port—to serve the intended revision.
7. After drain, retire the previous slot and every unneeded non-production candidate. Confirm no inactive slot listens and no temporary worktree remains.

## Canonical commands

Use package-manager-prefixed Nx targets. Deployment environment values remain machine-local; never print or commit them.

```sh
npm exec -- nx run -p bnest-app -t proxy:status
npm exec -- nx run -p bnest-app -t release:test
npm exec -- nx run -p bnest-app -t release:run -- --revision <sha>
npm exec -- nx run -p bnest-app -t release:build
npm exec -- nx run -p bnest-app -t deploy:prepare -- --slot <inactive-slot> --revision <sha>
npm exec -- nx run -p bnest-app -t deploy:promote -- --slot <inactive-slot>
npm exec -- nx run -p bnest-app -t proxy:status
```

## Recovery

Never stop Caddy to change its configuration. If candidate health, routing, or LiveView verification fails, keep the previous backend running and run `deploy:rollback` before diagnosis. Do not retry a failed candidate until its health failure is understood. Start releases through the managed target so descriptor limits and permanent runtime configuration apply.
