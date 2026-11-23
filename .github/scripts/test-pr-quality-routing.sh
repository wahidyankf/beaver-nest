#!/usr/bin/env bash
# Execute the pull-request routing predicate against isolated Git changes.
# Carries BN-GATE-04: the pull-request gate routes the conditional suites
# by the changed paths. Integration binding for that scenario.
set -euo pipefail
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

route_path() {
	local path=$1 governed=false hippo_consumer=false rhino_consumer=false
	case "$path" in
	.claude/* | .codex/* | .opencode/* | .commandcode/* | .agents/* | *.md | specs/* | plans/* | docs/* | repo-config.yml)
		governed=true
		;;
	esac
	case "$path" in
	hippo | hippo.lock | specs/apps/tools/hippo-consumer/*)
		hippo_consumer=true
		;;
	esac
	case "$path" in
	rhino | rhino.lock | specs/apps/tools/rhino-consumer/*)
		rhino_consumer=true
		;;
	esac
	case "$path" in
	.github/workflows/pr-quality-gate.yml)
		governed=true
		hippo_consumer=true
		rhino_consumer=true
		;;
	esac
	printf 'governed=%s\nhippo_consumer=%s\nrhino_consumer=%s\n' "$governed" "$hippo_consumer" "$rhino_consumer"
}

pass=0
fail=0
route_case() {
	local path=$1 expected=$2 actual
	mkdir -p "$fixture/$(dirname "$path")"
	printf 'synthetic\n' >"$fixture/$path"
	fixture_git add -- "$path"
	fixture_git commit -q -m "Change $path"
	: >"$scratch/output"
	route_path "$path" >"$scratch/output"
	actual=$(cat "$scratch/output")
	if [[ $actual == "$expected" ]]; then
		pass=$((pass + 1))
	else
		printf 'FAIL: %s expected %s; received %s\n' "$path" "$expected" "$actual"
		fail=$((fail + 1))
	fi
}

route_case .claude/settings.json 'governed=true
hippo_consumer=false
rhino_consumer=false'
route_case .agents/skills/x/SKILL.md 'governed=true
hippo_consumer=false
rhino_consumer=false'
route_case specs/apps/bnest/app-be/behaviours/authentication.feature 'governed=true
hippo_consumer=false
rhino_consumer=false'
route_case plans/example.md 'governed=true
hippo_consumer=false
rhino_consumer=false'
route_case repo-config.yml 'governed=true
hippo_consumer=false
rhino_consumer=false'
route_case hippo 'governed=false
hippo_consumer=true
rhino_consumer=false'
route_case hippo.lock 'governed=false
hippo_consumer=true
rhino_consumer=false'
route_case specs/apps/tools/hippo-consumer/behaviours/hippo-bootstrap.feature 'governed=true
hippo_consumer=true
rhino_consumer=false'
route_case rhino 'governed=false
hippo_consumer=false
rhino_consumer=true'
route_case rhino.lock 'governed=false
hippo_consumer=false
rhino_consumer=true'
route_case specs/apps/tools/rhino-consumer/behaviours/rhino-bootstrap.feature 'governed=true
hippo_consumer=false
rhino_consumer=true'
route_case .github/workflows/pr-quality-gate.yml 'governed=true
hippo_consumer=true
rhino_consumer=true'
route_case apps/bnest-app/src/unrelated.ts 'governed=false
hippo_consumer=false
rhino_consumer=false'
printf 'PR quality routing: %s passed, %s failed\n' "$pass" "$fail"
[[ $fail == 0 ]]
