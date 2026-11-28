#!/usr/bin/env bash
# test-integration-denied.sh — run the bnest-app integration suite with the
# network denied when bubblewrap is available, plainly otherwise.
#
# Under denial the suite runs inside `bwrap --unshare-net` with the host root
# re-bound, so any test that needs real egress fails instead of silently
# reaching the network. When `bwrap` is not on PATH the suite still runs, but
# the run prints NO-DENIAL so the missing denial is never silent.
set -euo pipefail

suite_args=(
  --warnings-as-errors
  --exclude integration-exempt
  --exclude ci-exempt
  --max-cases 1
  test/integration
)

export BNEST_TEST_LAYER=integration
export MIX_ENV=test

if command -v bwrap >/dev/null 2>&1; then
  exec bwrap --unshare-net --bind / / --proc /proc --dev /dev \
    mix do compile --warnings-as-errors + test "${suite_args[@]}" "$@"
else
  printf '%s\n' 'NO-DENIAL: bwrap not found on PATH; running test:integration without network denial'
  exec mix do compile --warnings-as-errors + test "${suite_args[@]}" "$@"
fi
