#!/bin/sh
# The adapter for specs/tools/hippo-consumer/behaviours/hippo-bootstrap.feature.
#
# Contention is choreographed through gates rather than through timing. A
# fixture that waits a while and then continues turns a race that never happened
# into a test that passes, so every wait here is bounded and every bound fails
# loudly.
set -eu

repository_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
temporary_root=$(mktemp -d)
trap 'rm -rf -- "$temporary_root"' EXIT HUP INT TERM

# The consumer policy example is an exact schema-2 reservation contract. Keep
# its bounded owner count and automatic shares independent from release bytes.
cat >"$temporary_root/expected-config.json" <<'EOF'
{
  "schemaVersion": 2,
  "coordination": {
    "mode": "reservation",
    "maxActiveOwners": 20,
    "automaticOwnerShares": {
      "balanced": 4,
      "constrained": 2,
      "minimal": 1
    }
  },
  "defaultProfile": "local-constrained",
  "profiles": {
    "local-constrained": {
      "extends": "constrained",
      "fallback": "minimal",
      "strict": false,
      "maxCpuUtilizationPercent": 90
    }
  }
}
EOF
cmp "$temporary_root/expected-config.json" "$repository_root/hippo.local.json.example"

# Build a synthetic tagged asset whose identity and digest are deterministic;
# the test never depends on GitHub or the machine's real installation cache.
subject="$temporary_root/consumer/hippo"
mkdir -p "$temporary_root/consumer" "$temporary_root/fake-bin" "$temporary_root/stat-bin" "$temporary_root/payload"
cp "$repository_root/hippo" "$subject"

chmod 755 "$subject"

# The suite runs on both Linux and macOS runners. Pinning the fake uname to one
# platform would send the wrapper down the wrong locking branch — flock on
# Linux, lockf on Darwin — so the real branch for the host is never exercised
# and the other one cannot even resolve its tool. Derive the platform from the
# real host, and let a scenario still override it explicitly.
case "$(uname -s)" in
Darwin) host_goos=darwin ;;
Linux) host_goos=linux ;;
*)
	echo "unsupported host operating system for the bootstrap suite" >&2
	exit 78
	;;
esac
case "$(uname -m)" in
x86_64 | amd64) host_goarch=amd64 ;;
arm64 | aarch64) host_goarch=arm64 ;;
*)
	echo "unsupported host architecture for the bootstrap suite" >&2
	exit 78
	;;
esac
host_platform="$host_goos-$host_goarch"
HIPPO_TEST_HOST_UNAME_S=$(uname -s)
HIPPO_TEST_HOST_UNAME_M=$(uname -m)
export HIPPO_TEST_HOST_UNAME_S HIPPO_TEST_HOST_UNAME_M

# Which dialect the host's own stat speaks, so the timestamp fixture can hand
# back true values while presenting the other platform's interface.
real_stat=$(command -v stat)
if "$real_stat" -c '%Y' "$temporary_root" >/dev/null 2>&1; then
	HIPPO_TEST_HOST_STAT=gnu
else
	HIPPO_TEST_HOST_STAT=bsd
fi
export HIPPO_TEST_HOST_STAT

test_version=v9.8.7
test_commit=0123456789abcdef0123456789abcdef01234567
cat >"$temporary_root/payload/hippo" <<EOF
#!/bin/sh
if [ "\${1:-}" = version ] && [ "\${2:-}" = --json ]; then
  if [ -n "\${HIPPO_TEST_IDENTITY:-}" ]; then
    printf '%s\n' "\$HIPPO_TEST_IDENTITY"
  else
    printf '%s\n' '{"schemaVersion":1,"version":"$test_version","commit":"$test_commit"}'
  fi
elif [ "\${1:-}" = run ]; then
  shift
  if [ -n "\${HIPPO_TEST_ARGUMENTS:-}" ]; then
    : > "\$HIPPO_TEST_ARGUMENTS"
    for argument in "\$@"; do
      printf '%s\n' "\$argument" >> "\$HIPPO_TEST_ARGUMENTS"
    done
  fi
  printf '%s\n' 'run-ok'
else
  # Staying alive inside the release is how a consumer that is *using* a release
  # is represented: the wrapper has already released its install guard by the
  # time this runs, so a peer's retention pass meets a live claim rather than a
  # live installer.
  if [ -n "\${HIPPO_TEST_PAYLOAD_WAIT:-}" ]; then
    payload_attempt=0
    while [ ! -e "\$HIPPO_TEST_PAYLOAD_WAIT" ]; do
      payload_attempt=\$((payload_attempt + 1))
      [ "\$payload_attempt" -lt 400 ] || exit 96
      /bin/sleep 0.05
    done
  fi
  printf '%s\n' 'probe-ok'
fi
EOF
chmod 755 "$temporary_root/payload/hippo"
tar -czf "$temporary_root/release.tar.gz" -C "$temporary_root/payload" hippo

# PATH-local curl and uname fixtures exercise download and platform branches
# while leaving the bootstrap's production checksum path intact.
cat >"$temporary_root/fake-bin/curl" <<'EOF'
#!/bin/sh
set -eu
if [ "${HIPPO_TEST_CURL_FAIL:-}" = 1 ]; then
  exit 99
fi
destination=
requested_url=
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output ]; then
    destination=$2
    shift 2
  else
    requested_url=$1
    shift
  fi
done
# The gate is what makes contention observable without measuring time:
# transport announces that it is in flight and then blocks until the test
# releases it, so a second consumer can be started and inspected while the
# first provably holds the install.
if [ -n "${HIPPO_TEST_CURL_GATE:-}" ]; then
  : > "$HIPPO_TEST_CURL_GATE/in-flight.$$"
  gate_attempt=0
  while [ ! -e "$HIPPO_TEST_CURL_GATE/release" ]; do
    gate_attempt=$((gate_attempt + 1))
    [ "$gate_attempt" -lt 400 ] || exit 96
    /bin/sleep 0.05
  done
fi
cp "$HIPPO_TEST_ARCHIVE" "$destination"
if [ -n "${HIPPO_TEST_CURL_DELAY:-}" ]; then
  sleep "$HIPPO_TEST_CURL_DELAY"
fi
printf '%s\n' "$requested_url" >> "$HIPPO_TEST_CURL_COUNT"
EOF
chmod 755 "$temporary_root/fake-bin/curl"

cat >"$temporary_root/fake-bin/uname" <<'EOF'
#!/bin/sh
case "$1" in
  -s) printf '%s\n' "${HIPPO_TEST_UNAME_S:-$HIPPO_TEST_HOST_UNAME_S}" ;;
  -m) printf '%s\n' "${HIPPO_TEST_UNAME_M:-$HIPPO_TEST_HOST_UNAME_M}" ;;
  *) exit 2 ;;
esac
EOF
chmod 755 "$temporary_root/fake-bin/uname"

cat >"$temporary_root/fake-bin/sleep" <<'EOF'
#!/bin/sh
if [ "${HIPPO_TEST_SLEEP_FAIL:-}" = 1 ]; then
  exit 97
fi
exec /bin/sleep "$@"
EOF
chmod 755 "$temporary_root/fake-bin/sleep"

# A stat that presents one platform's interface on either host. In `gnu` mode
# the BSD `-f` form means "filesystem status": a block of filesystem prose on
# standard output, then a failure on the format operand -- which is exactly the
# shape that makes a `stat -f ... || stat -c ...` fallback chain rank releases
# by prose instead of by time. In `bsd` mode the GNU `-c` form is simply not a
# thing. Values that are returned are the host's real ones.
cat >"$temporary_root/stat-bin/stat" <<EOF
#!/bin/sh
form=\$1
requested_format=\$2
subject_path=\$3
case "\${HIPPO_TEST_STAT_EMULATE:-}:\$form" in
gnu:-f)
  printf '  File: "%s"\n  ID: 0 Namelen: 255 Type: apfs\n' "\$subject_path"
  exit 1
  ;;
bsd:-c)
  echo "stat: illegal option -- c" >&2
  exit 1
  ;;
esac
case "\$requested_format" in
'%m' | '%Y') bsd_format='%m'; gnu_format='%Y' ;;
*) bsd_format=\$requested_format; gnu_format=\$requested_format ;;
esac
if [ "\$HIPPO_TEST_HOST_STAT" = gnu ]; then
  exec "$real_stat" -c "\$gnu_format" "\$subject_path"
else
  exec "$real_stat" -f "\$bsd_format" "\$subject_path"
fi
EOF
chmod 755 "$temporary_root/stat-bin/stat"

# Simulating the other platform's timestamp interface also selects that
# platform's file-locking tool, which the host may not have. Only one consumer
# runs in that scenario, so the guard has nothing to serialize; it is stubbed
# there and tested for real by every contention scenario on the host's own
# branch.
for stubbed_lock in flock lockf; do
	cat >"$temporary_root/stat-bin/$stubbed_lock" <<'EOF'
#!/bin/sh
exit 0
EOF
	chmod 755 "$temporary_root/stat-bin/$stubbed_lock"
done

if command -v sha256sum >/dev/null 2>&1; then
	checksum=$(sha256sum "$temporary_root/release.tar.gz" | awk '{print $1}')
else
	checksum=$(shasum -a 256 "$temporary_root/release.tar.gz" | awk '{print $1}')
fi
hash_stream() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum | awk '{print $1}'
	else
		shasum -a 256 | awk '{print $1}'
	fi
}
write_lock() {
	lock_version=$1
	lock_checksum=$2
	cat >"$temporary_root/consumer/hippo.lock" <<EOF
version=$lock_version
commit=$test_commit
darwin-amd64=$lock_checksum
darwin-arm64=$lock_checksum
linux-amd64=$lock_checksum
linux-arm64=$lock_checksum
EOF
}

write_lock "$test_version" "$checksum"

test_path="$temporary_root/fake-bin:$PATH"
cache_root="$temporary_root/cache"
curl_count="$temporary_root/curl-count"

# Every wait in this suite is bounded and every bound is fatal. A choreography
# that silently gives up is the one failure mode a contention fixture cannot
# report on itself: it degrades into two sequential runs that pass.
wait_for() {
	wait_description=$1
	shift
	wait_attempt=0
	until "$@"; do
		wait_attempt=$((wait_attempt + 1))
		if [ "$wait_attempt" -ge 200 ]; then
			echo "timed out waiting for $wait_description" >&2
			exit 1
		fi
		/bin/sleep 0.05
	done
}

transport_in_flight() {
	[ -n "$(find "$1" -maxdepth 1 -name 'in-flight.*' -print -quit 2>/dev/null)" ]
}

claim_exists_for() {
	[ -n "$(find "$1" -maxdepth 1 -name ".release-claim.$2.*" -print -quit 2>/dev/null)" ]
}

# Prove the append-only fixture itself distinguishes duplicate downloads. A
# broken install lock must not be able to collapse two concurrent fetches into
# one observed count through read/modify/write races.
counter_probe="$temporary_root/counter-probe"
HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$counter_probe" HIPPO_TEST_CURL_DELAY=1 \
	"$temporary_root/fake-bin/curl" --output "$temporary_root/probe-one.tar.gz" unused &
counter_probe_one=$!
HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$counter_probe" HIPPO_TEST_CURL_DELAY=1 \
	"$temporary_root/fake-bin/curl" --output "$temporary_root/probe-two.tar.gz" unused &
counter_probe_two=$!
wait "$counter_probe_one"
wait "$counter_probe_two"
[ "$(awk 'END { print NR }' "$counter_probe")" -eq 2 ]
rm -f -- "$counter_probe" "$temporary_root/probe-one.tar.gz" "$temporary_root/probe-two.tar.gz"

# This adapter binds the canonical tool corpus by exact scenario title. The
# exact-list comparison makes a missing, duplicate, renamed, or unknown
# scenario fail before any fixture runs.
feature_file="$repository_root/specs/tools/hippo-consumer/behaviours/hippo-bootstrap.feature"
expected_scenarios='A cold cache installs once and a warm cache needs no transport
Repository worker settings precede the caller'"'"'s run arguments
Tampered warm-cache payload never executes
A downloaded archive whose digest misses the pin never executes
Non-exact stable release version is rejected
Release identity envelope must match exactly
Unsupported platform is refused before any transport
Matching live install-lock owner remains protected
Malformed identity for a live install-lock owner fails closed
Reused live PID with a different valid identity is reclaimed
Dead install-lock owner is reclaimed
Crash before install-lock metadata publication is recoverable
Concurrent cold callers install from exactly one verified download
Concurrent stale reclaimers preserve a replacement live owner
A consumer never removes an install lock it did not publish
Install guard storage stays bounded across release versions
Retention never deletes a release another consumer is using
Retention never evicts a release another repository still uses
Release ranking reads real timestamps on every supported platform
Retention reclaims releases left idle beyond its window
Concurrent owners survive a retryable coordination deferral'
actual_scenarios=$(awk '/^[[:space:]]*Scenario: / { sub(/^[[:space:]]*Scenario: /, ""); print }' "$feature_file")
[ "$actual_scenarios" = "$expected_scenarios" ]

prepare_legacy_install_lock() {
	write_lock "$test_version" "$checksum"
	rm -rf -- "$cache_root"
	install_lock="$cache_root/$test_version/$host_platform.lock"
	mkdir -p "$install_lock"
}

prepare_atomic_install_lock() {
	write_lock "$test_version" "$checksum"
	rm -rf -- "$cache_root"
	install_lock="$cache_root/$test_version/$host_platform.lock"
	mkdir -p "$(dirname -- "$install_lock")"
}

download_count() {
	if [ -f "$curl_count" ]; then
		awk 'END { print NR }' "$curl_count"
	else
		printf '%s\n' 0
	fi
}

assert_pinned_release_installed() {
	downloads_before=$1
	[ "$result" = probe-ok ]
	[ "$(download_count)" -eq "$((downloads_before + 1))" ]
	[ -x "$cache_root/$test_version/$host_platform/hippo" ]
	[ -f "$cache_root/$test_version/$host_platform/hippo.sha256" ]
	[ ! -e "$install_lock" ]
}

assert_waits_for_live_lock() {
	set +e
	PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_SLEEP_FAIL=1 "$subject" probe >/dev/null 2>&1
	status=$?
	set -e
	[ "$status" -eq 97 ]
	[ -f "$install_lock" ]
}

run_cold_then_warm_cache() {
	write_lock "$test_version" "$checksum"
	rm -rf -- "$cache_root"
	downloads_before=$(download_count)
	result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" "$subject" probe)
	[ "$result" = probe-ok ]
	[ "$(download_count)" -eq "$((downloads_before + 1))" ]

	# Transport is not merely unused on the second run, it is broken. A warm
	# cache that quietly re-fetched would fail here rather than pass quietly.
	result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_CURL_FAIL=1 "$subject" probe)
	[ "$result" = probe-ok ]
	[ "$(download_count)" -eq "$((downloads_before + 1))" ]
	[ -f "$cache_root/$test_version/$host_platform/hippo.sha256" ]
}

# Repository-specific worker mappings belong in this consumer wrapper, so their
# presence and their position are both claims about it: every mapping must
# arrive ahead of the caller's own arguments, and the caller's order must be
# untouched.
run_worker_settings_precede_run_arguments() {
	write_lock "$test_version" "$checksum"
	rm -rf -- "$cache_root"
	result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" "$subject" probe)
	[ "$result" = probe-ok ]

	arguments_file="$temporary_root/run-arguments"
	result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_CURL_FAIL=1 HIPPO_TEST_ARGUMENTS="$arguments_file" "$subject" run --class ephemeral -- printf '%s\n' ok)
	[ "$result" = run-ok ]
	expected_arguments='--concurrency-env
NX_PARALLEL
--concurrency-env
GOMAXPROCS
--concurrency-env
DOTNET_PROCESSOR_COUNT
--class
ephemeral
--
printf
%s\n
ok'
	[ "$(sed -n '1,$p' "$arguments_file")" = "$expected_arguments" ]
}

# Integrity failures are configuration errors, not transport errors, and must
# stop before an unverified payload is published or executed.
run_download_digest_mismatch() {
	rm -rf -- "$cache_root"
	write_lock "$test_version" 0000000000000000000000000000000000000000000000000000000000000000
	downloads_before=$(download_count)
	mismatch_output="$temporary_root/digest-mismatch-output"
	set +e
	PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
		"$subject" probe >"$mismatch_output" 2>/dev/null
	status=$?
	set -e
	[ "$status" -eq 78 ]
	# The archive was fetched and then refused: nothing of it reached the cache
	# and the payload never spoke.
	[ "$(download_count)" -eq "$((downloads_before + 1))" ]
	[ ! -s "$mismatch_output" ]
	[ ! -e "$cache_root/$test_version/$host_platform/hippo" ]
	write_lock "$test_version" "$checksum"
}

# A host outside the published matrix has no asset to fetch, so the refusal has
# to come before the transport rather than from a download that fails to find
# one: a 404 read as a network problem is the kind of error a caller retries
# forever. The refusal is attributed by its message, because exit 78 is also
# what an unreadable lock produces -- and the platform branch runs before the
# lock's per-platform checksum is ever read.
run_unsupported_platform_refused() {
	write_lock "$test_version" "$checksum"
	rm -rf -- "$cache_root"
	downloads_before=$(download_count)
	refusal="$temporary_root/platform-refusal"

	set +e
	PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_UNAME_S=Plan9 "$subject" probe >/dev/null 2>"$refusal"
	status=$?
	set -e
	[ "$status" -eq 78 ]
	grep -q 'does not support this operating system' "$refusal"

	set +e
	PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_UNAME_M=riscv64 "$subject" probe >/dev/null 2>"$refusal"
	status=$?
	set -e
	[ "$status" -eq 78 ]
	grep -q 'does not support this architecture' "$refusal"

	[ "$(download_count)" -eq "$downloads_before" ]
	[ ! -e "$cache_root" ]
}

# Two ordinary cold callers contend through the atomically published owner
# record. The second starts only once the first is provably inside transport,
# so this is contention rather than two runs that happened to overlap, and
# exact-owner cleanup must leave neither the lock nor a prepared record behind.
run_concurrent_cold_callers() {
	write_lock "$test_version" "$checksum"
	rm -rf -- "$cache_root"
	gate="$temporary_root/cold-gate"
	rm -rf -- "$gate"
	mkdir -p "$gate"
	downloads_before=$(download_count)
	first_result="$temporary_root/concurrent-first"
	second_result="$temporary_root/concurrent-second"
	PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_CURL_GATE="$gate" "$subject" probe >"$first_result" &
	first_pid=$!
	wait_for "the first cold caller to reach transport" transport_in_flight "$gate"
	PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_CURL_GATE="$gate" "$subject" probe >"$second_result" &
	second_pid=$!
	wait_for "the second cold caller to start" claim_exists_for "$cache_root/$test_version" "$second_pid"
	: >"$gate/release"
	wait "$first_pid"
	wait "$second_pid"
	[ "$(sed -n '1p' "$first_result")" = probe-ok ]
	[ "$(sed -n '1p' "$second_result")" = probe-ok ]
	[ "$(download_count)" -eq "$((downloads_before + 1))" ]
	[ ! -e "$cache_root/$test_version/$host_platform.lock" ]
	[ -z "$(find "$cache_root/$test_version" -name '.install-owner.*' -print -quit)" ]
}

run_tampered_warm_cache() {
	write_lock "$test_version" "$checksum"
	rm -rf -- "$cache_root"
	tamper_marker="$temporary_root/tampered-executed"
	rm -f -- "$tamper_marker"
	result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" "$subject" probe)
	[ "$result" = probe-ok ]
	cached_binary="$cache_root/$test_version/$host_platform/hippo"

	# A digest mismatch must be rejected before the replacement executes.
	cat >"$cached_binary" <<EOF
#!/bin/sh
: > "$tamper_marker"
exit 0
EOF
	chmod 755 "$cached_binary"
	set +e
	PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_CURL_FAIL=1 "$subject" probe >/dev/null 2>&1
	status=$?
	set -e
	[ "$status" -eq 99 ]
	[ ! -e "$tamper_marker" ]

	# A matching sidecar digest cannot bypass the embedded release identity.
	rm -rf -- "$cache_root"
	result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" "$subject" probe)
	[ "$result" = probe-ok ]
	cat >"$cached_binary" <<EOF
#!/bin/sh
if [ "\${1:-}" = version ] && [ "\${2:-}" = --json ]; then
  printf '%s\n' '{"schemaVersion":1,"version":"v0.0.0","commit":"$test_commit"}'
else
  : > "$tamper_marker"
fi
EOF
	chmod 755 "$cached_binary"
	hash_stream <"$cached_binary" >"$cached_binary.sha256"
	set +e
	PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_CURL_FAIL=1 "$subject" probe >/dev/null 2>&1
	status=$?
	set -e
	[ "$status" -eq 99 ]
	[ ! -e "$tamper_marker" ]
}

run_non_exact_stable_version() {
	rm -rf -- "$cache_root"
	downloads_before=$(download_count)
	# `v1.2.3/../../../escape` resolves three levels above the cache root, which
	# is one level above the suite's own temporary root -- so that, and not a
	# path inside the sandbox, is where a traversal would land.
	escape_parent=$(dirname -- "$temporary_root")
	for invalid_version in v1x.2.3 v1.2.3-rc1 'v1.2.3/../../../escape'; do
		write_lock "$invalid_version" "$checksum"
		set +e
		PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" "$subject" probe >/dev/null 2>&1
		status=$?
		set -e
		[ "$status" -eq 78 ]
	done
	[ "$(download_count)" -eq "$downloads_before" ]
	[ ! -e "$escape_parent/escape" ]
	[ ! -e "$temporary_root/escape" ]
	[ ! -e "$cache_root" ]
	write_lock "$test_version" "$checksum"
}

run_non_exact_identity_envelope() {
	write_lock "$test_version" "$checksum"
	rm -rf -- "$cache_root"
	downloads_before=$(download_count)
	set +e
	PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_IDENTITY="{\"schemaVersion\":1,\"version\":\"$test_version\",\"commit\":\"$test_commit\",\"version\":\"v0.0.0\"}" \
		"$subject" probe >/dev/null 2>&1
	status=$?
	set -e
	[ "$status" -eq 78 ]
	[ "$(download_count)" -eq "$((downloads_before + 1))" ]
	[ ! -e "$cache_root/$test_version/$host_platform/hippo" ]
	[ ! -e "$cache_root/$test_version/$host_platform/hippo.sha256" ]
}

run_matching_live_owner() {
	prepare_atomic_install_lock
	process_start=$(LC_ALL=C ps -o lstart= -p "$$" 2>/dev/null | awk '{$1=$1; print; exit}')
	process_digest=$(printf '%s\n' "$process_start" | hash_stream)
	printf '%s\n%s\n' "$$" "$process_digest" >"$install_lock"
	assert_waits_for_live_lock
}

run_malformed_live_owner() {
	# Every case here is digest-consistent, so each one reaches the identity
	# check rather than being turned away by the record digest before it. The
	# shapes are the three ways a digest can be wrong while looking right: not
	# hexadecimal at all, the right alphabet at the wrong length, and the right
	# length in the wrong case.
	for malformed_identity in 'malformed-process-identity' "$(printf '%063d' 0)" "$(printf '%063d' 0)F"; do
		prepare_atomic_install_lock
		printf '%s\n%s\n' "$$" "$malformed_identity" >"$install_lock"
		assert_waits_for_live_lock
	done

	# A record carrying an extra field is stopped one gate earlier, by the record
	# digest that covers exactly the PID and identity lines. Kept because that
	# gate is what makes the identity check above meaningful.
	prepare_atomic_install_lock
	printf '%s\n%064d\n%s' "$$" 0 'unexpected-field' >"$install_lock"
	assert_waits_for_live_lock
}

run_reused_live_pid() {
	prepare_atomic_install_lock
	printf '%s\n%064d\n' "$$" 0 >"$install_lock"
	downloads_before=$(download_count)
	result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_SLEEP_FAIL=1 "$subject" probe)
	assert_pinned_release_installed "$downloads_before"
}

run_dead_owner() {
	prepare_atomic_install_lock
	dead_pid=2147483647
	if kill -0 "$dead_pid" 2>/dev/null; then
		exit 1
	fi
	printf '%s\n%s\n' "$dead_pid" 'legacy-process-identity' >"$install_lock"
	downloads_before=$(download_count)
	result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_SLEEP_FAIL=1 "$subject" probe)
	assert_pinned_release_installed "$downloads_before"
}

run_crash_before_publication() {
	dead_pid=2147483647
	if kill -0 "$dead_pid" 2>/dev/null; then
		exit 1
	fi
	prepare_legacy_install_lock
	downloads_before=$(download_count)
	set +e
	result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_SLEEP_FAIL=1 "$subject" probe)
	status=$?
	set -e
	[ "$status" -eq 0 ]
	assert_pinned_release_installed "$downloads_before"

	# A legacy owner that published only its now-dead PID is also recoverable.
	prepare_legacy_install_lock
	printf '%s\n' "$dead_pid" >"$install_lock/pid"
	downloads_before=$(download_count)
	result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_SLEEP_FAIL=1 "$subject" probe)
	assert_pinned_release_installed "$downloads_before"

	# Orphan preparation cleanup requires both conservative expiry and positive
	# owner staleness. Fresh dead-owner and expired matching-live records stay.
	# Sleep still fails: recovery here is immediate, never a wait that outlasts
	# the obstruction.
	write_lock "$test_version" "$checksum"
	rm -rf -- "$cache_root"
	preparation_dir="$cache_root/$test_version"
	mkdir -p "$preparation_dir"
	orphan_identity=$(printf '%064d' 0)
	process_start=$(LC_ALL=C ps -o lstart= -p "$$" 2>/dev/null | awk '{$1=$1; print; exit}')
	live_identity=$(printf '%s\n' "$process_start" | hash_stream)
	expired_orphan="$preparation_dir/.install-owner.$dead_pid.$orphan_identity.expired"
	fresh_orphan="$preparation_dir/.install-owner.$dead_pid.$orphan_identity.fresh"
	live_preparation="$preparation_dir/.install-owner.$$.$live_identity.live"
	: >"$expired_orphan"
	: >"$fresh_orphan"
	: >"$live_preparation"
	touch -t 200001010000 "$expired_orphan" "$live_preparation"
	downloads_before=$(download_count)
	result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_SLEEP_FAIL=1 "$subject" probe)
	assert_pinned_release_installed "$downloads_before"
	[ ! -e "$expired_orphan" ]
	[ -f "$fresh_orphan" ]
	[ -f "$live_preparation" ]
	rm -f -- "$fresh_orphan" "$live_preparation"
}

# The hazard is a second consumer arriving after a stale record has been
# reclaimed and destroying the live ownership that replaced it. Reproducing it
# needs the second consumer to be running while the first holds the release, so
# the first is held inside transport and the second is started and confirmed to
# have begun -- it publishes its release claim before it contends for anything
# -- before the replacement record is inspected.
run_concurrent_stale_reclaimers() {
	prepare_atomic_install_lock
	dead_pid=2147483647
	if kill -0 "$dead_pid" 2>/dev/null; then
		exit 1
	fi
	printf '%s\n%064d\n' "$dead_pid" 0 >"$install_lock"
	gate="$temporary_root/reclaim-gate"
	rm -rf -- "$gate"
	mkdir -p "$gate"
	downloads_before=$(download_count)
	first_result="$temporary_root/reclaimer-first"
	second_result="$temporary_root/reclaimer-second"

	PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_CURL_GATE="$gate" "$subject" probe >"$first_result" &
	first_pid=$!
	wait_for "the reclaiming consumer to reach transport" transport_in_flight "$gate"

	# The stale record is gone and the replacement names the consumer that is
	# installing right now.
	[ -f "$install_lock" ]
	[ "$(sed -n '1p' "$install_lock")" = "$first_pid" ]

	PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_CURL_GATE="$gate" "$subject" probe >"$second_result" &
	second_pid=$!
	wait_for "the second contender to start" claim_exists_for "$cache_root/$test_version" "$second_pid"

	# With both consumers running, the replacement is still owned by the first.
	[ -f "$install_lock" ]
	[ "$(sed -n '1p' "$install_lock")" = "$first_pid" ]

	: >"$gate/release"
	set +e
	wait "$first_pid"
	first_status=$?
	wait "$second_pid"
	second_status=$?
	set -e
	[ "$first_status" -eq 0 ]
	[ "$second_status" -eq 0 ]
	[ "$(sed -n '1p' "$first_result")" = probe-ok ]
	[ "$(sed -n '1p' "$second_result")" = probe-ok ]
	[ "$(download_count)" -eq "$((downloads_before + 1))" ]
	[ ! -e "$install_lock" ]
	[ -z "$(find "$cache_root/$test_version" -name '.install-owner.*' -print -quit)" ]
}

# A peer consumer is a second checkout of this same wrapper with its own lock.
# Every repository on a machine resolves to one cache root, so peers exercise
# the cross-repository behaviour that a single subject cannot.
install_peer_consumer() {
	peer_name=$1
	peer_version=$2
	peer_dir="$temporary_root/peers/$peer_name"
	mkdir -p "$peer_dir"
	cp "$repository_root/hippo" "$peer_dir/hippo"
	chmod 755 "$peer_dir/hippo"
	cat >"$peer_dir/hippo.lock" <<PEERLOCK
version=$peer_version
commit=$test_commit
darwin-amd64=$checksum
darwin-arm64=$checksum
linux-amd64=$checksum
linux-arm64=$checksum
PEERLOCK
}

run_peer_consumer() {
	peer_name=$1
	peer_version=$2
	peer_delay=$3
	PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" \
		HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" \
		HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_CURL_DELAY="$peer_delay" \
		HIPPO_TEST_IDENTITY="{\"schemaVersion\":1,\"version\":\"$peer_version\",\"commit\":\"$test_commit\"}" \
		"$temporary_root/peers/$peer_name/hippo" probe
}

run_retention_protects_installing_release() {
	rm -rf -- "$cache_root" "$curl_count"
	claimed_version=v9.7.2
	pinned_version=v9.7.1
	install_peer_consumer holding "$claimed_version"
	install_peer_consumer pruning "$pinned_version"

	# The claim is published by a real consumer and read by a real peer, so the
	# producer and the reader of that record are both the product. A claim
	# written by the test would prove only that the reader parses the test's
	# spelling. The holder stays inside its release rather than exiting, which is
	# what a claim exists for: the wrapper releases its install guard before
	# executing the release, so a peer's retention pass genuinely runs alongside.
	holder_gate="$temporary_root/holder-gate"
	rm -rf -- "$holder_gate"
	mkdir -p "$holder_gate"
	holder_output="$temporary_root/holder-output"
	PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" \
		HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" \
		HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_PAYLOAD_WAIT="$holder_gate/finish" \
		HIPPO_TEST_IDENTITY="{\"schemaVersion\":1,\"version\":\"$claimed_version\",\"commit\":\"$test_commit\"}" \
		"$temporary_root/peers/holding/hippo" probe >"$holder_output" &
	holder_pid=$!
	wait_for "the holding consumer to publish its release claim" \
		claim_exists_for "$cache_root/$claimed_version" "$holder_pid"
	wait_for "the holding consumer to enter its release" \
		test -x "$cache_root/$claimed_version/$host_platform/hippo"

	sentinel="$cache_root/$claimed_version/.survives-retention"
	: >"$sentinel"
	# Oldest of all candidates, and outside the ranked budget, so only the claim
	# can save it.
	touch -t 200001010000 "$cache_root/$claimed_version"
	for bystander in v9.6.1 v9.6.2 v9.6.3; do
		mkdir -p "$cache_root/$bystander"
		touch -t 200002010000 "$cache_root/$bystander"
	done

	[ "$(run_peer_consumer pruning "$pinned_version" 0)" = probe-ok ]

	[ -f "$sentinel" ]
	[ -x "$cache_root/$claimed_version/$host_platform/hippo" ]
	[ -x "$cache_root/$pinned_version/$host_platform/hippo" ]
	# Retention still ran: the ranked budget reclaimed exactly one unclaimed
	# idle peer, so the claim is an exemption rather than a disabled prune.
	surviving_bystanders=0
	for bystander in v9.6.1 v9.6.2 v9.6.3; do
		if [ -d "$cache_root/$bystander" ]; then
			surviving_bystanders=$((surviving_bystanders + 1))
		fi
	done
	[ "$surviving_bystanders" -eq 2 ]

	: >"$holder_gate/finish"
	wait "$holder_pid"
	[ "$(sed -n '1p' "$holder_output")" = probe-ok ]
	write_lock "$test_version" "$checksum"
	rm -rf -- "$cache_root" "$curl_count"
}

run_retention_keeps_releases_other_repositories_use() {
	rm -rf -- "$cache_root" "$curl_count"
	sharing_versions='v9.5.1 v9.5.2 v9.5.3 v9.5.4'
	for sharing_version in $sharing_versions; do
		install_peer_consumer "repo$sharing_version" "$sharing_version"
		[ "$(run_peer_consumer "repo$sharing_version" "$sharing_version" 0)" = probe-ok ]
	done
	# One download per distinct pin, and every pin survives every peer's prune.
	[ "$(download_count)" -eq 4 ]
	for sharing_version in $sharing_versions; do
		[ -x "$cache_root/$sharing_version/$host_platform/hippo" ]
	done

	# A second pass must serve every repository warm. Under a ranked-only
	# budget the fourth pin has already been evicted and downloads again.
	for sharing_version in $sharing_versions; do
		[ "$(run_peer_consumer "repo$sharing_version" "$sharing_version" 0)" = probe-ok ]
	done
	[ "$(download_count)" -eq 4 ]
	write_lock "$test_version" "$checksum"
	rm -rf -- "$cache_root" "$curl_count"
}

run_retention_reclaims_idle_releases() {
	rm -rf -- "$cache_root" "$curl_count"
	idle_version=v9.4.9
	install_peer_consumer idle "$idle_version"
	# Distinct far-past timestamps make the recency ordering deterministic.
	idle_stamp=1
	for idle_release in v8.0.1 v8.0.2 v8.0.3 v8.0.4 v8.0.5; do
		mkdir -p "$cache_root/$idle_release"
		touch -t "20000${idle_stamp}010000" "$cache_root/$idle_release"
		idle_stamp=$((idle_stamp + 1))
	done
	[ "$(run_peer_consumer idle "$idle_version" 0)" = probe-ok ]

	# Retention still reclaims genuinely idle releases: only the pinned release
	# and the two most recent idle fallbacks survive.
	[ -x "$cache_root/$idle_version/$host_platform/hippo" ]
	[ -d "$cache_root/v8.0.5" ]
	[ -d "$cache_root/v8.0.4" ]
	[ ! -d "$cache_root/v8.0.3" ]
	[ ! -d "$cache_root/v8.0.2" ]
	[ ! -d "$cache_root/v8.0.1" ]
	write_lock "$test_version" "$checksum"
	rm -rf -- "$cache_root" "$curl_count"
}

# `release_install_lock` removes the lock only while its inode identity and
# record digest are *both* still the ones this process published. A consumer
# whose lock a peer had already reclaimed would otherwise delete the peer's
# replacement on the way out, admitting a third installer into an install that
# is already owned. The branch is reached by every successful install, but only
# ever with a match; the arm that must refuse is reached by nothing else, so the
# record is substituted here while the consumer is provably still inside
# transport and what it does on the way out is observed.
#
# Three substitutions, because the two halves of the comparison are load-bearing
# separately: a different file with a different owner fails both, a rewrite in
# place keeps the inode and breaks only the digest, and a byte-identical copy
# keeps the digest and breaks only the inode. Dropping either conjunct survives
# the other two.
run_never_removes_a_foreign_install_lock() {
	for substitution in foreign-owner rewritten-in-place identical-copy; do
		prepare_atomic_install_lock
		gate="$temporary_root/foreign-lock-gate"
		rm -rf -- "$gate"
		mkdir -p "$gate"
		installer_result="$temporary_root/foreign-lock-installer"
		PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
			HIPPO_TEST_CURL_GATE="$gate" "$subject" probe >"$installer_result" &
		installer_pid=$!
		wait_for "the installing consumer to reach transport" transport_in_flight "$gate"
		[ "$(sed -n '1p' "$install_lock")" = "$installer_pid" ]

		replacement="$temporary_root/replacement-owner"
		rm -f -- "$replacement"
		case "$substitution" in
		foreign-owner)
			# A peer that reclaimed the lock and published its own record: a
			# different file, a different owner, and this owner is alive.
			process_start=$(LC_ALL=C ps -o lstart= -p "$$" 2>/dev/null | awk '{$1=$1; print; exit}')
			process_digest=$(printf '%s\n' "$process_start" | hash_stream)
			printf '%s\n%s\n' "$$" "$process_digest" >"$replacement"
			rm -f -- "$install_lock"
			ln "$replacement" "$install_lock"
			expected_owner=$$
			;;
		rewritten-in-place)
			# Same inode, different bytes. Only the record digest can notice.
			printf '%s\n%064d\n' "$installer_pid" 1 >"$install_lock"
			expected_owner=$installer_pid
			;;
		*)
			# Same bytes, different inode. Only the file identity can notice.
			cat "$install_lock" >"$replacement"
			rm -f -- "$install_lock"
			ln "$replacement" "$install_lock"
			expected_owner=$installer_pid
			;;
		esac

		: >"$gate/release"
		wait "$installer_pid"
		[ "$(sed -n '1p' "$installer_result")" = probe-ok ]
		# The substituted record is untouched and still names its own owner.
		[ -f "$install_lock" ]
		[ "$(sed -n '1p' "$install_lock")" = "$expected_owner" ]
		rm -f -- "$install_lock" "$replacement"
	done
}

run_bounded_install_guard_storage() {
	rm -rf -- "$cache_root"
	for release_version in v9.8.7 v9.8.8 v9.8.9 v9.8.10; do
		write_lock "$release_version" "$checksum"
		release_identity="{\"schemaVersion\":1,\"version\":\"$release_version\",\"commit\":\"$test_commit\"}"
		result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
			HIPPO_TEST_IDENTITY="$release_identity" "$subject" probe)
		[ "$result" = probe-ok ]
	done
	# Retention has to have something to prune, or the scenario's When never
	# happens and the guard count is only ever observed on a cache nothing
	# reclaimed. Three of the four pins are aged past the idle window, so the
	# ranked budget keeps two and reclaims the oldest on the next real install.
	idle_stamp=1
	for aged_release in v9.8.7 v9.8.8 v9.8.9; do
		touch -t "20000${idle_stamp}010000" "$cache_root/$aged_release"
		idle_stamp=$((idle_stamp + 1))
	done
	write_lock v9.8.11 "$checksum"
	result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_IDENTITY="{\"schemaVersion\":1,\"version\":\"v9.8.11\",\"commit\":\"$test_commit\"}" "$subject" probe)
	[ "$result" = probe-ok ]
	[ ! -d "$cache_root/v9.8.7" ]
	[ -d "$cache_root/v9.8.8" ]
	[ -d "$cache_root/v9.8.9" ]
	[ -d "$cache_root/v9.8.10" ]
	[ -d "$cache_root/v9.8.11" ]

	guard_count=0
	for guard_path in "$cache_root"/.install-guard.* "$cache_root"/.install-guards/*; do
		if [ -f "$guard_path" ] && [ ! -L "$guard_path" ]; then
			guard_count=$((guard_count + 1))
		fi
	done
	[ "$guard_count" -eq 1 ]
	write_lock "$test_version" "$checksum"
	rm -rf -- "$cache_root"
}

run_concurrent_owners_survive_retryable_deferral() {
	workflow="$repository_root/.github/workflows/hippo-consumer-smoke.yml"
	# Exit 75 is HIPPO's documented retryable deferral, and an owner can receive it
	# after its child is already running: activation records the supervised process
	# group once the child exists, and HIPPO stops a child whose process group it
	# could not record rather than leave behind an owner critical pressure cannot
	# shed. An owner that received 75 therefore holds no reservation, so a proof that
	# reads the deferral as an admission fails on whichever platform loses the
	# shared-root race. That is how this reached main and then failed only on Linux.
	if ! grep -qE '(-ne|-eq) 75 \]' "$workflow"; then
		echo "the shared-root proof must retry an owner that exits with the retryable 75" >&2
		return 1
	fi
	# Every guarded owner must reach the background through that retry rather than
	# being launched straight into it, or the retry protects nothing.
	if [ "$(grep -cE '^[[:space:]]*\./hippo run .*&$' "$workflow")" -ne 0 ]; then
		echo "a guarded owner reaches the background without the deferral retry" >&2
		return 1
	fi
	if [ "$(grep -cE '^[[:space:]]*launch_owner [a-z]+ &$' "$workflow")" -ne 2 ]; then
		echo "the proof must launch exactly two owners through the deferral retry" >&2
		return 1
	fi
}

# The BSD form `stat -f` means "filesystem status" to GNU coreutils, which writes
# a block of filesystem detail to stdout before failing on the format operand, so
# a `stat -f ... || stat -c ...` fallback chain captures that detail alongside the
# real value and retention then ranks releases by prose instead of by time. The
# fault is invisible on macOS, where the BSD form simply succeeds.
#
# So the platform is simulated rather than assumed: retention runs twice, once
# against a stat presenting the BSD interface and once against one presenting
# the GNU interface, on whichever host this is. Both must reclaim exactly the
# same set. A fallback chain, a call site that skipped the platform branch, or a
# read spelled in a command substitution all make one of the two runs read a
# timestamp it cannot parse, and an unreadable timestamp is never ranked -- so
# the idle releases that should have been reclaimed survive, and the run fails.
run_release_ranking_reads_real_timestamps() {
	for simulated_stat in bsd gnu; do
		case "$simulated_stat" in
		bsd)
			simulated_uname=Darwin
			simulated_goos=darwin
			;;
		*)
			simulated_uname=Linux
			simulated_goos=linux
			;;
		esac
		simulated_platform="$simulated_goos-$host_goarch"
		ranking_version=v9.3.9
		rm -rf -- "$cache_root" "$curl_count"
		install_peer_consumer "ranking-$simulated_stat" "$ranking_version"
		idle_stamp=1
		for idle_release in v8.1.1 v8.1.2 v8.1.3 v8.1.4 v8.1.5; do
			mkdir -p "$cache_root/$idle_release"
			touch -t "20000${idle_stamp}010000" "$cache_root/$idle_release"
			idle_stamp=$((idle_stamp + 1))
		done

		observed=$(PATH="$temporary_root/stat-bin:$test_path" HIPPO_INSTALL_CACHE="$cache_root" \
			HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
			HIPPO_TEST_UNAME_S="$simulated_uname" HIPPO_TEST_STAT_EMULATE="$simulated_stat" \
			HIPPO_TEST_IDENTITY="{\"schemaVersion\":1,\"version\":\"$ranking_version\",\"commit\":\"$test_commit\"}" \
			"$temporary_root/peers/ranking-$simulated_stat/hippo" probe)
		[ "$observed" = probe-ok ]
		[ -x "$cache_root/$ranking_version/$simulated_platform/hippo" ]
		[ -d "$cache_root/v8.1.5" ]
		[ -d "$cache_root/v8.1.4" ]
		[ ! -d "$cache_root/v8.1.3" ]
		[ ! -d "$cache_root/v8.1.2" ]
		[ ! -d "$cache_root/v8.1.1" ]
	done
	write_lock "$test_version" "$checksum"
	rm -rf -- "$cache_root" "$curl_count"
}

while IFS= read -r scenario; do
	# Name each scenario as it starts: a failure under `set -e` is otherwise
	# silent, and a corpus that shrank would still end in a pass line.
	echo "  $scenario"
	case "$scenario" in
	'A cold cache installs once and a warm cache needs no transport') run_cold_then_warm_cache ;;
	"Repository worker settings precede the caller's run arguments") run_worker_settings_precede_run_arguments ;;
	'Tampered warm-cache payload never executes') run_tampered_warm_cache ;;
	'A downloaded archive whose digest misses the pin never executes') run_download_digest_mismatch ;;
	'Non-exact stable release version is rejected') run_non_exact_stable_version ;;
	'Release identity envelope must match exactly') run_non_exact_identity_envelope ;;
	'Unsupported platform is refused before any transport') run_unsupported_platform_refused ;;
	'Matching live install-lock owner remains protected') run_matching_live_owner ;;
	'Malformed identity for a live install-lock owner fails closed') run_malformed_live_owner ;;
	'Reused live PID with a different valid identity is reclaimed') run_reused_live_pid ;;
	'Dead install-lock owner is reclaimed') run_dead_owner ;;
	'Crash before install-lock metadata publication is recoverable') run_crash_before_publication ;;
	'Concurrent cold callers install from exactly one verified download') run_concurrent_cold_callers ;;
	'Concurrent stale reclaimers preserve a replacement live owner') run_concurrent_stale_reclaimers ;;
	'A consumer never removes an install lock it did not publish') run_never_removes_a_foreign_install_lock ;;
	'Install guard storage stays bounded across release versions') run_bounded_install_guard_storage ;;
	'Retention never deletes a release another consumer is using') run_retention_protects_installing_release ;;
	'Retention never evicts a release another repository still uses') run_retention_keeps_releases_other_repositories_use ;;
	'Release ranking reads real timestamps on every supported platform') run_release_ranking_reads_real_timestamps ;;
	'Retention reclaims releases left idle beyond its window') run_retention_reclaims_idle_releases ;;
	'Concurrent owners survive a retryable coordination deferral') run_concurrent_owners_survive_retryable_deferral ;;
	*) exit 1 ;;
	esac
done <<EOF
$actual_scenarios
EOF

echo "hippo bootstrap tests passed"
