#!/bin/sh
# The adapter for specs/apps/tools/rhino-consumer/behaviours/ferret-bootstrap.feature.
set -eu

repository_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
temporary_root=$(mktemp -d)
trap 'rm -rf -- "$temporary_root"' EXIT HUP INT TERM

grep -Eq '^version=v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' "$repository_root/ferret.lock"
grep -Eq '^commit=[0-9a-f]{40}$' "$repository_root/ferret.lock"
grep -Eq '^artifact=[0-9a-f]{64}$' "$repository_root/ferret.lock"

test_version=v9.9.9
test_commit=0123456789abcdef0123456789abcdef01234567
mkdir -p "$temporary_root/consumer" "$temporary_root/fake-bin" "$temporary_root/payload"
cp "$repository_root/ferret" "$temporary_root/consumer/ferret"
chmod 755 "$temporary_root/consumer/ferret"
subject="$temporary_root/consumer/ferret"

make_pyz() {
	out=$1
	ver=$2
	cat >"$out" <<EOF
#!/bin/sh
if [ "\${1:-}" = version ]; then
	printf '%s\n' 'ferret $ver'
else
	printf '%s\n' 'ferret-ok'
	for a in "\$@"; do
		printf '%s\n' "\$a" >> "\${FERRET_TEST_ARGS:-/dev/null}"
	done
fi
EOF
	chmod 755 "$out"
}

if command -v sha256sum >/dev/null 2>&1; then
	digest_of() { sha256sum "$1" | awk '{print $1}'; }
else
	digest_of() { shasum -a 256 "$1" | awk '{print $1}'; }
fi

good_pyz="$temporary_root/payload/good.pyz"
make_pyz "$good_pyz" "9.9.9"
good_digest=$(digest_of "$good_pyz")
good_artifact="ferret-cli_${test_version}.pyz"
cp "$good_pyz" "$temporary_root/payload/$good_artifact"
printf '%s  %s\n' "$good_digest" "$good_artifact" >"$temporary_root/payload/checksums.txt"

write_lock() {
	ver=$1
	com=$2
	dig=$3
	cat >"$temporary_root/consumer/ferret.lock" <<EOF
version=$ver
commit=$com
artifact=$dig
EOF
}

write_lock "$test_version" "$test_commit" "$good_digest"

cat >"$temporary_root/fake-bin/curl" <<'EOF'
#!/bin/sh
set -eu
dest=""
url=""
while [ "$#" -gt 0 ]; do
	case "$1" in
	-o) dest=$2; shift 2 ;;
	-*) shift ;;
	*) url=$1; shift ;;
	esac
done
if [ "${FERRET_TEST_FAIL:-}" = archive ]; then
	case "$url" in
	*.pyz) exit 22 ;;
	esac
fi
if [ "${FERRET_TEST_FAIL:-}" = checksums ]; then
	case "$url" in
	*checksums.txt) exit 22 ;;
	esac
fi
case "$url" in
	*.pyz) cp "${FERRET_TEST_ARCHIVE:-/nonexistent}" "$dest" ;;
	*checksums.txt) cp "${FERRET_TEST_CHECKSUMS:-/nonexistent}" "$dest" ;;
	*) exit 22 ;;
esac
if [ -n "${FERRET_TEST_CURL_COUNT:-}" ]; then
	printf '%s\n' "$url" >> "$FERRET_TEST_CURL_COUNT"
fi
EOF
chmod 755 "$temporary_root/fake-bin/curl"

cat >"$temporary_root/fake-bin/sha256sum" <<'EOF'
#!/bin/sh
exec /usr/bin/sha256sum "$@"
EOF
chmod 755 "$temporary_root/fake-bin/sha256sum" 2>/dev/null || true

test_path="$temporary_root/fake-bin:$PATH"
cache_root="$temporary_root/cache"
curl_count="$temporary_root/curl-count"
mkdir -p "$temporary_root/path-ferret"
cat >"$temporary_root/path-ferret/ferret" <<EOF
#!/bin/sh
: > "$temporary_root/path-ferret-called"
exit 99
EOF
chmod 755 "$temporary_root/path-ferret/ferret"
rm -f -- "$temporary_root/path-ferret-called"

feature_file="$repository_root/specs/apps/tools/rhino-consumer/behaviours/ferret-bootstrap.feature"
expected_scenarios='./ferret installs and verifies the pinned FERRET before running it
./ferret refuses an unpinned fallback or a failed install
A missing, duplicated, or malformed pin makes ./ferret refuse with 125'
actual_scenarios=$(awk '/^[[:space:]]*Scenario( Outline)?: / { sub(/^[[:space:]]*Scenario( Outline)?: /, ""); print }' "$feature_file")
[ "$actual_scenarios" = "$expected_scenarios" ]

run_install_and_verify() {
	write_lock "$test_version" "$test_commit" "$good_digest"
	rm -rf -- "$cache_root" "$curl_count"
	: > "$curl_count"
	FERRET_TEST_ARCHIVE="$temporary_root/payload/$good_artifact" FERRET_TEST_CHECKSUMS="$temporary_root/payload/checksums.txt" \
		PATH="$temporary_root/path-ferret:$test_path" FERRET_INSTALL_CACHE="$cache_root" \
		FERRET_TEST_CURL_COUNT="$curl_count" FERRET_TEST_ARGS="$temporary_root/args-one" \
		"$subject" hello world >"$temporary_root/out-one"
	[ "$(cat "$temporary_root/out-one")" = ferret-ok ]
	[ "$(cat "$temporary_root/args-one")" = "$(printf 'hello\nworld\n')" ]
	[ "$(wc -l <"$curl_count")" -eq 2 ]
	[ -x "$cache_root/$test_version/ferret" ]
	[ ! -e "$temporary_root/path-ferret-called" ]
	downloads_before=$(wc -l <"$curl_count")
	FERRET_TEST_ARCHIVE="$temporary_root/payload/$good_artifact" FERRET_TEST_CHECKSUMS="$temporary_root/payload/checksums.txt" \
		PATH="$temporary_root/path-ferret:$test_path" FERRET_INSTALL_CACHE="$cache_root" \
		FERRET_TEST_CURL_COUNT="$curl_count" FERRET_TEST_ARGS="$temporary_root/args-two" \
		FERRET_TEST_FAIL=archive "$subject" again >"$temporary_root/out-two"
	[ "$(cat "$temporary_root/out-two")" = ferret-ok ]
	[ "$(wc -l <"$curl_count")" -eq "$downloads_before" ]
	[ ! -e "$temporary_root/path-ferret-called" ]
	printf '#!/bin/sh\nexit 0\n' >"$cache_root/$test_version/ferret"
	chmod 755 "$cache_root/$test_version/ferret"
	set +e
	PATH="$temporary_root/path-ferret:$test_path" FERRET_INSTALL_CACHE="$cache_root" \
		FERRET_TEST_CURL_COUNT="$curl_count" FERRET_TEST_FAIL=archive "$subject" probe >/dev/null 2>"$temporary_root/tamper-refusal"
	status=$?
	set -e
	[ "$status" -eq 125 ]
	grep -Fq '[ferret]' "$temporary_root/tamper-refusal"
	write_lock "$test_version" "$test_commit" "$good_digest"
	rm -rf -- "$cache_root" "$curl_count"
}

run_refuses_fallback_or_failed_install() {
	write_lock "$test_version" "$test_commit" "$good_digest"
	rm -rf -- "$cache_root" "$curl_count"
	: > "$curl_count"
	set +e
	FERRET_TEST_ARCHIVE="$temporary_root/payload/$good_artifact" FERRET_TEST_CHECKSUMS="$temporary_root/payload/checksums.txt" \
		PATH="$temporary_root/path-ferret:$test_path" FERRET_INSTALL_CACHE="$cache_root" FERRET_TEST_CURL_COUNT="$curl_count" \
		FERRET_TEST_FAIL=archive "$subject" probe >/dev/null 2>"$temporary_root/fail-archive"
	status=$?
	set -e
	[ "$status" -eq 125 ]
	grep -Fq 'will not fall back to an unpinned one' "$temporary_root/fail-archive"
	[ ! -x "$cache_root/$test_version/ferret" ]
	set +e
	FERRET_TEST_ARCHIVE="$temporary_root/payload/$good_artifact" FERRET_TEST_CHECKSUMS="$temporary_root/payload/checksums.txt" \
		PATH="$temporary_root/path-ferret:$test_path" FERRET_INSTALL_CACHE="$cache_root" FERRET_TEST_CURL_COUNT="$curl_count" \
		FERRET_TEST_FAIL=checksums "$subject" probe >/dev/null 2>"$temporary_root/fail-checksums"
	status=$?
	set -e
	[ "$status" -eq 125 ]
	grep -Fq 'release checksums could not be fetched' "$temporary_root/fail-checksums"
	printf '%s  %s\n' "0000000000000000000000000000000000000000000000000000000000000000" "$good_artifact" >"$temporary_root/bad-checksums.txt"
	set +e
	FERRET_TEST_ARCHIVE="$temporary_root/payload/$good_artifact" FERRET_TEST_CHECKSUMS="$temporary_root/bad-checksums.txt" \
		PATH="$temporary_root/path-ferret:$test_path" FERRET_INSTALL_CACHE="$cache_root" FERRET_TEST_CURL_COUNT="$curl_count" \
		"$subject" probe >/dev/null 2>"$temporary_root/fail-published"
	status=$?
	set -e
	[ "$status" -eq 125 ]
	grep -Fq 'publishes a different digest' "$temporary_root/fail-published"
	bad_pyz="$temporary_root/bad.pyz"
	make_pyz "$bad_pyz" "9.9.9"
	printf '# tamper to change the digest while keeping the version\n' >>"$bad_pyz"
	chmod 755 "$bad_pyz"
	set +e
	FERRET_TEST_ARCHIVE="$bad_pyz" FERRET_TEST_CHECKSUMS="$temporary_root/payload/checksums.txt" \
		PATH="$temporary_root/path-ferret:$test_path" FERRET_INSTALL_CACHE="$cache_root" FERRET_TEST_CURL_COUNT="$curl_count" \
		"$subject" probe >/dev/null 2>"$temporary_root/fail-bytes"
	status=$?
	set -e
	[ "$status" -eq 125 ]
	grep -Fq 'does not match the pinned digest' "$temporary_root/fail-bytes"
	wrong_pyz="$temporary_root/wrong.pyz"
	make_pyz "$wrong_pyz" "0.0.0"
	wrong_digest=$(digest_of "$wrong_pyz")
	write_lock "$test_version" "$test_commit" "$wrong_digest"
	printf '%s  %s\n' "$wrong_digest" "$good_artifact" >"$temporary_root/wrong-checksums.txt"
	set +e
	FERRET_TEST_ARCHIVE="$wrong_pyz" FERRET_TEST_CHECKSUMS="$temporary_root/wrong-checksums.txt" \
		PATH="$temporary_root/path-ferret:$test_path" FERRET_INSTALL_CACHE="$cache_root" FERRET_TEST_CURL_COUNT="$curl_count" \
		"$subject" probe >/dev/null 2>"$temporary_root/fail-version"
	status=$?
	set -e
	[ "$status" -eq 125 ]
	grep -Fq 'reports a version the pin does not name' "$temporary_root/fail-version"
	write_lock "$test_version" "$test_commit" "$good_digest"
	rm -rf -- "$cache_root"
	mkdir -p "$cache_root/$test_version"
	printf '#!/bin/sh\necho tampered\n' >"$cache_root/$test_version/ferret"
	chmod 755 "$cache_root/$test_version/ferret"
	set +e
	FERRET_TEST_ARCHIVE="$bad_pyz" FERRET_TEST_CHECKSUMS="$temporary_root/payload/checksums.txt" \
		PATH="$temporary_root/path-ferret:$test_path" FERRET_INSTALL_CACHE="$cache_root" FERRET_TEST_CURL_COUNT="$curl_count" \
		"$subject" probe >/dev/null 2>"$temporary_root/fail-cached"
	status=$?
	set -e
	[ "$status" -eq 125 ]
	grep -Fq '[ferret]' "$temporary_root/fail-cached"
	[ ! -e "$temporary_root/path-ferret-called" ]
	write_lock "$test_version" "$test_commit" "$good_digest"
	rm -rf -- "$cache_root" "$curl_count"
}

run_pin_refusals_125() {
	rm -rf -- "$cache_root"
	rm -f -- "$temporary_root/consumer/ferret.lock"
	set +e
	PATH="$temporary_root/path-ferret:$test_path" FERRET_INSTALL_CACHE="$cache_root" "$subject" probe >/dev/null 2>"$temporary_root/ferret-no-lock"
	status=$?
	set -e
	[ "$status" -eq 125 ]
	grep -Fq 'there is no pin at ferret.lock' "$temporary_root/ferret-no-lock"
	write_lock "$test_version" "$test_commit" "$good_digest"
	printf 'version=%s\n' "$test_version" >>"$temporary_root/consumer/ferret.lock"
	set +e
	PATH="$temporary_root/path-ferret:$test_path" FERRET_INSTALL_CACHE="$cache_root" "$subject" probe >/dev/null 2>"$temporary_root/ferret-dup"
	status=$?
	set -e
	[ "$status" -eq 125 ]
	grep -Fq 'more than once' "$temporary_root/ferret-dup"
	write_lock "bad-version" "$test_commit" "$good_digest"
	set +e
	PATH="$temporary_root/path-ferret:$test_path" FERRET_INSTALL_CACHE="$cache_root" "$subject" probe >/dev/null 2>"$temporary_root/ferret-version"
	status=$?
	set -e
	[ "$status" -eq 125 ]
	grep -Fq 'invalid stable version' "$temporary_root/ferret-version"
	write_lock "$test_version" "short" "$good_digest"
	set +e
	PATH="$temporary_root/path-ferret:$test_path" FERRET_INSTALL_CACHE="$cache_root" "$subject" probe >/dev/null 2>"$temporary_root/ferret-commit"
	status=$?
	set -e
	[ "$status" -eq 125 ]
	grep -Fq 'invalid commit' "$temporary_root/ferret-commit"
	write_lock "$test_version" "$test_commit" "short"
	set +e
	PATH="$temporary_root/path-ferret:$test_path" FERRET_INSTALL_CACHE="$cache_root" "$subject" probe >/dev/null 2>"$temporary_root/ferret-digest"
	status=$?
	set -e
	[ "$status" -eq 125 ]
	grep -Fq 'invalid artifact digest' "$temporary_root/ferret-digest"
	write_lock "$test_version" "$test_commit" "$good_digest"
	rm -rf -- "$cache_root"
	[ ! -e "$temporary_root/path-ferret-called" ]
}

while IFS= read -r scenario; do
	echo "  $scenario"
	case "$scenario" in
	'./ferret installs and verifies the pinned FERRET before running it') run_install_and_verify ;;
	'./ferret refuses an unpinned fallback or a failed install') run_refuses_fallback_or_failed_install ;;
	'A missing, duplicated, or malformed pin makes ./ferret refuse with 125') run_pin_refusals_125 ;;
	*) exit 1 ;;
	esac
done <<EOF
$actual_scenarios
EOF

[ ! -e "$temporary_root/path-ferret-called" ]

echo "ferret bootstrap tests passed"
