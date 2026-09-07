#!/bin/sh
# The adapter for specs/tools/rhino-consumer/behaviours/rhino-bootstrap.feature.
#
# This is a documented fork of .github/scripts/test-hippo-bootstrap.sh. The two
# consumers pin releases of different tools, but the hazard they defend against
# is the same one -- a machine-wide cache that several checkouts install into
# concurrently -- so the fixtures are deliberately the same shape. Where this
# file differs from its origin, it differs because RHINO differs:
#
#   * RHINO has no runtime configuration of its own, so there is no local policy
#     example to compare against.
#   * RHINO's release assets are named for Rust target triples, so the platform
#     the suite resolves is a triple rather than a goos/goarch pair.
#   * RHINO's wrapper passes its argument vector through untouched. HIPPO's maps
#     repository-specific worker settings ahead of it; the absence of any such
#     mapping is asserted here rather than left implied.
#   * Two scenarios are RHINO's own: platform refusal before any transport, and
#     the disjointness of the two bootstraps' state on a shared machine.
set -eu

repository_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
temporary_root=$(mktemp -d)
trap 'rm -rf -- "$temporary_root"' EXIT HUP INT TERM

# Build a synthetic tagged asset whose identity and digest are deterministic;
# the test never depends on GitHub or the machine's real installation cache.
subject="$temporary_root/consumer/rhino"
mkdir -p "$temporary_root/consumer" "$temporary_root/fake-bin" "$temporary_root/payload"
cp "$repository_root/rhino" "$subject"

chmod 755 "$subject"

# The suite runs on both Linux and macOS runners. Pinning the fake uname to one
# platform would send the wrapper down the wrong locking branch -- flock on
# Linux, lockf on Darwin -- so the real branch for the host is never exercised
# and the other one cannot even resolve its tool. Derive the platform from the
# real host, and let a scenario still override it explicitly.
case "$(uname -s)" in
Darwin) host_system=apple-darwin ;;
Linux) host_system=unknown-linux-gnu ;;
*)
	echo "unsupported host operating system for the bootstrap suite" >&2
	exit 78
	;;
esac
case "$(uname -m)" in
x86_64 | amd64) host_architecture=x86_64 ;;
arm64 | aarch64) host_architecture=aarch64 ;;
*)
	echo "unsupported host architecture for the bootstrap suite" >&2
	exit 78
	;;
esac
# A Rust target triple, because that is what the release assets are named for.
host_platform="$host_architecture-$host_system"
RHINO_TEST_HOST_UNAME_S=$(uname -s)
RHINO_TEST_HOST_UNAME_M=$(uname -m)
export RHINO_TEST_HOST_UNAME_S RHINO_TEST_HOST_UNAME_M

test_version=v9.8.7
test_commit=0123456789abcdef0123456789abcdef01234567
# `probe` is not a RHINO command, and never will be. The payload here is a stub,
# and giving the wrapper an argument the real product does not own keeps the
# marker it echoes from ever reading as a claim about a validator. What the
# marker proves is narrower and is the whole point: the wrapper executed the
# payload it verified.
cat >"$temporary_root/payload/rhino" <<EOF
#!/bin/sh
if [ "\${1:-}" = version ] && [ "\${2:-}" = --json ]; then
  if [ -n "\${RHINO_TEST_IDENTITY:-}" ]; then
    printf '%s\n' "\$RHINO_TEST_IDENTITY"
  else
    printf '%s\n' '{"schemaVersion":1,"version":"$test_version","commit":"$test_commit"}'
  fi
else
  if [ -n "\${RHINO_TEST_ARGUMENTS:-}" ]; then
    : > "\$RHINO_TEST_ARGUMENTS"
    for argument in "\$@"; do
      printf '%s\n' "\$argument" >> "\$RHINO_TEST_ARGUMENTS"
    done
  fi
  printf '%s\n' 'probe-ok'
fi
EOF
chmod 755 "$temporary_root/payload/rhino"
tar -czf "$temporary_root/release.tar.gz" -C "$temporary_root/payload" rhino

# PATH-local curl and uname fixtures exercise download and platform branches
# while leaving the bootstrap's production checksum path intact.
cat >"$temporary_root/fake-bin/curl" <<'EOF'
#!/bin/sh
set -eu
if [ "${RHINO_TEST_CURL_FAIL:-}" = 1 ]; then
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
cp "$RHINO_TEST_ARCHIVE" "$destination"
if [ -n "${RHINO_TEST_CURL_DELAY:-}" ]; then
  sleep "$RHINO_TEST_CURL_DELAY"
fi
printf '%s\n' download >> "$RHINO_TEST_CURL_COUNT"
EOF
chmod 755 "$temporary_root/fake-bin/curl"

cat >"$temporary_root/fake-bin/uname" <<'EOF'
#!/bin/sh
case "$1" in
  -s) printf '%s\n' "${RHINO_TEST_UNAME_S:-$RHINO_TEST_HOST_UNAME_S}" ;;
  -m) printf '%s\n' "${RHINO_TEST_UNAME_M:-$RHINO_TEST_HOST_UNAME_M}" ;;
  *) exit 2 ;;
esac
EOF
chmod 755 "$temporary_root/fake-bin/uname"

cat >"$temporary_root/fake-bin/sleep" <<'EOF'
#!/bin/sh
if [ "${RHINO_TEST_SLEEP_FAIL:-}" = 1 ]; then
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
if [ "${RHINO_TEST_RECLAIM_RACE:-}" = 1 ] && [ "$last_argument" = "${RHINO_TEST_RACE_LOCK:-}" ]; then
	controller=$RHINO_TEST_RACE_CONTROLLER
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
	cat >"$temporary_root/consumer/rhino.lock" <<EOF
version=$lock_version
commit=$test_commit
aarch64-apple-darwin=$lock_checksum
x86_64-apple-darwin=$lock_checksum
aarch64-unknown-linux-gnu=$lock_checksum
x86_64-unknown-linux-gnu=$lock_checksum
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
RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$counter_probe" RHINO_TEST_CURL_DELAY=1 \
	"$temporary_root/fake-bin/curl" --output "$temporary_root/probe-one.tar.gz" unused &
counter_probe_one=$!
RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$counter_probe" RHINO_TEST_CURL_DELAY=1 \
	"$temporary_root/fake-bin/curl" --output "$temporary_root/probe-two.tar.gz" unused &
counter_probe_two=$!
wait "$counter_probe_one"
wait "$counter_probe_two"
[ "$(awk 'END { print NR }' "$counter_probe")" -eq 2 ]
rm -f -- "$counter_probe" "$temporary_root/probe-one.tar.gz" "$temporary_root/probe-two.tar.gz"

# A cold cache downloads exactly once; a warm cache must work while the
# download transport is forced offline.
result=$(PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" "$subject" probe)
[ "$result" = probe-ok ]
[ "$(awk 'END { print NR }' "$curl_count")" = 1 ]

result=$(PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_CURL_FAIL=1 "$subject" probe)
[ "$result" = probe-ok ]
[ "$(awk 'END { print NR }' "$curl_count")" = 1 ]
[ -f "$cache_root/$test_version/$host_platform/rhino.sha256" ]

# Where HIPPO's consumer maps repository worker settings ahead of the caller's
# arguments, RHINO's passes the vector through untouched. That is a claim about
# the wrapper, not an absence, so it is asserted: a real command spelling goes
# in, and exactly that spelling must come out with nothing added, removed, or
# reordered.
arguments_file="$temporary_root/passed-arguments"
result=$(PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_CURL_FAIL=1 RHINO_TEST_ARGUMENTS="$arguments_file" "$subject" md word-count inspect --file README.md)
[ "$result" = probe-ok ]
expected_arguments='md
word-count
inspect
--file
README.md'
[ "$(sed -n '1,$p' "$arguments_file")" = "$expected_arguments" ]

# Integrity failures are configuration errors and must stop before executing an
# untrusted payload.
rm -rf -- "$cache_root"
write_lock "$test_version" 0000000000000000000000000000000000000000000000000000000000000000
set +e
PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" "$subject" probe >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 78 ]

# This adapter binds the canonical tool corpus by exact scenario title. The
# exact-list comparison makes a missing, duplicate, renamed, or unknown
# scenario fail before any fixture runs.
feature_file="$repository_root/specs/tools/rhino-consumer/behaviours/rhino-bootstrap.feature"
expected_scenarios='Tampered warm-cache payload never executes
Non-exact stable release version is rejected
Release identity envelope must match exactly
Unsupported platform is refused before any transport
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
The two consumer bootstraps never reach each other'"'"'s state'
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
	[ -x "$cache_root/$test_version/$host_platform/rhino" ]
	[ -f "$cache_root/$test_version/$host_platform/rhino.sha256" ]
	[ ! -e "$install_lock" ]
}

assert_waits_for_live_lock() {
	set +e
	PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" \
		RHINO_TEST_SLEEP_FAIL=1 "$subject" probe >/dev/null 2>&1
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
	result=$(PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" "$subject" probe)
	[ "$result" = probe-ok ]
	cached_binary="$cache_root/$test_version/$host_platform/rhino"

	# A digest mismatch must be rejected before the replacement executes.
	cat >"$cached_binary" <<EOF
#!/bin/sh
: > "$tamper_marker"
exit 0
EOF
	chmod 755 "$cached_binary"
	set +e
	PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_CURL_FAIL=1 "$subject" probe >/dev/null 2>&1
	status=$?
	set -e
	[ "$status" -eq 99 ]
	[ ! -e "$tamper_marker" ]

	# A matching sidecar digest cannot bypass the embedded release identity.
	rm -rf -- "$cache_root"
	result=$(PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" "$subject" probe)
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
	PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_CURL_FAIL=1 "$subject" probe >/dev/null 2>&1
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
		PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" "$subject" probe >/dev/null 2>&1
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
	PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" \
		RHINO_TEST_IDENTITY="{\"schemaVersion\":1,\"version\":\"$test_version\",\"commit\":\"$test_commit\",\"version\":\"v0.0.0\"}" \
		"$subject" probe >/dev/null 2>&1
	status=$?
	set -e
	[ "$status" -eq 78 ]
	[ "$(download_count)" -eq "$((downloads_before + 1))" ]
	[ ! -e "$cache_root/$test_version/$host_platform/rhino" ]
	[ ! -e "$cache_root/$test_version/$host_platform/rhino.sha256" ]
}

# RHINO publishes four target triples and no more. A host outside that matrix
# has no asset to fetch, so the refusal has to come before the transport rather
# than from a download that fails to find one: a 404 read as a network problem
# is the kind of error a caller retries forever.
run_unsupported_platform_refused() {
	write_lock "$test_version" "$checksum"
	rm -rf -- "$cache_root"
	downloads_before=$(download_count)

	set +e
	PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" \
		RHINO_TEST_UNAME_S=Plan9 "$subject" probe >/dev/null 2>&1
	status=$?
	set -e
	[ "$status" -eq 78 ]

	# An architecture RHINO does not build for is refused on the same terms as
	# an operating system it does not build for.
	set +e
	PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" \
		RHINO_TEST_UNAME_M=riscv64 "$subject" probe >/dev/null 2>&1
	status=$?
	set -e
	[ "$status" -eq 78 ]

	[ "$(download_count)" -eq "$downloads_before" ]
	[ ! -e "$cache_root" ]
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
	result=$(PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" \
		RHINO_TEST_SLEEP_FAIL=1 "$subject" probe)
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
	result=$(PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" \
		RHINO_TEST_SLEEP_FAIL=1 "$subject" probe)
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
	result=$(PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" \
		RHINO_TEST_SLEEP_FAIL=1 "$subject" probe)
	status=$?
	set -e
	[ "$status" -eq 0 ]
	assert_pinned_release_installed "$downloads_before"

	# A legacy owner that published only its now-dead PID is also recoverable.
	prepare_legacy_install_lock
	printf '%s\n' "$dead_pid" >"$install_lock/pid"
	downloads_before=$(download_count)
	result=$(PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" \
		RHINO_TEST_SLEEP_FAIL=1 "$subject" probe)
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
	result=$(PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" "$subject" probe)
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
	PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" \
		RHINO_TEST_CURL_DELAY=2 RHINO_TEST_RECLAIM_RACE=1 RHINO_TEST_RACE_LOCK="$install_lock" RHINO_TEST_RACE_CONTROLLER="$tracer" \
		"$subject" probe >"$first_result" &
	first_pid=$!
	PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" \
		RHINO_TEST_CURL_DELAY=2 RHINO_TEST_RECLAIM_RACE=1 RHINO_TEST_RACE_LOCK="$install_lock" RHINO_TEST_RACE_CONTROLLER="$tracer" \
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
	cp "$repository_root/rhino" "$peer_dir/rhino"
	chmod 755 "$peer_dir/rhino"
	cat >"$peer_dir/rhino.lock" <<PEERLOCK
version=$peer_version
commit=$test_commit
aarch64-apple-darwin=$checksum
x86_64-apple-darwin=$checksum
aarch64-unknown-linux-gnu=$checksum
x86_64-unknown-linux-gnu=$checksum
PEERLOCK
}

run_peer_consumer() {
	peer_name=$1
	peer_version=$2
	peer_delay=$3
	PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" \
		RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" \
		RHINO_TEST_CURL_COUNT="$curl_count" \
		RHINO_TEST_CURL_DELAY="$peer_delay" \
		RHINO_TEST_IDENTITY="{\"schemaVersion\":1,\"version\":\"$peer_version\",\"commit\":\"$test_commit\"}" \
		"$temporary_root/peers/$peer_name/rhino" probe
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
	[ -x "$cache_root/$pinned_version/$host_platform/rhino" ]
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
		[ -x "$cache_root/$sharing_version/$host_platform/rhino" ]
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
	[ -x "$cache_root/$idle_version/$host_platform/rhino" ]
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
		result=$(PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" \
			RHINO_TEST_IDENTITY="$release_identity" "$subject" probe)
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
run_release_ranking_reads_real_timestamps() {
	if grep -qE "stat -[fc] .*\|\| *stat -[fc] " "$repository_root/rhino"; then
		echo "rhino must read timestamps through a platform branch, not a stat fallback chain" >&2
		exit 1
	fi
	# A lone BSD or GNU read means a new call site skipped the branch entirely,
	# which fails on exactly one platform and passes on the other.
	bsd_reads=$(grep -cE '^[[:space:]]*stat -f ' "$repository_root/rhino")
	gnu_reads=$(grep -cE '^[[:space:]]*stat -c ' "$repository_root/rhino")
	[ "$bsd_reads" -eq "$gnu_reads" ]
	[ "$bsd_reads" -gt 0 ]
}

# Both wrappers install into one machine-wide cache under one user account. If
# either reached a path, variable, or asset the other owns, one tool's retention
# pass would reclaim the other tool's release, and the failure would surface as
# a checksum mismatch in whichever repository ran second.
#
# Proved statically rather than by running both: observing the real defaults
# would mean letting each wrapper install its real release from GitHub, and a
# test that downloads proves less than it costs. Comments are excluded from the
# name check, because this fork is required to say what it was forked from.
run_bootstraps_never_share_state() {
	rhino_wrapper="$repository_root/rhino"
	hippo_wrapper="$repository_root/hippo"
	[ -x "$rhino_wrapper" ]
	[ -x "$hippo_wrapper" ]

	if grep -v '^[[:space:]]*#' "$rhino_wrapper" | grep -qi hippo; then
		echo "the RHINO bootstrap names HIPPO in executable code" >&2
		return 1
	fi
	if grep -v '^[[:space:]]*#' "$hippo_wrapper" | grep -qi rhino; then
		echo "the HIPPO bootstrap names RHINO in executable code" >&2
		return 1
	fi

	# Name-disjointness alone would still permit two anonymous defaults that
	# collide, so every piece of state that lands on a shared machine has to
	# carry its own tool's name: the lock beside the wrapper, the cache-root
	# override, the cache directory, the transport override, and the asset.
	for bearing in 'rhino.lock' 'RHINO_INSTALL_CACHE' 'RHINO_DOWNLOAD_BASE_URL' '/rhino' 'rhino-'; do
		if ! grep -qF "$bearing" "$rhino_wrapper"; then
			echo "the RHINO bootstrap declares no $bearing" >&2
			return 1
		fi
	done
	for bearing in 'hippo.lock' 'HIPPO_INSTALL_CACHE' 'HIPPO_DOWNLOAD_BASE_URL' '/hippo' 'hippo_'; do
		if ! grep -qF "$bearing" "$hippo_wrapper"; then
			echo "the HIPPO bootstrap declares no $bearing" >&2
			return 1
		fi
	done

	# The seams each adapter drives are part of its bootstrap's environment
	# surface, and a shared one would let one adapter's fixtures steer the
	# other adapter's subject. Assignment and expansion positions only: this
	# adapter has to name HIPPO's seams above in order to assert HIPPO owns
	# them, and a check that a mention disqualifies could never be satisfied.
	seam_use='\$\{?HIPPO_|HIPPO_[A-Z_]*='
	if grep -qE "$seam_use" "$repository_root/.github/scripts/test-rhino-bootstrap.sh"; then
		echo "the RHINO bootstrap suite drives a HIPPO test seam" >&2
		return 1
	fi
	seam_use='\$\{?RHINO_|RHINO_[A-Z_]*='
	if grep -qE "$seam_use" "$repository_root/.github/scripts/test-hippo-bootstrap.sh"; then
		echo "the HIPPO bootstrap suite drives a RHINO test seam" >&2
		return 1
	fi
}

while IFS= read -r scenario; do
	case "$scenario" in
	'Tampered warm-cache payload never executes') run_tampered_warm_cache ;;
	'Non-exact stable release version is rejected') run_non_exact_stable_version ;;
	'Release identity envelope must match exactly') run_non_exact_identity_envelope ;;
	'Unsupported platform is refused before any transport') run_unsupported_platform_refused ;;
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
	"The two consumer bootstraps never reach each other's state") run_bootstraps_never_share_state ;;
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
PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" \
	RHINO_TEST_CURL_DELAY=1 "$subject" probe >"$first_result" &
first_pid=$!
PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" RHINO_TEST_CURL_COUNT="$curl_count" \
	RHINO_TEST_CURL_DELAY=1 "$subject" probe >"$second_result" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
[ "$(sed -n '1p' "$first_result")" = probe-ok ]
[ "$(sed -n '1p' "$second_result")" = probe-ok ]
[ "$(download_count)" -eq "$((downloads_before + 1))" ]
[ ! -e "$cache_root/$test_version/$host_platform.lock" ]
[ -z "$(find "$cache_root/$test_version" -name '.install-owner.*' -print -quit)" ]

echo "rhino bootstrap tests passed"
