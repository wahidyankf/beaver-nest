#!/usr/bin/env bash
# Execute the workflow's real route predicate against isolated Git changes, without a remote fetch.
set -euo pipefail
repository_root=$(cd "$(dirname "$0")/../.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
scratch=$(cd "$scratch" && pwd -P)
fixture="$scratch/repository"
mkdir -p "$fixture"
unset GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
export GIT_CEILING_DIRECTORIES="$scratch" GIT_DIR="$fixture/.git"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
git -C "$fixture" -c init.templateDir= init -q "$fixture"
fixture_git() {
	local actual
	actual=$(git -C "$fixture" rev-parse --show-toplevel)
	[[ $(cd "$actual" && pwd -P) == "$fixture" ]] || exit 1
	git -C "$fixture" -c user.name='Routing Test' -c user.email='routing@example.invalid' \
		-c core.hooksPath=/dev/null "$@"
}
fixture_git commit -q --allow-empty -m baseline
# Keep the predicate and output emitter intact; only the network setup is supplied by the fixture.
awk '
  /^      - name: Route the conditional suites$/ {route=1; next}
  route && /^        run: \|$/ {capture=1; next}
  capture {
    if ($0 !~ /^          / && $0 !~ /^$/) exit
    sub(/^          /, "")
    if ($0 !~ /^git fetch --no-tags origin /) print
  }
' "$repository_root/.github/workflows/pr-quality-gate.yml" >"$scratch/route.sh"
[[ -s $scratch/route.sh ]] || exit 1
pass=0
fail=0
route_case() {
	local path=$1 expected=$2 baseline actual
	baseline=$(fixture_git rev-parse HEAD)
	mkdir -p "$fixture/$(dirname "$path")"
	printf 'synthetic\n' >"$fixture/$path"
	fixture_git add -- "$path"
	fixture_git commit -q -m "Change $path"
	fixture_git update-ref FETCH_HEAD "$baseline"
	: >"$scratch/output"
	(cd "$fixture" && GITHUB_OUTPUT="$scratch/output" /bin/bash "$scratch/route.sh")
	actual=$(cat "$scratch/output")
	if [[ $actual == "governed=$expected"$'\nhippo_consumer=false\nrhino_consumer=false' ]]; then
		pass=$((pass + 1))
	else
		printf 'FAIL: %s expected governed=%s; received %s\n' "$path" "$expected" "$actual"
		fail=$((fail + 1))
	fi
}
route_case .commandcode/settings.json true
route_case .commandcode/hooks/run-policy-hook.sh true
route_case .commandcode/agents/swe-developer.md true
route_case .codex/config.toml true
route_case .claude/settings.json true
route_case .opencode/plugins/hook.ts true
route_case apps/web/src/unrelated.ts false
printf 'PR quality routing: %s passed, %s failed\n' "$pass" "$fail"
[[ $fail == 0 ]]
