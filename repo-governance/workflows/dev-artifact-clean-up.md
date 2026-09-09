# Dev Artifact Clean-Up

## Goal and When to Use It

Remove exactly the development artifacts one piece of work created, and bring the primary checkout's `main` back level with `origin/main`. The [integration path](../conventions/integration-path.md) states these as obligations; this workflow states the order and the checks that make deleting safe.

Run it once every delivery unit that used the worktree has landed, or once the work is deliberately abandoned. Not between units, because the worktree is reused. Never as a periodic sweep.

## Scope

Five things, and nothing else: the worktree this work provisioned, its local branch, that branch on `origin`, the regenerable build output this work produced, and the primary checkout's `main` ref.

Build output means `dist/`, `.next/`, and the build caches a documented command rebuilds — in the worktree, and the same regenerable output in the primary checkout. It never means a `.env*` file or any other local secret: those are not build output, exist nowhere else, and are out of scope in every location.

Everything else on the machine belongs to someone else — a worktree this work did not create, a branch it did not open, another repository's state. That holds even when they look abandoned.

## Prerequisites

1. Nothing is unpushed: `git status --porcelain` is empty and `git log <branch> --not --remotes` prints nothing.
2. Nothing is running in the worktree.
3. The worktree is one this work provisioned, confirmed against `git worktree list`.
4. The pull request reports merged, or the abandonment is deliberate.

A worktree whose run ended `partial` or failed is retained, and said so, rather than deleted.

## Steps

Run from the primary checkout, never from inside the directory being removed: a shell holding a deleted working directory resolves the next relative path somewhere unintended.

```sh
git fetch origin --prune
git merge --ff-only origin/main
git rev-list --left-right --count HEAD...origin/main
git worktree remove worktrees/<name>
git branch -d worktree/<name>
git push origin --delete worktree/<name>
```

Purge the build output this work produced once delivery has landed and nothing is using it. Retain
logs, traces, and any other non-regenerable evidence a failure would need.

`--prune` drops the remote-tracking ref for a branch the forge deleted on merge; without it the branch keeps appearing in `git branch -a` after it is gone. Delete on `origin` only if merging did not.

Where a clone has no primary checkout, `git fetch origin main:main` reconciles without one — never against a branch checked out somewhere.

## When `-d` Refuses

`git branch -d` refuses a branch whose commits `main` does not literally contain, so after a rebase or squash merge it always refuses: the landed commits carry different hashes than the ones on the branch.

Read the refusal before answering it. Where the pull request reports merged and the change is on `origin/main`, `-D` is correct, because `-d` is asking about hashes rather than about content. Where that is not established, `-D` discards work.

## Verification

`git worktree list` no longer names the path, `git branch --list` no longer prints the branch, the branch is gone from `origin`, the purged build output is gone, and `git rev-list --left-right --count HEAD...origin/main` reads `0 0`.

## Recovery

A deleted branch whose commits are unreachable is recoverable from `git reflog` until it is garbage-collected; a removed worktree is re-provisioned from the branch. Neither recovery restores work that was never pushed, which is why the first prerequisite is checked rather than assumed.

## Never

Never delete a `.env*` file or any other local secret. They are gitignored and unregenerable — nothing in the repository reconstructs one — so deleting one is permanent loss of the operator's own configuration, not a reclaimed artifact. That holds inside a worktree being removed too, which is part of why removal is never forced: `git worktree remove` refuses while untracked files remain, and that refusal is a signal to stop.

In the primary checkout, only regenerable build output is removable. Every other removal targets the worktree this work provisioned or the branch it opened. The primary checkout holds the only copies of gitignored secrets and local state, so a deletion there is unrecoverable. Never delete `main` itself, locally or on `origin`.

Never delete an artifact another actor created. Never stash to clear a worktree before removing it — the stash stack is shared across every worktree of a clone, so a pop elsewhere takes an entry it did not create.
