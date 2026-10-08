# Command Code Policy Hooks

These scripts connect Command Code's native tool events to the repository's existing policy checks. The registrations
live in [`settings.json`](../settings.json); the adapter invokes each existing delegate by its declared policy name.

## Files

- [`run-policy-hook.sh`](run-policy-hook.sh) — Normalizes native payload fields and invokes the existing policy.
- [`policy-hooks.test.sh`](policy-hooks.test.sh) — Exercises mappings and policy delegation in synthetic repositories.
- [Git fixture isolation regression](git-fixture-isolation.test.sh) — Checks native Git-local environment purge,
  physical fixture ownership, and unchanged disposable parent config, index and HEAD. The
  [policy driver](policy-hooks.test.sh) runs it once after the selector regression without recursively invoking the full driver.

## Local Policy Endpoint

Current settings register `agent-policy` once for native shell, read, multi-read, list, write, edit, search and glob
tools. That selector forwards original JSON to the maintained router with `--scope local --harness commandcode`.
The registration uses `failClosed` and a 30-second timeout. FERRET capture belongs to global configuration.
The [selector regression](agent-policy-selector.test.sh) runs from the policy transport driver.

## Legacy Transport Helpers

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

## Registered Policies

The current settings use the local policy endpoint above.

The adapter and settings contain no model or effort selection. Policy hooks follow the active session's tool calls;
these files do not establish native agent discovery or a live session probe. Authenticated Command Code execution was
not exercised in this documentation pass. The rollout executor records synthetic test results and live evidence.
