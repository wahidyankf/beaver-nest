# Push-Hook Verification

Do not pass `--no-verify` to `git push` unless the user explicitly authorizes bypassing hooks for that specific push.

## Requirements

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
