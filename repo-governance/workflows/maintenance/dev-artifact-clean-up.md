# Dev Artifact Clean-Up

## Goal

Remove only task-created development artifacts and bring primary `main` level with `origin/main`. The [integration path](../../conventions/integration-path.md) makes these obligations; this workflow gives the safe order.

Run it once every delivery unit that used the worktree has landed, or once the work is deliberately abandoned. Not between units, because the worktree is reused. Never as a periodic sweep.

## Scope

Six things, and nothing else: the worktree this work provisioned, its local branch, that branch on `origin`, the regenerable build output this work produced, the `local-tmp/` scratch it wrote, and the primary checkout's `main` ref.

Build output means `dist/`, `.next/`, and the build caches a documented command rebuilds — in the worktree, and the same regenerable output in the primary checkout. It never means a `.env*` file or any other local secret, in any location.

Scratch means what this work itself wrote under `local-tmp/`, never another actor's; see [other actors and bare clones](dev-artifact-clean-up/001-other-actors-and-bare-clones.md).

Everything else on the machine belongs to someone else — a worktree this work did not create, a branch it did not open, another repository's state — even when they look abandoned.

## Prerequisites

1. Nothing is unpushed: `git status --porcelain` is empty and `git log <branch> --not --remotes` prints nothing.
2. Nothing is running in the worktree.
3. The worktree is one this work provisioned, confirmed against `git worktree list`.
4. The pull request reports merged, or the abandonment is deliberate.

A worktree whose run ended `partial` or failed is retained and said so, not deleted.

## Steps

Run from the primary checkout, never from inside the directory being removed: a shell holding a deleted directory resolves the next relative path somewhere unintended.

```sh
git fetch origin --prune
git merge --ff-only origin/main
git rev-list --left-right --count HEAD...origin/main
git worktree remove worktrees/<name>
git branch -d worktree/<name>
git push origin --delete worktree/<name>
```

Purge the build output this work produced, and its own scratch, once delivery has landed and nothing uses it. Retain logs, traces, and any other non-regenerable evidence a failure would need.

`--prune` drops the remote-tracking ref for a branch the forge deleted on merge; without it the deleted branch lingers in `git branch -a`. Delete on `origin` only if merging did not. A clone with no primary checkout: [other actors and bare clones](dev-artifact-clean-up/001-other-actors-and-bare-clones.md).

## When `-d` Refuses

`git branch -d` refuses a branch whose commits `main` does not literally contain, so after a rebase or squash merge it always refuses: the landed commits carry different hashes.

Read the refusal first. After the steps' fetch and worktree removal, `git branch -D` is correct only for a branch that **landed** — its pull request `MERGED` with `headRefOid` equal to the tip, or `git cherry origin/main <branch>` printing only `-` lines — or is **stale** — its tip over 72 hours old, with no open pull request.

When that cherry prints a `+` line, preserve a stale tip first: keep `origin/<branch>` if it holds the tip, else `git bundle create <path> origin/main..<branch>` under the primary checkout's ignored `local-tmp/`, recording the path; its `origin` copy goes only after that. Otherwise `-D` discards work: retain the branch and say why.

## Verification

`git worktree list` no longer names the path, `git branch --list` no longer prints the branch, the branch is gone from `origin`, the purged build output and this work's scratch are gone, and the divergence count reads `0 0`.

## Recovery

A deleted branch whose commits are unreachable is recoverable from `git reflog` until garbage collection; a removed worktree is re-provisioned from the branch. Neither restores unpushed work, so the first prerequisite is checked, not assumed.

## Never

Never delete a `.env*` file or any other local secret-bearing file or directory. They are gitignored and unregenerable; deleting one permanently loses the operator's configuration. That holds inside a worktree being removed too, which is why removal is never forced: `git worktree remove` refuses while untracked files remain, and that refusal is a signal to stop.

In the primary checkout, only regenerable build output and this work's own scratch are removable. Every other removal targets the worktree this work provisioned or the branch it opened. The primary checkout holds the only copies of gitignored secrets and local state, so a deletion there is unrecoverable. Never delete `main` itself, locally or on `origin`.
