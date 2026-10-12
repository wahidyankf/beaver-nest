# Commit Authorization

Do not commit or push repository changes unless the action is explicitly authorized by the user or explicitly included in a user-approved plan being followed for the current task.

## Ongoing Task Delivery

A single-action grant covers that action once. Authorization to deliver a named task covers its staging, thematic
commits, synchronization, publication, and landing until that task is finished. Do not request permission again for
those routine steps; [authorized task sync](no-destructive-git-operations/001-authorized-task-branch-sync.md) owns the
rebase and lease-push safeguards. Resuming the same unfinished task retains its recorded authority after scope and
current state are verified. It covers no unrelated work, later task, hook bypass, or release.

## Requirements

- Treat commit and push as separate actions. Authorization for one does not authorize the other.
- A plan authorizes only the commit or push steps it states. An agent-created plan that the user has not approved grants no authorization.
- Match the authorized files, theme, branch, remote, and other stated scope. Ask before materially expanding it.
- Do not infer authorization from a request to edit, fix, test, finish, stage, or otherwise complete work.
- Do not carry authorization from a completed task into later work.
- Without authorization, leave changes uncommitted or unpushed, report their status, and request confirmation when the action is needed.
- Merging a pull request is not one of these actions. Its authority comes from the [pull-request merge convention](pull-request-merge.md) preconditions, which stand in for a per-merge prompt; the commits and pushes onto the branch remain separately authorized here.

Examples:

- “Commit these changes” authorizes a commit but not a push.
- “Push the existing commits to the task branch” authorizes that push but not a new commit.
- “Commit and push” authorizes both actions within the current task's scope.

This convention preserves user control over repository history and external side effects.
