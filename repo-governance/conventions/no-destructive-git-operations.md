# No Destructive Git Operations

Git keeps no undo for uncommitted work, and a rewrite of pushed history reaches every clone that holds it. Assume someone else is using the same machine and remote at the same moment.

Adapted from the catalog rule of the same name. What changed: a branch whose pull request merged is still deleted with `-D` where [dev artifact clean-up](../workflows/dev-artifact-clean-up.md) establishes that the change is on `origin/main`, and that workflow's own refusals stand beside this rule.

## The Rule Is the Effect

Any Git invocation whose effect is to discard uncommitted changes, destroy work this actor did not create, rewrite history others may hold, or remove the means of recovering any of those needs explicit approval for that one instance. The spelling is irrelevant: an alias, a script, or an unlisted flag with the same effect is covered. Ask what the command destroys and who made it, not whether it appears below.

## Common Cases

| Operation                                                             | Destroys                                        | Use instead                                                      |
| --------------------------------------------------------------------- | ----------------------------------------------- | ---------------------------------------------------------------- |
| `git push --force`, or `--force-with-lease` without an expected value | remote commits absent locally                   | `--force-with-lease=<branch>:<expected-sha> --force-if-includes` |
| rebasing or amending commits already pushed                           | history others built on                         | a new commit; for the sync rebase, the lease form above          |
| `git reset --hard`, `git checkout -f`, `git switch --discard-changes` | uncommitted changes                             | commit first, or `git stash push -- <path>` and keep the entry   |
| `git checkout -- <path>` or `git restore <path>` over edits           | the unstaged edits at those paths               | commit or stash first                                            |
| `git clean -fd` or `git clean -fdx`                                   | untracked and ignored files, local secrets too  | `git clean -n` to preview, then delete named paths               |
| `git stash drop`, `git stash clear`                                   | stash entries, which then become prunable       | leave the entries                                                |
| `git branch -D`, `git update-ref -d`                                  | a branch, skipping the merged check             | `git branch -d`                                                  |
| expiring the reflog and pruning at once                               | the recovery path itself                        | let automatic maintenance run                                    |
| `git worktree remove --force`, deleting a worktree folder             | a working tree and everything uncommitted in it | plain `git worktree remove`                                      |

The lease form is still a force push and still needs approval; it only refuses to overwrite commits nobody has seen. Runtime data under `data/` and SQLite files are ignored, so `git clean -fdx` destroys them too.

## Asking for Approval

First look for a route that destroys nothing: a new commit, a revert, a removal without force. When none exists:

1. State the exact command as it will run.
2. State what it affects: the ref, the commits left unreachable where they can be determined, and the paths.
3. Ask a yes-or-no question and wait for the answer.
4. Run exactly what was approved. If a flag, ref, or target changes, ask again.

Approval never carries forward. The repository can change between two operations, and the earlier answer was about a state that no longer exists.

## Worktrees Share State

Task worktrees under `worktrees/`, and the detached worktree `release:run` creates, share the object database and every ref with the primary checkout, so pruning and forced removal reach state other worktrees depend on. Never pass `--ignore-other-worktrees`. A destructive operation in a worktree this task does not use needs positive evidence that the worktree is idle.

## Prefer Additive

When a destructive and an additive operation reach the same end state, take the one that leaves a trail. Before any bulk deletion, run its dry-run form.

## Enforcement

No gate checks this. A hook cannot tell an approved force push from an unapproved one, so the rule depends on attention. The `main` ruleset refuses direct pushes, force pushes, and deletion of `main` for every actor.
