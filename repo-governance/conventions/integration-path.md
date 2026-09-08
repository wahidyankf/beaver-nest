# Integration Path

This repository practises trunk-based development. `main` is the trunk, every branch off it is short-lived, and history stays linear. It takes the scaled variant, in which work reaches the trunk through a pull request rather than a direct commit, so the shorthand "commit to trunk" never applies here.

Integrate every change through a pull request from a task branch into `main`. Local `main` has no executable path to `origin/main`: the repository's `main` ruleset refuses direct pushes, force pushes, and branch deletion for every actor, including the repository owner.

## Requirements

- Do the work on a branch dedicated to it, in a Git worktree created under `worktrees/<name>/` at the repository root. That directory is ignored apart from its placeholder, so a worktree never enters history.
- Initialize a new worktree from its own root, before any Git mutation or Nx target runs in it, with `./hippo run --class ephemeral --disk-path . -- npm install`. That installs the checkout's dependencies and activates its Husky hooks; a worktree whose hooks were never activated pushes unverified work.
- Push the task branch to `origin` and open a pull request against `main`.
- Merge only after the `Quality gate` check reports success. The ruleset requires no approving review, because the sole maintainer cannot approve their own pull request and requiring one would block every merge.
- Keep history linear, which the ruleset enforces. Rebase a stale branch onto `main`; never merge `main` into it.
- `main` is the only persistent branch. Delete the task branch and remove its worktree immediately after the pull request merges or the work is abandoned.
- A no-downtime deployment is the single exception to the location rule: `release:run` creates and removes its own detached worktree outside the normal checkout to build a release. It is temporary infrastructure, not an integration path, and never becomes one. Invoke it from the primary checkout on local `main`, never from a `worktrees/` checkout. The run asserts branch `main`, a clean tree, and `HEAD` equal to `origin/main` in whichever checkout it runs from, so a task branch is refused even when it already points at the released revision.

Server-side enforcement is why the local hooks are not the last word. A pull request can be opened from any checkout, including one whose hooks never ran, so [`pr-quality-gate.yml`](../../.github/workflows/pr-quality-gate.yml) mirrors the `pre-commit`, `commit-msg`, and `pre-push` contracts as merge-blocking checks. Repairing a failure there follows the [push-hook verification convention](push-hook-verification.md): fix the cause, never bypass the gate.

This convention chooses an integration path; it does not authorize a commit or push. Obtain the authorization required by the [commit-authorization convention](commit-authorization.md) and the user's request.
