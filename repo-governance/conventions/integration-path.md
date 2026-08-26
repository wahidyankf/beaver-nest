# Integration Path

Use direct pushes from local `main` to `origin/main` as this repository's only integration path. Do not create pull requests or task branches for repository integration.

## Requirements

- Perform integration work on local `main` and push it directly to `origin/main`.
- Do not open a pull request, create an integration branch, or create a task worktree as an alternative path.
- If an external system later requires pull requests, stop and ask the user to change this repository rule explicitly before taking action.

This convention chooses an integration path; it does not authorize a commit or push. Obtain the authorization required by the [commit-authorization convention](commit-authorization.md) and the user's request.
