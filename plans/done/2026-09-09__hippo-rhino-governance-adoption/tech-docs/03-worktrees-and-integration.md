# Worktrees and the Integration Path

## The Tree

Each repository gains `worktrees/` at its root, holding a single tracked `.gitkeep` and nothing else. Every task worktree is created inside it and never enters history. HIPPO's external the external `hippo-worktrees/` directory beside the checkout — empty today — is retired, because a worktree beside the repository is invisible to the repository's own rules and to anything that inspects it.

This plan's own worktree is `worktrees/repo-rules-adoption/` on branch `worktree/repo-rules-adoption`, in both repositories and here.

## Containment Is the Whole Design

An in-repository worktree is a complete second copy of the tree. Unexcluded, it doubles every Markdown file the word budget counts, every link the link checker resolves, every directory the map checker demands a README for, and every source file a linter walks. The result is not a crash — it is a gate reporting findings against a copy of the repository, which is worse, because the findings look real.

Exclusion is therefore verified by experiment, not by reading globs: create a real worktree, run every gate, and require byte-identical results to the recorded pre-worktree run.

| Consumer      | Change                                                                    | Failure if omitted                                                                                                                                                                |
| ------------- | ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Git           | `/worktrees/*` ignored, `!/worktrees/.gitkeep` re-included                | The primary checkout reports the whole worktree as untracked, and it can be committed.                                                                                            |
| RHINO scan    | `worktrees` added to `scan.exclude-directories` in both repositories      | Every governed document is counted, linked, and mapped twice.                                                                                                                     |
| Go (HIPPO)    | Verify `go build ./...`, `go test ./...`, `golangci-lint`, `scripts/*.sh` | A nested module is normally excluded by the toolchain, but the shell scripts' own globs are the real risk and are not covered by that rule.                                       |
| Cargo (RHINO) | Verify `cargo fmt --all`, `clippy --all-targets`, `xtask` walks           | A nested crate outside the workspace members is normally ignored; `xtask` walking the root is not.                                                                                |
| Prettier      | Verify against `.prettierignore` in both repositories                     | Formatting checks run over a duplicate tree and can report a file twice.                                                                                                          |
| ShellCheck    | Verify the lint target list in RHINO                                      | Bootstrap scripts linted twice, or a stale copy linted instead of the real one.                                                                                                   |
| Disk          | Accepted, not mitigated                                                   | A RHINO worktree carries its own `target/`, measured in gigabytes; a HIPPO worktree its own `.cache/`. This is a cost of the convention, and it is stated rather than discovered. |

RHINO's `scan.exclude-directories` also gains `local-tmp`, which is a live omission unrelated to worktrees: it is git-ignored, but RHINO walks the filesystem rather than the index, so scratch Markdown is reachable by the gate today.

## Bootstrapping the Convention

The first change to each repository creates `worktrees/` and its ignore rules — and by this plan's own requirement it must be authored inside a worktree that the repository does not yet ignore. That works: `git worktree add worktrees/repo-rules-adoption` needs only a path on disk. The consequence is that until that first pull request merges, the primary checkout reports the worktree directory as untracked. That is expected, brief, and preferable to making the first change from `main` as an exception to the rule the change is establishing.

## Hooks

Each repository already runs `commit-msg`, `pre-commit`, and `pre-push` through Husky, and a worktree's hooks are inert until its dependencies are installed. So the integration procedure's second step is an install, before any Git mutation or gate run in that worktree — a worktree whose hooks were never activated pushes unverified work. This is the one step in the procedure that has no visible symptom when skipped, which is why it is a numbered step rather than an assumption.

Hook contents change minimally:

- **HIPPO** keeps `npm run test:quick` unguarded. HIPPO cannot guard HIPPO; its `resource-aware-development` document states this as the governed exception rather than leaving a reader to infer it from an absence.
- **RHINO** keeps its existing guarded call, `./hippo run --class ephemeral --disk-path . -- cargo xtask test-quick`, unchanged, including its exit-`75` rule: the host was busy, so retry, never bypass.

Neither repository adopts this one's conditional path routing in its hooks. That routing exists because a monorepo push can touch unrelated subsystems; a single-project repository has one quick gate and no routing decision to make. Adding it would be machinery with nothing to select between.

## The Integration Path

Both repositories practise trunk-based development in its scaled variant: `main` is the trunk, every branch off it is short-lived, and work reaches the trunk through a pull request rather than a direct commit. The convention is written into each repository's `conventions/integration-path.md` and made executable as the `worktree-to-pr` skill:

1. Create the worktree under `worktrees/<name>/` at the repository root.
2. Install dependencies from inside it, before any Git mutation or gate run, to activate its hooks.
3. Do the work there. Commit thematically; commitlint runs on each message.
4. Push the branch to `origin` and open a pull request against `main`.
5. Merge only after the aggregate quality-gate check reports success. No approving review is required, because the sole maintainer cannot approve their own pull request and requiring one would block every merge.
6. Keep history linear. Rebase a stale branch onto `main`; never merge `main` into it.
7. Sync before working and before resuming: `git fetch origin` then `git rebase origin/main`, never auto-stashing, discarding, or auto-resolving. An unclean tree or a rebase conflict stops the work. When the sync brings in commits the branch did not have, read the whole incoming diff and reconcile the current task against it before continuing.
8. Provision **one** worktree per plan or ad-hoc task and reuse it for every delivery unit. A second `git worktree add` for the same work is a defect. Units land serially: land one, sync from `origin/main`, then branch the next in the same directory.
9. Keep the branch short-lived in a measurable sense: merge it the same day where possible, one to two days as the maximum, and past two days rebase or abandon rather than carry it.
10. Delete all three artifacts the work created — the worktree, the local branch, and that branch on `origin` — once every delivery unit that used the worktree has landed. Confirm nothing is unpushed and nothing is running in the worktree first. Retain a worktree whose run ended partial or failed, and say so, rather than deleting the evidence.

The exception this repository grants its release worktree does not travel. Neither CLI builds releases from a detached worktree — HIPPO builds through `scripts/build-release.sh` and RHINO through `cargo xtask dist`, both in place — so the convention in these two repositories has no exceptions to the location rule at all, and says so. What does travel is the surrounding discipline: a release is invoked from the primary checkout on local `main`, never from a `worktrees/` checkout, and never from a task branch even when that branch already points at the released revision.

Server-side enforcement is why local hooks are not the last word: a pull request can be opened from any checkout, including one whose hooks never ran. That is [the gate's job](04-pr-gate-and-ruleset.md).

## Related

- [Technical design](README.md)
- [The gate and ruleset design](04-pr-gate-and-ruleset.md)
