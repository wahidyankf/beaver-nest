#!/usr/bin/env bash
# Validate Rhino's typed commit-message input without exposing a hook-file path.
set -euo pipefail

: "${RHINO_GATE_MESSAGE:?RHINO_GATE_MESSAGE is required}"
message_file=$(mktemp "${TMPDIR:-/tmp}/beaver-nest-commit-message.XXXXXX")
trap 'rm -f -- "$message_file"' EXIT
printf '%s\n' "$RHINO_GATE_MESSAGE" >"$message_file"
npm exec -- commitlint --edit "$message_file"
