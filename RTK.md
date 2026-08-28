# RTK — Rust Token Killer

Use RTK as the token-optimized proxy for shell commands in Codex, Claude Code, and OpenCode. These repository instructions follow the upstream [Codex awareness document](https://github.com/rtk-ai/rtk/blob/develop/hooks/codex/rtk-awareness.md); each harness uses its own upstream-supported integration route.

## Required Usage

Prefix shell commands with `rtk` while preserving repository-mandated command forms and all safety rules:

```sh
rtk git status
rtk npm exec -- nx run badakmini-cli:test:repo
rtk pytest -q
```

Use `rtk proxy <command>` only when unfiltered command output is necessary for diagnosis.

## Meta Commands

```sh
rtk gain
rtk gain --history
rtk discover
rtk proxy <command>
```

## Verification

```sh
rtk --version
rtk gain
which rtk
```

## Harness Integration

Repository instructions make Codex aware of RTK. Install the upstream user-level integration for Claude Code with `rtk init --global` and for OpenCode with `rtk init --global --opencode`. Inspect the active integration with `rtk init --show`. Do not commit generated user-global hooks, plugins, paths, or settings.

## Command Authorization

All `rtk *` commands are globally pre-authorized. Run them without confirmation while still respecting secret-handling and destructive-operation safeguards.
