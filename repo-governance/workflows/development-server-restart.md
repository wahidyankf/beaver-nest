# Development Server Restart

Use this workflow when a running development server must be restarted after a configuration, dependency, runtime, or supervision-tree change. Apply the [live-service continuity standard](../development/live-service-continuity.md) first when users can reach the service.

Do not stop or reconfigure an independently managed tailnet proxy during the restart; follow the [development tailnet proxy workflow](development-tailnet-proxy.md) for that lifecycle.

## Procedure

1. Check the expected local endpoint before editing restart-triggering files. If it is routed to users, verify the routed endpoint and establish a separate healthy backend before touching the only watched server.
2. List tmux panes and identify the existing server pane from its working directory, current process, and captured output. Do not guess or silently create a competing server on the same port.
3. Stop the server in that pane and wait until its shell prompt returns. If Erlang opens its BREAK menu, send `a` separately to abort, then wait for the prompt before sending another command.
4. When stable/candidate mode changes compile-time endpoint settings, compile with the exact environment that will start the server before invoking its Nx `serve` target. Any Nx target that starts Mix in that same development build while the stable backend serves must declare that same environment. A compile-environment mismatch disqualifies the candidate; leave routing on the healthy backend, rebuild, and reverify instead of bypassing validation.
5. Restart the applicable Nx `serve` target in the same pane, prefixed with the workspace package manager.
6. Verify startup from the pane output and make read-only requests to the expected local endpoint and one critical route. For a candidate release, promote only after both pass through Caddy, then verify routed HTTP and LiveView/WebSocket behavior. Do not restart Caddy or Tailscale during application promotion.

Do not leave a running code reloader to discover changed dependency or configuration inputs from a user request; restart or replace it immediately as part of the same change batch.

If no existing server pane can be identified, do not guess a target. Report that no reusable pane was found before deciding whether a new server process is in scope. On any failed startup or health check, keep or restore routing to the previous healthy backend before other work resumes.
