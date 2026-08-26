# Development Tailnet Proxy

Use this workflow to expose the stable loopback Caddy proxy privately through a persistent Tailscale Serve HTTPS proxy.

## Boundaries

- Manage the Tailnet proxy independently from Caddy and Phoenix so either application backend can restart without changing the public HTTPS route.
- Keep the backend bound to loopback. Use Tailscale Serve, never Funnel, for private development access.
- Never commit a machine hostname, tailnet name, private address, certificate, or other machine-local state.
- Operate the repository-owned proxy through its package-manager-prefixed Nx targets. Tailscale forwards only to Caddy on loopback port `4100`; Caddy preserves the forwarded Host and supplies `X-Forwarded-Proto: https` to the Phoenix upstream, while deployment targets change that upstream independently.
- Treat the configured backend port as non-secret deployment state; never put the tailnet hostname in repository files or evidence.

## Procedure

1. Install and verify Caddy through `npm exec -- nx run -p bnest-app -t proxy:install`; it listens on loopback port `4100` and owns the active Phoenix upstream.
2. Run `BNEST_TAILNET_BACKEND_PORT=4100 npm run tailnet:up` once to create or refresh the background HTTPS root proxy.
3. Run `npm run tailnet:status` and confirm it forwards HTTPS to loopback port `4100`.
4. Start, prepare, promote, or retire Phoenix independently through the Nx deployment targets. A backend change must not stop or reconfigure the Tailnet proxy.
5. Run `npm run tailnet:down` only when tailnet access should be removed. The target must remove the repository-owned root mount without resetting unrelated Tailscale Serve configuration.

The first `tailnet:up` may require interactive tailnet approval to enable HTTPS certificates. Complete that approval before retrying the target.

## Verification

- Request the local HTTP endpoint and the tailnet HTTPS endpoint.
- Exercise a LiveView interaction through HTTPS so the WebSocket path is covered.
- For a no-downtime change, start and verify the alternate local backend first, gracefully reload Caddy to that upstream, then verify HTTPS and a LiveView interaction before retiring the previous backend.
- During an interruption-tolerant app restart, confirm the proxy configuration remains present and the HTTPS endpoint recovers after the local server returns.

If HTTPS returns a proxy error, inspect `npm run tailnet:status` and the app-server pane separately. Repair only the failed lifecycle.
