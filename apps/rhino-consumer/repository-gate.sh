#!/bin/sh
# The six checks this repository's documentation gate runs, against one already
# resolved release.
#
# It exists because the alternative is six `./rhino` invocations, and resolving
# the pinned release is not free: each one takes the shared install guard,
# digests the cached executable, and asks it for its embedded identity in a
# subprocess. Six of those serialize against each other and cost more than the
# checking does. `./rhino --bootstrap-exec` pays it once and names the verified
# executable in `RHINO_BIN`.
#
# This file owns which checks run and in what combination. It owns nothing
# about what any of them mean: the policy is in `repo-config.yml`.
set -u

# Reading this variable is the whole contract with the bootstrap. Running the
# checks without one would mean running an executable nobody verified.
: "${RHINO_BIN:?repository-gate.sh must run under ./rhino --bootstrap-exec}"

"$RHINO_BIN" repo-config validate &
repo_config=$!
"$RHINO_BIN" governance word-budget validate &
word_budget=$!
"$RHINO_BIN" governance directory-map validate &
directory_map=$!
"$RHINO_BIN" harness parity validate &
harness_parity=$!
"$RHINO_BIN" md internal-link validate &
internal_link=$!
"$RHINO_BIN" md mermaid validate &
mermaid=$!

# Every check is waited on, so the gate reports every failing check rather than
# the first one. A single failure fails the gate.
gate_status=0
for check in "$repo_config" "$word_budget" "$directory_map" "$harness_parity" "$internal_link" "$mermaid"; do
	wait "$check" || gate_status=1
done
exit "$gate_status"
