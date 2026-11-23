# Push-Hook Verification

Do not pass `--no-verify` to `git push` unless the user explicitly authorizes bypassing hooks for that specific push.
The one standing HIPPO-contention exception lives in [HIPPO-Congestion Exception](#hippo-congestion-exception);
[Capacity-Held Hook](push-hook-verification/001-capacity-held-hook.md) holds its background.

## Requirements

- Run the [public-safety screen](../../scripts/public-safety/README.md) over the pushed range. Pre-push runs only this leak scan (C6).
- Every other gate runs at pull-request; see the [gate inventory](../development/quality/gate-inventory.md). Do not run `test:quick`, document checks, or bootstrap suites at pre-push.
- Treat authorization to push and authorization to bypass push hooks as separate permissions. A normal push request does not authorize `--no-verify`.
- Obtain explicit user permission that identifies or clearly includes the hook bypass before using `--no-verify`.
- Do not carry bypass permission into a later push or broader scope.
- If a hook fails, preserve its output, name the failing check, and reproduce it without bypassing verification.
- Trace the failure to its root cause and fix the earliest responsible code, test, configuration, dependency, or environment issue in scope.
- Do not disable, remove, mute, weaken, or superficially satisfy a hook or its checks merely to make the push pass.
- Rerun the failed check and relevant verification after the fix, then use a normal verified push.
- Convenience, time pressure, repeated failure, or difficulty diagnosing the cause never justify `--no-verify`.
- If the root cause cannot be fixed within the authorized scope, report the evidence and unresolved blocker. Ask for direction only under the [last-resort questions convention](last-resort-questions.md).
- A bypass never covers the public-safety screen, which `--no-verify` would otherwise skip, nor the [push leak review](../workflows/quality/pr-leak-review/002-push-review.md). Before an authorized bypass push, screen with `RHINO_GATE_SURFACE=pre-push scripts/public-safety/check.sh </dev/null`, then commit by commit with `PUBLIC_SAFETY_BASE` and `PUBLIC_SAFETY_HEAD` set to the remote tip (or `origin/main` for a new branch) and the pushed commit; push only when both exit `0`.
- Even when bypass is explicitly authorized, disclose which safeguards will be skipped and any unresolved failure before pushing.

## HIPPO-Congestion Exception

When a task-owned branch lands through a pull request whose quality gate mirrors the skipped hook's deterministic checks, pushing it with `--no-verify` and letting CI run the gate is sound, and preferable under HIPPO contention (deferral or failure, exit `124`/`125` never-started, abnormal latency, or a wait). The maintainer pre-authorizes this commit and push bypass with no per-instance prompt when every condition below holds. This is the only standing exception above. A hook that reported a violation is still fixed at cause.

- The hook produced no check result because HIPPO admission deferred or failed it (exit `124` never-started, exit `125`, abnormal latency, or a wait), not because a gate found a violation.
- The push opens or updates the pull request running that mirror; the `Quality gate` aggregate in `.github/workflows/pr-quality-gate.yml` is that mirror.
- The manual screens pass: the tree screen and the per-commit range screen from the bypass paragraph above both exit `0`, with no push-leak-review finding. The `commit-msg` hook stays enabled.
- Formatting is done by hand or editor; the pull-request gate verifies it.
- The bypass cites the HIPPO receipt and screen evidence in the push and PR notes, and never carries into a later operation.
- The branch does not merge until the hosted gate passes on the exact pushed head; a later push owes a fresh pass.

Direct pushes to `main` stay outside this exception: explicit per-instance authorization still applies, strongly discouraged except for manual override.

This convention keeps repository safeguards effective through root-cause correction rather than bypasses or cosmetic fixes, while preserving the user's authority to approve a deliberate exception. It supplements the [commit-authorization convention](commit-authorization.md); neither permission implies the other.
