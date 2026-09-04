#!/bin/sh
set -eu

repository_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
temporary_root=$(mktemp -d)
trap 'rm -rf -- "$temporary_root"' EXIT HUP INT TERM

# Build a synthetic tagged asset whose identity and digest are deterministic;
# the test never depends on GitHub or the machine's real installation cache.
subject="$temporary_root/consumer/hippo"
mkdir -p "$temporary_root/consumer" "$temporary_root/fake-bin" "$temporary_root/payload"
cp "$repository_root/hippo" "$subject"
chmod 755 "$subject"

test_version=v9.8.7
test_commit=0123456789abcdef0123456789abcdef01234567
cat >"$temporary_root/payload/hippo" <<EOF
#!/bin/sh
if [ "\${1:-}" = version ] && [ "\${2:-}" = --json ]; then
  printf '%s\n' '{"schemaVersion":1,"version":"$test_version","commit":"$test_commit"}'
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
count=0
if [ -f "$HIPPO_TEST_CURL_COUNT" ]; then
  count=$(sed -n '1p' "$HIPPO_TEST_CURL_COUNT")
fi
printf '%s\n' "$((count + 1))" > "$HIPPO_TEST_CURL_COUNT"
EOF
chmod 755 "$temporary_root/fake-bin/curl"

cat >"$temporary_root/fake-bin/uname" <<'EOF'
#!/bin/sh
case "$1" in
  -s) printf '%s\n' "${HIPPO_TEST_UNAME_S:-Darwin}" ;;
  -m) printf '%s\n' "${HIPPO_TEST_UNAME_M:-arm64}" ;;
  *) exit 2 ;;
esac
EOF
chmod 755 "$temporary_root/fake-bin/uname"

if command -v sha256sum >/dev/null 2>&1; then
	checksum=$(sha256sum "$temporary_root/release.tar.gz" | awk '{print $1}')
else
	checksum=$(shasum -a 256 "$temporary_root/release.tar.gz" | awk '{print $1}')
fi
cat >"$temporary_root/consumer/hippo.lock" <<EOF
version=$test_version
commit=$test_commit
darwin-amd64=$checksum
darwin-arm64=$checksum
linux-amd64=$checksum
linux-arm64=$checksum
EOF

test_path="$temporary_root/fake-bin:$PATH"
cache_root="$temporary_root/cache"
curl_count="$temporary_root/curl-count"
# A cold cache downloads exactly once; a warm cache must work while the
# download transport is forced offline.
result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" "$subject" probe)
[ "$result" = probe-ok ]
[ "$(sed -n '1p' "$curl_count")" = 1 ]

result=$(PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_CURL_FAIL=1 "$subject" probe)
[ "$result" = probe-ok ]
[ "$(sed -n '1p' "$curl_count")" = 1 ]

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
sed "s/$checksum/0000000000000000000000000000000000000000000000000000000000000000/g" \
	"$temporary_root/consumer/hippo.lock" >"$temporary_root/bad.lock"
mv "$temporary_root/bad.lock" "$temporary_root/consumer/hippo.lock"
set +e
PATH="$test_path" HIPPO_INSTALL_CACHE="$cache_root" HIPPO_TEST_ARCHIVE="$temporary_root/release.tar.gz" HIPPO_TEST_CURL_COUNT="$curl_count" "$subject" probe >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 78 ]

set +e
PATH="$test_path" HIPPO_TEST_UNAME_S=Plan9 "$subject" probe >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 78 ]

echo "hippo bootstrap tests passed"
