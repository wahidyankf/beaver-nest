#!/usr/bin/env bash
# ==============================================================================
# check.sh — this repository's public-safety gate
# ==============================================================================
# Usage: OSE_GATE_SURFACE=<surface> scripts/public-safety/check.sh [hook args]
#
#   commit-msg   $1 is the file holding the message being written
#   pre-commit   no arguments; the staged tree is the subject
#   pre-push     ref updates arrive on stdin, as Git supplies them
#   ci           no arguments; the checked-out tree is the subject
#
# The surface arrives in the environment and nowhere else. It is never inferred
# from an argument's filename, from which hook happens to be running, or from
# whether a remote is reachable — a gate that guesses its own surface will
# eventually guess a weaker one, and that is precisely the case where guessing
# is expensive.
#
# This file decides *what is outbound* at each surface. `outbound-preflight.sh`
# decides whether any of it is prohibited. Keeping those apart is what lets the
# leaf be tested against synthetic inputs with no repository at all.
#
# Exit codes pass through from the leaf: 0 clean, 1 blocked, 2 scan error.
# ==============================================================================

set -uo pipefail

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(git -C "$here" rev-parse --show-toplevel 2>/dev/null) || {
	printf '[public-safety] blocked scan-error not inside a Git repository\n' >&2
	exit 2
}
leaf="$here/outbound-preflight.sh"
[[ -x "$leaf" ]] || {
	printf '[public-safety] blocked scan-error the leaf wrapper is missing or not executable\n' >&2
	exit 2
}

surface="${OSE_GATE_SURFACE:-}"
case "$surface" in
commit-msg | pre-commit | pre-push | ci) ;;
"")
	printf '[public-safety] blocked scan-error OSE_GATE_SURFACE is unset\n' >&2
	exit 2
	;;
*)
	printf '[public-safety] blocked scan-error OSE_GATE_SURFACE is not a known surface\n' >&2
	exit 2
	;;
esac

cd "$root" || exit 2

# ------------------------------------------------------------------------------
# Input collection. Every helper appends to `args`, an argument vector — never a
# string. A path containing a space or a shell metacharacter is data here, and
# building a command line out of it would make it an instruction.
# ------------------------------------------------------------------------------

declare -a args=()

add_tracked_tree() {
	# Every tracked file, plus every tracked path as text: a name is outbound
	# material too, and a directory named after something private leaks whether
	# or not any file inside it does.
	local f
	while IFS= read -r f; do
		[[ -f "$f" ]] && args+=(--file "$f")
		args+=(--text "$f")
	done < <(git ls-files)
}

add_staged() {
	local f
	while IFS= read -r f; do
		[[ -f "$f" ]] && args+=(--file "$f")
		args+=(--text "$f")
	done < <(git diff --cached --name-only --diff-filter=ACMR)
}

run_leaf() {
	# run_leaf <leaf-surface>; consumes and clears `args`.
	local leaf_surface=$1 rc
	if [[ ${#args[@]} -eq 0 ]]; then
		args=()
		return 0
	fi
	"$leaf" --surface "$leaf_surface" "${args[@]}"
	rc=$?
	args=()
	return $rc
}

current_ref() {
	git symbolic-ref --quiet --short HEAD 2>/dev/null || git rev-parse --short HEAD
}

# ------------------------------------------------------------------------------
# Surfaces
# ------------------------------------------------------------------------------

case "$surface" in
commit-msg)
	[[ $# -ge 1 && -r "$1" ]] || {
		printf '[public-safety] blocked scan-error commit-msg received no readable message file\n' >&2
		exit 2
	}
	args+=(--file "$1" --text "$(current_ref)")
	run_leaf commit || exit $?
	;;

pre-commit)
	# The tracked tree first: a leak that is already committed does not become
	# safe because this particular change did not introduce it.
	add_tracked_tree
	run_leaf baseline || exit $?
	add_staged
	run_leaf diff || exit $?
	;;

pre-push)
	# Git supplies `<local-ref> <local-sha> <remote-ref> <remote-sha>` per line.
	# Deletions carry an all-zero local sha and send nothing outbound.
	local_refs=()
	ranges=()
	while read -r local_ref local_sha remote_ref remote_sha; do
		[[ -z "${local_ref:-}" ]] && continue
		[[ "$local_sha" =~ ^0+$ ]] && continue
		local_refs+=("${local_ref#refs/heads/}" "${remote_ref#refs/heads/}")
		if [[ "$remote_sha" =~ ^0+$ ]]; then
			ranges+=("$local_sha --not --remotes")
		else
			ranges+=("$remote_sha..$local_sha")
		fi
	done

	# Invoked outside a hook, with nothing on stdin: screen what is here now
	# rather than reporting a vacuous pass.
	if [[ ${#local_refs[@]} -eq 0 ]]; then
		local_refs=("$(current_ref)")
		ranges=("HEAD --not --remotes")
	fi

	for r in "${local_refs[@]}"; do
		[[ -n "$r" ]] && args+=(--text "$r")
	done
	run_leaf ref || exit $?

	for range in "${ranges[@]}"; do
		# shellcheck disable=SC2086
		while IFS= read -r sha; do
			[[ -n "$sha" ]] && args+=(--text "$(git log -1 --format=%B "$sha")")
		done < <(git rev-list $range 2>/dev/null)
	done
	run_leaf commit || exit $?

	add_tracked_tree
	run_leaf baseline || exit $?
	;;

ci)
	args+=(--text "$(current_ref)" --text "$(git log -1 --format=%B HEAD)")
	run_leaf ref || exit $?
	add_tracked_tree
	run_leaf baseline || exit $?
	;;
esac

printf '[public-safety] %s: clean\n' "$surface"
exit 0
