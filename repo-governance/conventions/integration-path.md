# Integration Path

Use direct pushes from local `main` to `origin/main` as this repository's only integration path. Do not create pull requests or task branches for repository integration.

## Requirements

- Perform integration work on local `main` and push it directly to `origin/main`.
- Do not open a pull request, create an integration branch, or create a task worktree as an alternative path.
- `main` is the only persistent branch. Integrate or explicitly abandon every temporary non-`main` branch, then delete it immediately; do not retain task, feature, deployment, or integration branches.
- A no-downtime deployment may use an isolated Git worktree only to build its release. It is temporary infrastructure, not an integration path: remove the exact worktree immediately after the release no longer needs its source. Do not retain deployment, task, or feature worktrees after their work completes.
- If an external system later requires pull requests, stop and ask the user to change this repository rule explicitly before taking action.

This convention chooses an integration path; it does not authorize a commit or push. Obtain the authorization required by the [commit-authorization convention](commit-authorization.md) and the user's request.
