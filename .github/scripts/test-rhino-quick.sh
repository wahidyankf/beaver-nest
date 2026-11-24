#!/bin/sh
# Fast hermetic self-test for the RHINO consumer wrapper (`rhino-consumer` `test:quick`).
#
# A genuine subset of `.github/scripts/test-rhino-bootstrap.sh`: the branches
# that must refuse before any transport (missing or ambiguous pin, invalid
# version, commit, or checksum, unsupported platform), one local-archive
# install cycle (a cold cache installs once, a warm cache needs no transport),
# and the warm-cache tamper refusal. No network ever: transport is a
# PATH-local `curl` double serving a synthetic release built here, platforms
# come from a PATH-local `uname` double, and nothing here contends, so nothing
# here waits.
#
# C14 shape: lint (shellcheck, run by the Nx target before this script)
# checks the wrapper statically; this script is the unit-double level; the
# scoped `behaviour coverage validate` over B04 to B08 (run by the Nx target
# after this script) is the static corpus check. There is no typecheck: the
# wrapper and its doubles are POSIX shell.
set -eu

repository_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
temporary_root=$(mktemp -d)
trap 'rm -rf -- "$temporary_root"' EXIT HUP INT TERM

subject="$temporary_root/consumer/rhino"
mkdir -p "$temporary_root/consumer" "$temporary_root/fake-bin" "$temporary_root/payload"
cp "$repository_root/rhino" "$subject"
chmod 755 "$subject"

case "$(uname -s)" in
Darwin) host_system=apple-darwin ;;
Linux) host_system=unknown-linux-gnu ;;
*)
	echo "unsupported host operating system for the quick self-test" >&2
	exit 125
	;;
esac
case "$(uname -m)" in
x86_64 | amd64) host_architecture=x86_64 ;;
arm64 | aarch64) host_architecture=aarch64 ;;
*)
	echo "unsupported host architecture for the quick self-test" >&2
	exit 125
	;;
esac
host_platform="$host_architecture-$host_system"

test_version=v9.8.7
test_commit=0123456789abcdef0123456789abcdef01234567
cat >"$temporary_root/payload/rhino" <<EOF
#!/bin/sh
if [ "\${1:-}" = version ] && [ "\${2:-}" = --json ]; then
  printf '%s\n' '{"schemaVersion":1,"version":"$test_version","commit":"$test_commit"}'
else
  printf '%s\n' 'probe-ok'
fi
EOF
chmod 755 "$temporary_root/payload/rhino"
tar -czf "$temporary_root/release.tar.gz" -C "$temporary_root/payload" rhino

cat >"$temporary_root/fake-bin/curl" <<'EOF'
#!/bin/sh
set -eu
if [ "${RHINO_TEST_CURL_FAIL:-}" = 1 ]; then
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
cp "$RHINO_TEST_ARCHIVE" "$destination"
printf '%s\n' "$requested_url" >> "$RHINO_TEST_CURL_COUNT"
EOF
chmod 755 "$temporary_root/fake-bin/curl"

cat >"$temporary_root/fake-bin/uname" <<EOF
#!/bin/sh
case "\$1" in
  -s) printf '%s\n' "\${RHINO_TEST_UNAME_S:-$(uname -s)}" ;;
  -m) printf '%s\n' "\${RHINO_TEST_UNAME_M:-$(uname -m)}" ;;
  *) exit 2 ;;
esac
EOF
chmod 755 "$temporary_root/fake-bin/uname"

if command -v sha256sum >/dev/null 2>&1; then
	checksum=$(sha256sum "$temporary_root/release.tar.gz" | awk '{print $1}')
else
	checksum=$(shasum -a 256 "$temporary_root/release.tar.gz" | awk '{print $1}')
fi
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

test_path="$temporary_root/fake-bin:$PATH"
cache_root="$temporary_root/cache"
curl_count="$temporary_root/curl-count"

download_count() {
	if [ -f "$curl_count" ]; then
		awk 'END { print NR }' "$curl_count"
	else
		printf '%s\n' 0
	fi
}

run_probe() {
	set +e
	PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" \
		RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" \
		RHINO_TEST_CURL_COUNT="$curl_count" \
		"$subject" probe >"$temporary_root/probe-out" 2>"$temporary_root/probe-err"
	probe_status=$?
	set -e
}

echo "quick: a missing pin exits 125 before any transport"
write_lock "$test_version" "$checksum"
rm -f -- "$temporary_root/consumer/rhino.lock"
rm -rf -- "$cache_root" "$curl_count"
run_probe
echo "  exit $probe_status"
[ "$probe_status" -eq 125 ]
grep -Fq 'rhino has no pin at rhino.lock' "$temporary_root/probe-err"
[ ! -s "$temporary_root/probe-out" ]
[ "$(download_count)" -eq 0 ]
[ ! -e "$cache_root" ]

echo "quick: a duplicated version key exits 125 before any transport"
write_lock "$test_version" "$checksum"
printf 'version=%s\n' v0.0.0 >>"$temporary_root/consumer/rhino.lock"
rm -rf -- "$cache_root" "$curl_count"
run_probe
echo "  exit $probe_status"
[ "$probe_status" -eq 125 ]
grep -Fq 'missing or duplicate version' "$temporary_root/probe-err"
[ ! -s "$temporary_root/probe-out" ]
[ "$(download_count)" -eq 0 ]
[ ! -e "$cache_root" ]

echo "quick: an invalid commit exits 125 before any transport"
write_lock "$test_version" "$checksum"
awk -v bad=short '{ if ($0 ~ /^commit=/) print "commit=" bad; else print }' \
	"$temporary_root/consumer/rhino.lock" >"$temporary_root/consumer/rhino.lock.tmp"
mv "$temporary_root/consumer/rhino.lock.tmp" "$temporary_root/consumer/rhino.lock"
rm -rf -- "$cache_root" "$curl_count"
run_probe
echo "  exit $probe_status"
[ "$probe_status" -eq 125 ]
grep -Fq 'invalid commit' "$temporary_root/probe-err"
[ ! -s "$temporary_root/probe-out" ]
[ "$(download_count)" -eq 0 ]
[ ! -e "$cache_root" ]

echo "quick: an invalid checksum exits 125 before any transport"
write_lock "$test_version" "$checksum"
awk -v plat="$host_platform" '{ if ($0 ~ "^" plat "=") print plat "=invalid"; else print }' \
	"$temporary_root/consumer/rhino.lock" >"$temporary_root/consumer/rhino.lock.tmp"
mv "$temporary_root/consumer/rhino.lock.tmp" "$temporary_root/consumer/rhino.lock"
rm -rf -- "$cache_root" "$curl_count"
run_probe
echo "  exit $probe_status"
[ "$probe_status" -eq 125 ]
grep -Fq 'invalid checksum' "$temporary_root/probe-err"
[ ! -s "$temporary_root/probe-out" ]
[ "$(download_count)" -eq 0 ]
[ ! -e "$cache_root" ]

echo "quick: an unsupported operating system is refused before any transport"
write_lock "$test_version" "$checksum"
rm -rf -- "$cache_root" "$curl_count"
set +e
RHINO_TEST_UNAME_S=Plan9 \
	PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" \
	RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" \
	RHINO_TEST_CURL_COUNT="$curl_count" \
	"$subject" probe >"$temporary_root/probe-out" 2>"$temporary_root/probe-err"
probe_status=$?
set -e
echo "  exit $probe_status"
[ "$probe_status" -eq 125 ]
grep -Fq 'does not support this operating system' "$temporary_root/probe-err"
[ ! -s "$temporary_root/probe-out" ]
[ "$(download_count)" -eq 0 ]
[ ! -e "$cache_root" ]

echo "quick: an unsupported architecture is refused before any transport"
write_lock "$test_version" "$checksum"
rm -rf -- "$cache_root" "$curl_count"
set +e
RHINO_TEST_UNAME_M=riscv64 \
	PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" \
	RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" \
	RHINO_TEST_CURL_COUNT="$curl_count" \
	"$subject" probe >"$temporary_root/probe-out" 2>"$temporary_root/probe-err"
probe_status=$?
set -e
echo "  exit $probe_status"
[ "$probe_status" -eq 125 ]
grep -Fq 'does not support this architecture' "$temporary_root/probe-err"
[ ! -s "$temporary_root/probe-out" ]
[ "$(download_count)" -eq 0 ]
[ ! -e "$cache_root" ]

echo "quick: a cold cache installs once and a warm cache needs no transport"
write_lock "$test_version" "$checksum"
rm -rf -- "$cache_root" "$curl_count"
downloads_before=$(download_count)
result=$(PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" \
	RHINO_TEST_ARCHIVE="$temporary_root/release.tar.gz" \
	RHINO_TEST_CURL_COUNT="$curl_count" "$subject" probe)
[ "$result" = probe-ok ]
[ "$(download_count)" -eq "$((downloads_before + 1))" ]
[ -x "$cache_root/$test_version/$host_platform/rhino" ]
[ -f "$cache_root/$test_version/$host_platform/rhino.sha256" ]
[ ! -e "$cache_root/$test_version/$host_platform.lock" ]
result=$(PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" \
	RHINO_TEST_CURL_FAIL=1 "$subject" probe)
[ "$result" = probe-ok ]
[ "$(download_count)" -eq "$((downloads_before + 1))" ]

echo "quick: a tampered warm-cache payload never executes"
tamper_marker="$temporary_root/tampered-executed"
rm -f -- "$tamper_marker"
cached_binary="$cache_root/$test_version/$host_platform/rhino"
cat >"$cached_binary" <<EOF
#!/bin/sh
: > "$tamper_marker"
exit 0
EOF
chmod 755 "$cached_binary"
set +e
PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" \
	RHINO_TEST_CURL_FAIL=1 "$subject" probe >/dev/null 2>&1
probe_status=$?
set -e
echo "  exit $probe_status"
[ "$probe_status" -eq 99 ]
[ ! -e "$tamper_marker" ]
cat >"$cached_binary" <<EOF
#!/bin/sh
if [ "\${1:-}" = version ] && [ "\${2:-}" = --json ]; then
  printf '%s\n' '{"schemaVersion":1,"version":"v0.0.0","commit":"$test_commit"}'
else
  : > "$tamper_marker"
fi
EOF
chmod 755 "$cached_binary"
if command -v sha256sum >/dev/null 2>&1; then
	sha256sum <"$cached_binary" | awk '{print $1}' >"$cached_binary.sha256"
else
	shasum -a 256 <"$cached_binary" | awk '{print $1}' >"$cached_binary.sha256"
fi
set +e
PATH="$test_path" RHINO_INSTALL_CACHE="$cache_root" \
	RHINO_TEST_CURL_FAIL=1 "$subject" probe >/dev/null 2>&1
probe_status=$?
set -e
echo "  exit $probe_status"
[ "$probe_status" -eq 99 ]
[ ! -e "$tamper_marker" ]

echo "rhino quick self-test passed"
