# Development Server Restart

Use this workflow when a running development server must be restarted after a configuration, dependency, runtime, or supervision-tree change.

## Procedure

1. List tmux panes and identify the existing server pane from its working directory, current process, and captured output. Do not start a replacement server in another pane.
2. Stop the server in that pane and wait until its shell prompt returns. If Erlang opens its BREAK menu, send `a` separately to abort, then wait for the prompt before sending another command.
3. Restart the applicable Nx `serve` target in the same pane, prefixed with the workspace package manager.
4. Verify startup from the pane output and make a read-only request to the expected local endpoint.

If no existing server pane can be identified, do not guess a target. Report that no reusable pane was found before deciding whether a new server process is in scope.
