# Command Code Policy Hooks

These scripts connect Command Code's native tool events to the repository's existing policy checks. The registrations
live in [`settings.json`](../settings.json); the adapter invokes each existing delegate by its declared policy name.

## Files

- [`run-policy-hook.sh`](run-policy-hook.sh) — Normalizes native payload fields and invokes the existing policy.
- [`policy-hooks.test.sh`](policy-hooks.test.sh) — Exercises mappings and policy delegation in synthetic repositories.

## Native payload mapping

Settings match native display IDs such as `SHELL`, `READ`, `WRITE`, and `EDIT`. Payload `tool_name` identifiers such as
`shell_command`, `read_file`, `write_file`, and `edit_file` map to the tool names the existing policies expect. Original
native fields remain available; path aliases supply `file_path`, and multi-file reads check every path before returning
permission. The first delegate response is returned unchanged, so a later allowed path cannot hide an earlier denial.

Shell commands combine `command` and optional `args`, preserving argument quoting. The adapter takes the actual tool
working directory from native `cwd`, `directory`, `workdir`, or the payload's session `cwd`, and runs the policy there.
The owning checkout supplies the delegates and `CLAUDE_PROJECT_DIR`; this keeps repository policy available even when
the tool runs from another directory.

The adapter also recognizes `format-lint-markdown`. Markdown formatting receives transactional HIPPO admission;
the current settings determine which policy routes run for each event.

## Registered policies

The current settings register the existing
[HIPPO boundary guard](../../.claude/hooks/require-hippo-boundary.sh) for native shell tools with `failClosed`.

The adapter and settings contain no model or effort selection. Policy hooks follow the active session's tool calls;
these files do not establish native agent discovery or a live session probe. Authenticated Command Code execution was
not exercised in this documentation pass. The rollout executor records synthetic test results and live evidence.
