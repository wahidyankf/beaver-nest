# RTK — Rust Token Killer (Codex CLI)

Use RTK as the token-optimized proxy for shell commands. These instructions follow the upstream [Codex awareness document](https://github.com/rtk-ai/rtk/blob/develop/hooks/codex/rtk-awareness.md).

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

## Command Authorization

All `rtk *` commands are globally pre-authorized. Run them without confirmation while still respecting secret-handling and destructive-operation safeguards.
