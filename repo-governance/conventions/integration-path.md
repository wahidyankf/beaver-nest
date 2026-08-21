# Integration Path

Use direct pushes from local `main` to `origin/main` as this repository's primary integration path. Use a pull request when the user explicitly selects one or an applicable external requirement makes one necessary.

## Requirements

- Perform direct-integration work on local `main` and push it to `origin/main`.
- Perform every pull-request task on a dedicated non-`main` branch in a dedicated Git worktree under the repository root's `worktrees/` directory.
- Follow the [pull-request worktree workflow](../workflows/pull-request-worktree.md) from worktree creation through cleanup.
- Remove the task's worktree after the requested pull-request work is complete and its changes are safely retained. Do not leave completed worktrees to accumulate.
- Never force-remove a worktree merely to satisfy cleanup when doing so could discard work.

This convention chooses an integration path; it does not authorize a commit, push, pull request, or destructive cleanup. Obtain the authorization required by the [commit-authorization convention](commit-authorization.md) and the user's request.
