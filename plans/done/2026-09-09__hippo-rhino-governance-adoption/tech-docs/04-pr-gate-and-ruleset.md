# The Pull-Request Gate and the Ruleset

## The Shape

One workflow per repository, `pr-quality-gate.yml`, triggered on `pull_request` against `main`, producing one aggregate check that is the sole required status check. The workflow it replaces, `ci.yml`, is deleted in the same change.

Deleted rather than demoted, for one reason: a demoted `ci.yml` still runs the same suites on the same events, so a change to a hook contract would have two places to make it and one of them would eventually be missed. One file, one contract.

Absorbed rather than mirrored, for another: both repositories' existing `ci.yml` is **stronger** than their hooks. HIPPO's `pre-push` runs `npm run test:quick`, while its CI already runs `scripts/test.sh` across ubuntu and macOS. RHINO's `pre-push` runs `cargo xtask test-quick`, while its CI already adds `cargo deny`, coverage tooling, and `cargo xtask self-validate`. A gate that mirrored the hooks literally would be a downgrade on the day it landed. The rule this plan applies is that the gate must be a **superset**: everything the hooks enforce, plus everything CI already ran.

## Job Inventory

### RHINO

| Job                  | Mirrors                    | Runs                                                                                                     |
| -------------------- | -------------------------- | -------------------------------------------------------------------------------------------------------- |
| `commit-messages`    | `commit-msg`               | commitlint from the merge base to the pull-request head.                                                 |
| `formatting`         | `pre-commit`               | Prettier `--check --ignore-unknown` over added, copied, modified and renamed files; `cargo fmt --check`. |
| `quick`              | `pre-push`                 | `cargo xtask test-quick`, unguarded.                                                                     |
| `supply-chain`       | _(absorbed from `ci.yml`)_ | `cargo clippy --all-targets --all-features -- -D warnings`, `cargo deny check`.                          |
| `self-validation`    | _(absorbed from `ci.yml`)_ | `cargo xtask self-validate`, which is also where the new harness roster proves itself.                   |
| `consumer-bootstrap` | _(new)_                    | Conditional on `hippo` or `hippo.lock` changing: verify the pinned bootstrap and ShellCheck the wrapper. |
| `quality-gate`       | —                          | Aggregate. The required check.                                                                           |

### HIPPO

| Job                   | Mirrors                          | Runs                                                                                                           |
| --------------------- | -------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `commit-messages`     | `commit-msg`                     | commitlint from the merge base to the pull-request head.                                                       |
| `formatting`          | `pre-commit`                     | Prettier `--check --ignore-unknown` over added, copied, modified and renamed files; `scripts/format-check.sh`. |
| `test`                | `pre-push`, and a superset of it | `scripts/test.sh` on ubuntu and macOS, which contains `test:quick`.                                            |
| `repository-contract` | _(new)_                          | Conditional on governed content or its configuration changing: the pinned `./rhino` documentation gate.        |
| `consumer-bootstrap`  | _(new)_                          | Conditional on `rhino` or `rhino.lock` changing: verify the pinned bootstrap.                                  |
| `release-build`       | _(absorbed from `ci.yml`)_       | Whatever the existing job builds, unchanged.                                                                   |
| `quality-gate`        | —                                | Aggregate. The required check.                                                                                 |

HIPPO's `repository-contract` job is genuinely new: its pinned RHINO gate has never run in CI, only through whatever the maintainer remembered to run locally. That is the single largest enforcement gain in either repository.

## Three Details That Matter

**The commit range is the merge base, not the base tip.** HIPPO's current `ci.yml` lints from `github.event.pull_request.base.sha`. A branch behind `main` then re-lints commits it never authored and fails on someone else's history. Use `git merge-base` against a fetched base ref.

**Commitlint reads the real head, not the synthetic merge commit.** GitHub's merge commit carries a `Merge ... into ...` subject that no Conventional Commits rule accepts. Check out `github.event.pull_request.head.sha` in that job specifically.

**A skipped job is not a pass.** Conditional jobs legitimately skip, and a skipped required check never reports at all, so merge protection points at the aggregate. The aggregate must treat `skipped` and `cancelled` as failure and require an explicit `success` from every dependency — `if: always()` plus an explicit result check, never `needs` alone.

## No HIPPO Guard in CI

This repository wraps every CI step in `./hippo run --class ephemeral --disk-path .`. Neither of these gates does.

HIPPO arbitrates contention on one shared workstation. A GitHub runner is dedicated, ephemeral, and has no competing work, so the guard has nothing to arbitrate; what it adds is a download, a checksum verification, and an exit-`75` "host was busy" path that cannot occur and therefore cannot be tested. In HIPPO's own repository it is additionally self-referential.

What replaces it is better targeted. Each gate gains a `consumer-bootstrap` job that runs when the pinned consumer files change — the pinned wrapper, its lock, its policy example, its own suite. That is the surface which genuinely needs proving on a clean machine, and it is the surface a local hook can prove least well.

## What Authorizes a Merge

The ruleset requires no approving review, so nothing human reads every line before merge. Both repositories therefore adopt the five merge preconditions unchanged, adapted only in naming their own aggregate check:

- the aggregate check is green **for the pull request's current head SHA and current base** — a run against an earlier head is stale evidence and authorizes nothing;
- a data-safety review of that same head finds no credential, personal or machine identifier, private infrastructure value, or artefact carrying one, with the head SHA pinned and recorded, and a push that moves the head voids the result;
- the branch is current with `main`, brought forward by rebase, with no conflict reported;
- every review conversation is resolved or dismissed;
- every gate the changed reachable behaviour requires has a passing terminal result, and where nothing reachable changed, that is said explicitly rather than left open.

Every pull request opens as a draft and is flipped to ready only when the work meets its done definition. Readiness states that the work is finished; it authorizes nothing by itself.

This is why neither repository's coverage floor, specification corpus, or adapter strictness may be weakened by this plan. Whatever the gate does not exercise, nothing checks — so weakening a suite silently widens what "safe to merge" is willing to mean.

## The Ruleset

Identical in both repositories, applied to `main`, created **last**:

- Refuse direct pushes, force pushes, and branch deletion for every actor.
- Require a pull request with **zero** approving reviews. The sole maintainer cannot approve their own pull request; requiring one would block every merge and the first workaround would become the permanent one.
- Require linear history.
- Require the aggregate `quality-gate` status check.
- **No bypass actors.** Not the owner, not admins, not an app.

Both repositories are public, so rulesets cost nothing.

### Ordering

The required check name must come from a run the server has actually seen, not from the workflow file. A name that never reports leaves every pull request permanently pending, and with no bypass configured there is no way to merge the fix. So per repository: gate lands and runs green on a real pull request, the observed check name is read back, then the ruleset is created, then a direct push to `main` is attempted and its refusal recorded as evidence.

### The Accepted Cost

With no bypass, a broken gate makes `main` unwritable until a pull request repairs it — and that pull request must itself pass the broken gate. This is accepted deliberately. Two things make it survivable: the gate's definition lives inside the repository, so the fix is an ordinary change rather than an escalation; and the gate is proved green on a real pull request before the ruleset exists, so it is never enabled against an unproven check.

The alternatives were considered and declined. A configured owner bypass stops the rule being machine-enforced, and an escape hatch that exists gets used. A documented procedure for temporarily deleting the ruleset is the same bypass with more steps, and it hides the exception in a document instead of in the ruleset where an auditor would look.

## Related

- [Technical design](README.md)
- [Worktrees and the integration path](03-worktrees-and-integration.md)
- [Business requirements](../brd.md)
