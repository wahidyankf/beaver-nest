# Development Tailnet Proxy

Use this workflow to expose a loopback development server privately through a persistent Tailscale Serve HTTPS proxy.

## Boundaries

- Manage the proxy independently from the app server so either can restart without changing the other.
- Keep the backend bound to loopback. Use Tailscale Serve, never Funnel, for private development access.
- Never commit a machine hostname, tailnet name, private address, certificate, or other machine-local state.
- Operate the repository-owned proxy through its package-manager-prefixed Nx targets.

## Procedure

1. Run `npm run tailnet:up` once to create or refresh the background HTTPS root proxy.
2. Run `npm run tailnet:status` and confirm it forwards HTTPS to the expected loopback port.
3. Start or restart the app independently through its Nx `serve` target. A restart must not stop or reconfigure the proxy.
4. Run `npm run tailnet:down` only when tailnet access should be removed. The target must remove the repository-owned root mount without resetting unrelated Tailscale Serve configuration.

The first `tailnet:up` may require interactive tailnet approval to enable HTTPS certificates. Complete that approval before retrying the target.

## Verification

- Request the local HTTP endpoint and the tailnet HTTPS endpoint.
- Exercise a LiveView interaction through HTTPS so the WebSocket path is covered.
- During an app restart, confirm the proxy configuration remains present and the HTTPS endpoint recovers after the local server returns.

If HTTPS returns a proxy error, inspect `npm run tailnet:status` and the app-server pane separately. Repair only the failed lifecycle.
