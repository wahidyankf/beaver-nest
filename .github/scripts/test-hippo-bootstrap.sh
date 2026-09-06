#!/bin/sh
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
mkdir -p "$temporary_root/consumer" "$temporary_root/fake-bin" "$temporary_root/payload"
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
  : > "\$HIPPO_TEST_ARGUMENTS"
  for argument in "\$@"; do
    printf '%s\n' "\$argument" >> "\$HIPPO_TEST_ARGUMENTS"
  done
  printf '%s\n' 'run-ok'
else
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
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output ]; then
    destination=$2
    shift 2
  else
    shift
  fi
done
cp "$HIPPO_TEST_ARCHIVE" "$destination"
if [ -n "${HIPPO_TEST_CURL_DELAY:-}" ]; then
  sleep "$HIPPO_TEST_CURL_DELAY"
fi
printf '%s\n' download >> "$HIPPO_TEST_CURL_COUNT"
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

cat >"$temporary_root/fake-bin/rm" <<'EOF'
#!/bin/sh
set -eu
last_argument=
for argument in "$@"; do
	last_argument=$argument
done
if [ "${HIPPO_TEST_RECLAIM_RACE:-}" = 1 ] && [ "$last_argument" = "${HIPPO_TEST_RACE_LOCK:-}" ]; then
	controller=$HIPPO_TEST_RACE_CONTROLLER
	: >"$controller/ready.$$"
	if mkdir "$controller/first" 2>/dev/null; then
		attempt=0
		while [ "$(find "$controller" -name 'ready.*' -type f | awk 'END { print NR }')" -lt 2 ]; do
			attempt=$((attempt + 1))
			[ "$attempt" -lt 40 ] || break
			/bin/sleep 0.05
		done
		/bin/rm "$@"
		: >"$controller/first-removed"
		exit 0
	fi

	attempt=0
	while [ ! -f "$controller/first-removed" ]; do
		attempt=$((attempt + 1))
		[ "$attempt" -lt 100 ] || exit 98
		/bin/sleep 0.05
	done
	attempt=0
	while [ ! -e "$last_argument" ]; do
		attempt=$((attempt + 1))
		[ "$attempt" -lt 100 ] || exit 98
		/bin/sleep 0.05
	done
	/bin/rm "$@"
	: >"$controller/second-removed"
	exit 0
fi
exec /bin/rm "$@"
EOF
chmod 755 "$temporary_root/fake-bin/rm"

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

# A cold cache downloads exactly once; a warm cache must work while the
# download transport is forced offline.
result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" "$subject" probe)
[ "$result" = probe-ok ]
[ "$(awk 'END { print NR }' "$curl_count")" = 1 ]

result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_CURL_FAIL=1 "$subject" probe)
[ "$result" = probe-ok ]
[ "$(awk 'END { print NR }' "$curl_count")" = 1 ]
[ -f "$cache_root/$test_version/$host_platform/hippo.sha256" ]

# Restore a verified cache before checking the consumer-specific mappings.
# Repository-specific worker mappings belong in this consumer wrapper. Verify
# all mappings precede the original run arguments without changing their order.
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

# Integrity and unsupported-platform failures are configuration errors and
# must stop before executing an untrusted payload.
rm -rf -- "$cache_root"
write_lock "$test_version" 0000000000000000000000000000000000000000000000000000000000000000
set +e
PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" "$subject" probe >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 78 ]

# This adapter binds the canonical tool corpus by exact scenario title. The
# exact-list comparison makes a missing, duplicate, renamed, or unknown
# scenario fail before any fixture runs.
feature_file="$repository_root/specs/tools/hippo-consumer/behaviours/hippo-bootstrap.feature"
expected_scenarios='Tampered warm-cache payload never executes
Non-exact stable release version is rejected
Release identity envelope must match exactly
Matching live install-lock owner remains protected
Malformed identity for a live install-lock owner fails closed
Reused live PID with a different valid identity is reclaimed
Dead install-lock owner is reclaimed
Crash before install-lock metadata publication is recoverable
Concurrent stale reclaimers preserve a replacement live owner
Install guard storage stays bounded across release versions
Retention never deletes a release another consumer is installing
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
	for invalid_version in v1x.2.3 v1.2.3-rc1 'v1.2.3/../../../escape'; do
		write_lock "$invalid_version" "$checksum"
		set +e
		PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" "$subject" probe >/dev/null 2>&1
		status=$?
		set -e
		[ "$status" -eq 78 ]
	done
	[ "$(download_count)" -eq "$downloads_before" ]
	[ ! -e "$temporary_root/escape" ]
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
	prepare_atomic_install_lock
	printf '%s\n%s\n' "$$" 'malformed-process-identity' >"$install_lock"
	assert_waits_for_live_lock

	# A valid-looking stale digest plus a trailing field is still malformed and
	# cannot authorize reclamation of a live PID.
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
	result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" "$subject" probe)
	assert_pinned_release_installed "$downloads_before"
	[ ! -e "$expired_orphan" ]
	[ -f "$fresh_orphan" ]
	[ -f "$live_preparation" ]
	rm -f -- "$fresh_orphan" "$live_preparation"
}

run_concurrent_stale_reclaimers() {
	prepare_atomic_install_lock
	dead_pid=2147483647
	if kill -0 "$dead_pid" 2>/dev/null; then
		exit 1
	fi
	printf '%s\n%064d\n' "$dead_pid" 0 >"$install_lock"
	tracer="$temporary_root/reclaim-race"
	mkdir -p "$tracer"
	downloads_before=$(download_count)
	first_result="$temporary_root/reclaimer-first"
	second_result="$temporary_root/reclaimer-second"
	PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_CURL_DELAY=2 HIPPO_TEST_RECLAIM_RACE=1 HIPPO_TEST_RACE_LOCK="$install_lock" HIPPO_TEST_RACE_CONTROLLER="$tracer" \
		"$subject" probe >"$first_result" &
	first_pid=$!
	PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
		HIPPO_TEST_CURL_DELAY=2 HIPPO_TEST_RECLAIM_RACE=1 HIPPO_TEST_RACE_LOCK="$install_lock" HIPPO_TEST_RACE_CONTROLLER="$tracer" \
		"$subject" probe >"$second_result" &
	second_pid=$!
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
	install_peer_consumer pruning "$pinned_version"

	mkdir -p "$cache_root/$claimed_version"
	sentinel="$cache_root/$claimed_version/.survives-retention"
	: >"$sentinel"
	# A live claim published by this test stands in for a consumer that is
	# mid-install: the same PID and process-start digest the wrapper records.
	# Publishing it by hand keeps the assertion deterministic, where racing two
	# real consumers would only sometimes overlap the retention pass.
	process_start=$(LC_ALL=C ps -o lstart= -p "$$" 2>/dev/null | awk '{$1=$1; print; exit}')
	live_identity=$(printf '%s\n' "$process_start" | hash_stream)
	printf '%s\n%s\n' "$$" "$live_identity" \
		>"$cache_root/$claimed_version/.release-claim.$$.$live_identity.live"
	# Oldest of all candidates, and outside the ranked budget, so only the claim
	# can save it.
	touch -t 200001010000 "$cache_root/$claimed_version"
	for bystander in v9.6.1 v9.6.2 v9.6.3; do
		mkdir -p "$cache_root/$bystander"
		touch -t 200002010000 "$cache_root/$bystander"
	done

	[ "$(run_peer_consumer pruning "$pinned_version" 0)" = probe-ok ]

	[ -f "$sentinel" ]
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

run_bounded_install_guard_storage() {
	rm -rf -- "$cache_root"
	for release_version in v9.8.7 v9.8.8 v9.8.9 v9.8.10; do
		write_lock "$release_version" "$checksum"
		release_identity="{\"schemaVersion\":1,\"version\":\"$release_version\",\"commit\":\"$test_commit\"}"
		result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
			HIPPO_TEST_IDENTITY="$release_identity" "$subject" probe)
		[ "$result" = probe-ok ]
	done
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

# The BSD form `stat -f` means "filesystem status" to GNU coreutils, which writes
# a block of filesystem detail to stdout before failing on the format operand, so
# a `stat -f ... || stat -c ...` fallback chain captures that detail alongside the
# real value. Retention then ranks releases by prose instead of by time. The fault
# is invisible on macOS, where the BSD form succeeds, so a single-platform run can
# only honour "on every supported platform" by asserting that no timestamp read
# takes a platform-fragile path.
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

run_release_ranking_reads_real_timestamps() {
	if grep -qE "stat -[fc] .*\|\| *stat -[fc] " "$repository_root/hippo"; then
		echo "hippo must read timestamps through a platform branch, not a stat fallback chain" >&2
		exit 1
	fi
	# A lone BSD or GNU read means a new call site skipped the branch entirely,
	# which fails on exactly one platform and passes on the other.
	bsd_reads=$(grep -cE '^[[:space:]]*stat -f ' "$repository_root/hippo")
	gnu_reads=$(grep -cE '^[[:space:]]*stat -c ' "$repository_root/hippo")
	[ "$bsd_reads" -eq "$gnu_reads" ]
	[ "$bsd_reads" -gt 0 ]
}

while IFS= read -r scenario; do
	case "$scenario" in
	'Tampered warm-cache payload never executes') run_tampered_warm_cache ;;
	'Non-exact stable release version is rejected') run_non_exact_stable_version ;;
	'Release identity envelope must match exactly') run_non_exact_identity_envelope ;;
	'Matching live install-lock owner remains protected') run_matching_live_owner ;;
	'Malformed identity for a live install-lock owner fails closed') run_malformed_live_owner ;;
	'Reused live PID with a different valid identity is reclaimed') run_reused_live_pid ;;
	'Dead install-lock owner is reclaimed') run_dead_owner ;;
	'Crash before install-lock metadata publication is recoverable') run_crash_before_publication ;;
	'Concurrent stale reclaimers preserve a replacement live owner') run_concurrent_stale_reclaimers ;;
	'Install guard storage stays bounded across release versions') run_bounded_install_guard_storage ;;
	'Retention never deletes a release another consumer is installing') run_retention_protects_installing_release ;;
	'Retention never evicts a release another repository still uses') run_retention_keeps_releases_other_repositories_use ;;
	'Release ranking reads real timestamps on every supported platform') run_release_ranking_reads_real_timestamps ;;
	'Retention reclaims releases left idle beyond its window') run_retention_reclaims_idle_releases ;;
	'Concurrent owners survive a retryable coordination deferral') run_concurrent_owners_survive_retryable_deferral ;;
	*) exit 1 ;;
	esac
done <<EOF
$actual_scenarios
EOF

# Two normal cold-cache callers contend through the atomically published owner
# record. Both complete from one verified download, and exact-owner cleanup
# leaves neither the published lock nor a prepared-record file behind.
rm -rf -- "$cache_root"
downloads_before=$(download_count)
first_result="$temporary_root/concurrent-first"
second_result="$temporary_root/concurrent-second"
PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
	HIPPO_TEST_CURL_DELAY=1 "$subject" probe >"$first_result" &
first_pid=$!
PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" \
	HIPPO_TEST_CURL_DELAY=1 "$subject" probe >"$second_result" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
[ "$(sed -n '1p' "$first_result")" = probe-ok ]
[ "$(sed -n '1p' "$second_result")" = probe-ok ]
[ "$(download_count)" -eq "$((downloads_before + 1))" ]
[ ! -e "$cache_root/$test_version/$host_platform.lock" ]
[ -z "$(find "$cache_root/$test_version" -name '.install-owner.*' -print -quit)" ]

write_lock "$test_version" "$checksum"
set +e
PATH="$test_path" HIPPO_TEST_UNAME_S=Plan9 "$subject" probe >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 78 ]

echo "hippo bootstrap tests passed"
