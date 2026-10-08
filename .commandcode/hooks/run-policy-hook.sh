#!/usr/bin/env bash
# Adapt native Command Code payloads to existing repository policy hooks without copying their enforcement logic.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
[[ $# == 1 ]] || exit 2
policy=$1
if [[ $policy == agent-policy ]]; then
	exec /bin/bash "$repo/scripts/agent-policy-router.sh" --scope local --harness commandcode
fi
source_dir="$repo/.claude/hooks"
[[ $(dirname "${BASH_SOURCE[0]}") != "$repo/commandcode/hooks" ]] || source_dir="$repo/claude/hooks"
case "$policy" in
require-hippo-boundary | block-env-file-access | remind-rules-propagation | warm-cache-before-push | format-lint-markdown)
	delegate=(bash "$source_dir/$policy.sh") ;;
check-rule-change) delegate=(node "$repo/scripts/check-rule-change.mjs" hook) ;;
ensure-hooks) exec bash "$repo/scripts/ensure-hooks.sh" ;;
*) exit 2 ;;
esac
export CLAUDE_PROJECT_DIR="$repo"
# Keep original native fields. The policy delegates need canonical tool names, file_path, workdir,
# and the same command that the native runtime assembles from command plus optional argv.
if ! mapped=$(jq -c 'def shell_arg: if test("^[A-Za-z0-9_@%+=:,./-]+$") then . else @sh end;
  .tool_name as $native |
  .tool_name = ({shell_command:"Bash",read_file:"Read",read_multiple_files:"Read",read_directory:"Read",
    grep:"Read",glob:"Read",write_file:"Write",edit_file:"Edit"}[$native] // $native) |
  if $native == "shell_command" then
    .tool_input.workdir = (.tool_input.cwd // .tool_input.directory // .tool_input.workdir // .cwd) |
    .tool_input.command = ((.tool_input.command // "") +
      (if (.tool_input.args // [] | length) > 0 then
        " " + (.tool_input.args | map(shell_arg) | join(" ")) else "" end))
  elif $native == "read_multiple_files" then
    (.tool_input.paths // .tool_input.file_paths // .tool_input.file_path // []) as $paths |
    (if ($paths | type) == "array" then $paths else [$paths] end)[] as $path |
    .tool_input.file_path = $path
  else .tool_input.file_path = (.tool_input.file_path // .tool_input.path) end' 2>/dev/null); then
	printf '%s\n' 'Invalid Command Code hook payload.' >&2
	exit 2
fi
while IFS= read -r payload; do
	[[ -n $payload ]] || continue
	# Native shell hooks run in the session directory, while the command can request another
	# cwd. Existing delegates inspect Git and filesystem state, so run them where the tool will.
	execution_dir=$(jq -r 'if .tool_name == "Bash" then .tool_input.workdir // empty else empty end' <<<"$payload")
	# Cache warming and markdown formatting are compute. Match the unchanged delegates'
	# narrow conditions so other tool calls never wait for an unrelated admission.
	admission_class=""
	if [[ $policy == warm-cache-before-push ]] &&
		jq -r '.tool_input.command // empty' <<<"$payload" | grep -qE '^\s*git\s+push\b'; then
		admission_class=ephemeral
	elif [[ $policy == format-lint-markdown ]] &&
		[[ $(jq -r '.tool_input.file_path // empty' <<<"$payload") == *.md ]]; then
		admission_class=transactional
	fi
	output=$(
		# Bash 3.2 substitutions do not inherit errexit; never delegate from a failed requested cwd.
		if [[ -n $execution_dir ]]; then
			cd -- "$execution_dir" || exit 2
		fi
		if [[ -n $admission_class ]]; then
			printf '%s' "$payload" | "$repo/hippo" run --class "$admission_class" --resource-tier standard \
				--disk-path "$repo" -- "${delegate[@]}"
		else
			printf '%s' "$payload" | "${delegate[@]}"
		fi
	)
	# A multi-file read is permitted only when every path passes. Return the first policy
	# response unchanged, so an earlier denial can never be hidden by a later permitted path.
	if [[ -n $output ]]; then printf '%s\n' "$output"; exit 0; fi
done <<<"$mapped"
