# Pull-Request Worktree

Use this workflow whenever the [integration path](../conventions/integration-path.md) for a task is a pull request.

## Inputs

- the pull-request task and completion condition;
- a dedicated non-`main` branch name;
- a unique worktree name; and
- the base branch, normally `origin/main`.

## Create

1. Confirm that a pull request was explicitly selected or is required, and that the intended external actions are authorized.
2. From the primary repository checkout, fetch the base branch and inspect `git worktree list` to avoid reusing an active path or branch.
3. Create the worktree beneath the root `worktrees/` directory:

   ```sh
   git fetch origin main
   git worktree add -b <branch-name> worktrees/<worktree-name> origin/main
   ```

   When the branch already exists safely, attach it without `-b` instead of creating a duplicate branch.

## Work and Deliver

1. Perform the entire pull-request task inside `worktrees/<worktree-name>`.
2. Follow all applicable development, verification, thematic-commit, and authorization rules.
3. Push the dedicated branch and create or update the pull request only when authorized.
4. Treat the requested pull-request task as complete when its requested deliverables exist and all local changes are committed and safely pushed. Waiting for merge is part of the task only when explicitly requested.

## Clean Up

1. Confirm the worktree has no uncommitted changes and no required commits that exist only locally.
2. Return to the primary checkout and remove the worktree without forcing removal:

   ```sh
   git worktree remove worktrees/<worktree-name>
   git worktree prune
   ```

3. Verify with `git worktree list` that the completed worktree is gone.

If work remains or cleanup could lose data, keep the worktree temporarily, report the exact retained state, and resume or resolve it before declaring the task complete. Do not create a replacement worktree for the same task merely because an existing one needs inspection.
