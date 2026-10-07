# Other Actors and Bare Clones

What [dev artifact clean-up](../dev-artifact-clean-up.md) may reclaim that the current piece of work did not write, what it never touches, and how a clone without a primary checkout reconciles.

Scratch a crashed session left behind is reclaimed only deliberately, never by an ambient sweep: once unmodified for seven days, it moves to `local-tmp/.reclaim-quarantine-YYYY-MM-DD/`, and is deleted once nothing needs it.

An exact ignored, nonshared cache such as `.fvm-cache` may be scratch even when another task created it, but only after recorded regeneration, non-use, and secret-free evidence. This never makes a shared cache removable.

Never delete an artifact another actor created. Never stash to clear a worktree before removing it — the stash stack is shared across every worktree of a clone, so a pop elsewhere takes an entry it did not create.

Where a clone has no primary checkout, `git fetch origin main:main` reconciles without one, never against a branch checked out elsewhere.
