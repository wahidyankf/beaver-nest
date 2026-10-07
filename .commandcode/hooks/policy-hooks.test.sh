#!/usr/bin/env bash
# Native policy adapter tests use synthetic repositories and unchanged policy delegates.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
pass=0
fail=0
check() {
	local label=$1
	shift
	if "$@" >/dev/null; then pass=$((pass + 1)); else echo "FAIL: $label"; fail=$((fail + 1)); fi
}
bridge="$(dirname "$0")/run-policy-hook.sh"
if [[ ! -f $bridge ]]; then echo 'FAIL: native policy adapter is missing'; exit 1; fi
fixture="$scratch/repository"
mkdir -p "$fixture/.commandcode/hooks" "$fixture/.claude/hooks" "$scratch/session" "$scratch/home"
cp "$bridge" "$fixture/.commandcode/hooks/"
git -C "$fixture" init -q
printf '#!/usr/bin/env bash\ncat\n' >"$fixture/hippo"
chmod +x "$fixture/hippo"
touch "$fixture/hippo.lock"
source_dir="$repo/.claude/hooks"
[[ -d $repo/claude/hooks ]] && source_dir="$repo/claude/hooks"
if [[ -f $source_dir/require-hippo-boundary.sh ]]; then
	cp "$source_dir/require-hippo-boundary.sh" "$fixture/.claude/hooks/"
fi
cat >"$fixture/.claude/hooks/remind-rules-propagation.sh" <<'DELEGATE'
#!/usr/bin/env bash
jq -c --arg context "$CLAUDE_PROJECT_DIR" '. + {delegate_context:$context}'
DELEGATE
run_bridge() {
	local policy=$1 payload=$2
	code=0
	out=$(cd "$scratch/session" && printf '%s' "$payload" | HOME="$scratch/home" \
		/bin/bash "$fixture/.commandcode/hooks/run-policy-hook.sh" "$policy" 2>"$scratch/errors") || code=$?
}
run_bridge remind-rules-propagation '{"tool_name":"write_file","tool_input":{"file_path":".commandcode/settings.json","content":"synthetic"}}'
check 'write tool maps while preserving native fields' jq -e '.tool_name == "Write" and .tool_input.content == "synthetic"' <<<"$out"
check 'delegate context is the owning checkout' test "$(jq -r '.delegate_context' <<<"$out")" = "$fixture"
run_bridge remind-rules-propagation '{"tool_name":"grep","tool_input":{"path":"/synthetic/.env.prod","pattern":"synthetic"}}'
check 'native path aliases preserve their original fields' jq -e '.tool_input.file_path == .tool_input.path and .tool_input.pattern == "synthetic"' <<<"$out"
run_bridge remind-rules-propagation "$(jq -nc --arg cwd "$fixture" '{tool_name:"shell_command",tool_input:{command:"npm",args:["install"],cwd:$cwd}}')"
check 'argv is assembled and retained' jq -e '.tool_name == "Bash" and .tool_input.command == "npm install" and .tool_input.args == ["install"]' <<<"$out"
check 'native cwd identifies the consumer' jq -e '.tool_input.workdir == .tool_input.cwd' <<<"$out"
if [[ -f $fixture/.claude/hooks/require-hippo-boundary.sh ]]; then
run_bridge require-hippo-boundary "$(jq -nc --arg cwd "$fixture" '{tool_name:"shell_command",tool_input:{command:"npm",args:["install"],cwd:$cwd}}')"
check 'existing HIPPO policy denies unguarded native argv' jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out"
run_bridge require-hippo-boundary "$(jq -nc --arg cwd "$fixture" '{tool_name:"shell_command",tool_input:{command:"npm",args:["run","check:complete"],cwd:$cwd}}')"
check 'already guarded scripts stay permitted' test -z "$out"
run_bridge require-hippo-boundary "$(jq -nc --arg cwd "$fixture" '{tool_name:"shell_command",tool_input:{command:"./hippo run --class ephemeral --resource-tier light --disk-path . -- npm install",directory:$cwd}}')"
check 'guarded native shell commands stay permitted' test -z "$out"
fi
cat >"$fixture/.claude/hooks/block-env-file-access.sh" <<'DELEGATE'
#!/usr/bin/env bash
input=$(cat)
if [[ $(jq -r '.tool_input.file_path' <<<"$input") == *.env.prod ]]; then
	printf '{"hookSpecificOutput":{"permissionDecision":"deny"}}\n'
fi
DELEGATE
run_bridge block-env-file-access '{"tool_name":"read_multiple_files","tool_input":{"paths":["/synthetic/README.md","/synthetic/.env.prod"]}}'
check 'every native multi-file path reaches the existing file policy' jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out"
if [[ -f $source_dir/block-env-file-access.sh ]]; then
	cp "$source_dir/block-env-file-access.sh" "$fixture/.claude/hooks/"
	for tool in read_file write_file edit_file grep glob; do
		run_bridge block-env-file-access "$(jq -nc --arg tool "$tool" '{tool_name:$tool,tool_input:{path:"/synthetic/.env.prod"}}')"
		check "existing env policy denies native $tool" jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out"
	done
	run_bridge block-env-file-access '{"tool_name":"read_file","tool_input":{"file_path":"/synthetic/.env.example"}}'
	check 'existing env policy allows the template' test -z "$out"
	run_bridge block-env-file-access '{"tool_name":"shell_command","tool_input":{"command":"cat","args":["/synthetic/.env.prod"]}}'
	check 'existing env policy examines assembled native argv' jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out"
fi
cat >"$fixture/.claude/hooks/warm-cache-before-push.sh" <<'DELEGATE'
#!/usr/bin/env bash
cat
DELEGATE
cat >"$fixture/hippo" <<'ADMISSION'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${BASH_SOURCE[0]}.args"
while [[ $1 != -- ]]; do shift; done
shift
exec "$@"
ADMISSION
run_bridge warm-cache-before-push '{"tool_name":"shell_command","tool_input":{"command":"git","args":["push","origin","main"]}}'
check 'native push cache work receives HIPPO admission' test -f "$fixture/hippo.args"
check 'native push preserves arguments for the delegate' jq -e '.tool_input.command == "git push origin main"' <<<"$out"
rm "$fixture/hippo.args"
run_bridge warm-cache-before-push '{"tool_name":"shell_command","tool_input":{"command":"git","args":["status"]}}'
check 'ordinary shell calls do not request cache admission' test ! -e "$fixture/hippo.args"
cat >"$fixture/.claude/hooks/format-lint-markdown.sh" <<'DELEGATE'
#!/usr/bin/env bash
cat
DELEGATE
run_bridge format-lint-markdown '{"tool_name":"write_file","tool_input":{"file_path":"README.md","content":"synthetic"}}'
check 'native markdown formatting receives admission' test -f "$fixture/hippo.args"
check 'native formatting uses transactional admission' grep -q '^transactional$' "$fixture/hippo.args"
check 'native post-edit fields reach the existing formatter' jq -e '.tool_name == "Write" and .tool_input.content == "synthetic"' <<<"$out"
rm -f "$fixture/hippo.args"
run_bridge format-lint-markdown '{"tool_name":"edit_file","tool_input":{"file_path":"fixture.txt"}}'
check 'non-markdown edits do not request formatting admission' test ! -e "$fixture/hippo.args"
check 'non-markdown formatter delegation remains successful' test "$code" -eq 0
if [[ -f $repo/scripts/ensure-hooks.sh ]]; then
	mkdir -p "$fixture/scripts" "$fixture/node_modules"
	cp "$repo/scripts/ensure-hooks.sh" "$fixture/scripts/"
	git -C "$fixture" config core.hooksPath .husky/_
	run_bridge ensure-hooks '{}'
	check 'native session bootstrap delegates its installed happy path silently' test -z "$out"
	check 'native session bootstrap succeeds' test "$code" -eq 0
fi
# Bash 3.2 does not inherit errexit in substitutions: refusal must precede every policy/admission effect.
for policy in require-hippo-boundary block-env-file-access remind-rules-propagation warm-cache-before-push format-lint-markdown; do
	cat >"$fixture/.claude/hooks/$policy.sh" <<'DELEGATE'
#!/usr/bin/env bash
printf '%s\n' "$PWD" >"$CLAUDE_PROJECT_DIR/delegate.effect"
touch "$CLAUDE_PROJECT_DIR/$(basename "$0").effect"
cat
DELEGATE
done
mkdir -p "$fixture/working directory" "$scratch/inaccessible"
touch "$scratch/not-directory"
chmod 000 "$scratch/inaccessible"
no_policy_effects() {
	[[ $code -ne 0 && -z $out && ! -e $fixture/delegate.effect && ! -e $fixture/hippo.args &&
		! -e $fixture/$policy.sh.effect ]]
}
for execution_dir in "$scratch/missing" "$scratch/not-directory" "$scratch/inaccessible"; do
	# Prove the fixture really refuses cd; do not mistake elevated access for a passing denial test.
	check "fixture refuses $(basename "$execution_dir")" /bin/bash -c 'if cd "$1" 2>/dev/null; then exit 1; fi' _ "$execution_dir"
	for policy in require-hippo-boundary block-env-file-access remind-rules-propagation warm-cache-before-push format-lint-markdown; do
		rm -f "$fixture/delegate.effect" "$fixture/hippo.args" "$fixture/$policy.sh.effect"
		run_bridge "$policy" "$(jq -nc --arg cwd "$execution_dir" '{tool_name:"shell_command",tool_input:{command:"git",args:["push","origin","main"],file_path:"README.md",cwd:$cwd}}')"
		check "$policy refuses $(basename "$execution_dir") without effects" no_policy_effects
	done
done
chmod 700 "$scratch/inaccessible"
for policy in require-hippo-boundary block-env-file-access remind-rules-propagation warm-cache-before-push format-lint-markdown; do
	run_bridge "$policy" "$(jq -nc --arg cwd "$fixture/working directory" '{tool_name:"shell_command",tool_input:{command:"git",args:["push","origin","main"],file_path:"README.md",cwd:$cwd}}')"
	check "$policy still delegates from the requested valid cwd" test "$(cat "$fixture/delegate.effect")" = "$fixture/working directory"
	check "$policy valid cwd remains successful" test "$code" -eq 0
done
run_bridge '../outside' '{}'
check 'delegate names cannot escape the hook directory' test "$code" -eq 2
run_bridge require-hippo-boundary 'not json'
check 'malformed native payload fails before delegation' test "$code" -ne 0
printf 'Native policy adapter: %s passed, %s failed\n' "$pass" "$fail"
[[ $fail == 0 ]]
