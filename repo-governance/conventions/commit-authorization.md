# Commit Authorization

Do not commit or push repository changes unless the action is explicitly authorized by the user or explicitly included in a user-approved plan being followed for the current task.

## Requirements

- Treat commit and push as separate actions. Authorization for one does not authorize the other.
- A plan authorizes only the commit or push steps it states. An agent-created plan that the user has not approved grants no authorization.
- Match the authorized files, theme, branch, remote, and other stated scope. Ask before materially expanding it.
- Do not infer authorization from a request to edit, fix, test, finish, stage, or otherwise complete work.
- Do not carry authorization from a completed task into later work.
- Without authorization, leave changes uncommitted or unpushed, report their status, and request confirmation when the action is needed.

Examples:

- “Commit these changes” authorizes a commit but not a push.
- “Push the existing commits to `origin/main`” authorizes that push but not a new commit.
- “Commit and push” authorizes both actions within the current task's scope.

This convention preserves user control over repository history and external side effects.
