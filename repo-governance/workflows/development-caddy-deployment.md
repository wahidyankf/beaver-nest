# Development Caddy Deployment

Use this workflow to promote a verified Bnest Phoenix release without requiring a browser refresh. It composes the [continuity](../development/live-service-continuity.md) and [Tailnet proxy](development-tailnet-proxy.md) workflows.

## Preconditions

- Caddy is managed by `proxy:install` and Tailscale Serve already forwards HTTPS to loopback port `4100`. During first migration, Caddy initially proxies the legacy blue server without an active health check; the first promoted release enables it.
- `BNEST_DEPLOY_ROOT`, `BNEST_RUNTIME_ROOT`, `BNEST_DEPLOY_COOKIE_FILE`, and `BNEST_DEPLOY_SECRET_KEY_BASE_FILE` name machine-local state outside the repository. Do not store their values, hostnames, cookies, or key-base material in Git. Keep the deployed key base compatible with the active service so browser sessions survive the cutover.
- The current active route must be healthy before release work starts. Check `proxy:status` and the routed `/health/ready` endpoint; recover a failed active service before building or promoting anything.
- Build from an isolated, temporary Git worktree. The active backend remains independent from that worktree, and `main` is the only persistent branch.

## Release sequence

1. Release an identified clean `main` revision only; a commit or push is not a deployment. Run required gates and commit/push only when authorized.
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
npm exec -- nx run -p bnest-app -t release:build
npm exec -- nx run -p bnest-app -t deploy:prepare -- --slot <inactive-slot> --revision <sha>
npm exec -- nx run -p bnest-app -t deploy:promote -- --slot <inactive-slot>
npm exec -- nx run -p bnest-app -t proxy:status
```

## Recovery

Never stop Caddy to change its configuration. If candidate health, routing, or LiveView verification fails, keep the previous backend running and run `deploy:rollback` before diagnosis. Do not retry a failed candidate until its health failure is understood. Start releases through the managed target so descriptor limits and permanent runtime configuration apply.
