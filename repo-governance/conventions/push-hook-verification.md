# Push-Hook Verification

Do not pass `--no-verify` to `git push` unless the user explicitly authorizes bypassing hooks for that specific push.

## Requirements

- Run the [`test:quick` quality gate](../development/quality-gates.md) through one HIPPO-guarded `nx affected` for every non-deleted ref being pushed, using `origin/main` as the base and the pushed local commit as the head. Nx consumes the admitted `NX_PARALLEL` allocation for independent projects. Only affected projects that define `test:quick` participate.
- Keep Nx Cloud disabled for pre-push checks.
- Run the full repository documentation gate when a pushed range changes repository Markdown, governed documentation trees, Badakmini source or adapters, or the pre-push hook itself. Validator changes must prove the existing corpus before they can enforce it.
- Treat authorization to push and authorization to bypass push hooks as separate permissions. A normal push request does not authorize `--no-verify`.
- Obtain explicit user permission that identifies or clearly includes the hook bypass before using `--no-verify`.
- Do not carry bypass permission into a later push or broader scope.
- If a hook fails, preserve its output, identify the failing check, and reproduce the failure without bypassing verification.
- Trace the failure to its root cause and fix the earliest responsible repository code, test, configuration, dependency, or environment issue within the authorized scope.
- Do not disable, remove, mute, weaken, or superficially satisfy a hook or its checks merely to make the push pass.
- Rerun the failed check and relevant verification after the fix, then use a normal verified push.
- Convenience, time pressure, repeated failure, or difficulty diagnosing the cause never justify `--no-verify`.
- If the root cause cannot be fixed within the authorized scope, report the evidence and unresolved blocker. Ask for direction only under the [last-resort questions convention](last-resort-questions.md).
- Even when bypass is explicitly authorized, disclose which safeguards will be skipped and any unresolved failure before pushing.

This convention keeps repository safeguards effective through root-cause correction rather than bypasses or cosmetic fixes, while preserving the user's authority to approve a deliberate exception. It supplements the [commit-authorization convention](commit-authorization.md); neither permission implies the other.
