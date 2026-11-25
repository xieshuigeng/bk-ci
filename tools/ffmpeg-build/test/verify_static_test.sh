#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY="$ROOT/scripts/verify-static.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

make_fake_tools() {
  mkdir -p "$TMP/fakebin"
  printf '#!/bin/sh\necho "ELF 64-bit LSB executable, x86-64, statically linked"\n' > "$TMP/fakebin/file"
  printf '#!/bin/sh\necho "not a dynamic executable"\n' > "$TMP/fakebin/ldd"
  chmod +x "$TMP/fakebin/file" "$TMP/fakebin/ldd"
}

make_bins() {
  local version="$1"
  mkdir -p "$TMP/fixture/bin"
  for b in ffmpeg ffprobe ffplay; do
    printf '#!/bin/sh\necho "ffmpeg version %s"\n' "$version" > "$TMP/fixture/bin/$b"
    chmod +x "$TMP/fixture/bin/$b"
  done
}

expect_fail() {
  local name="$1"; shift
  if PATH="$TMP/fakebin:$PATH" "$VERIFY" "$@" >/dev/null 2>&1; then
    echo "FAIL: $name should have failed"; exit 1
  fi
}

# 1. missing output directory / missing binaries must fail with a clear error
ERR="$TMP/missing.err"
if PATH="$TMP/fakebin:$PATH" "$VERIFY" "$TMP/does-not-exist" >/dev/null 2>"$ERR"; then
  echo "FAIL: missing files should have failed"; exit 1
fi
grep -q 'ERROR: missing or non-executable:' "$ERR" || {
  echo "FAIL: missing files did not report a clear error"; cat "$ERR"; exit 1
}

# 2. dynamic-looking file must be rejected even with correct version
make_fake_tools
make_bins n9.1
printf '#!/bin/sh\necho "ELF 64-bit LSB executable, dynamically linked"\n' > "$TMP/fakebin/file"
expect_fail "dynamic link" "$TMP/fixture"

# 3. wrong version must be rejected even when static checks are stubbed to pass
make_fake_tools
make_bins n8.0
expect_fail "wrong version" "$TMP/fixture"

# 4. happy path with stubbed static checks
make_fake_tools
make_bins n9.1
PATH="$TMP/fakebin:$PATH" "$VERIFY" "$TMP/fixture" | grep -q '^VERIFY_OK$'

# 5. checksums.txt with bare binary names must be resolved from bin/
make_fake_tools
make_bins n9.1
(cd "$TMP/fixture/bin" && sha256sum ffmpeg ffprobe ffplay > ../checksums.txt)
PATH="$TMP/fakebin:$PATH" "$VERIFY" "$TMP/fixture" | grep -q '^VERIFY_OK$'

# 6. empty checksums.txt must fail
: > "$TMP/fixture/checksums.txt"
expect_fail "empty checksums" "$TMP/fixture"

# 7. incomplete checksums.txt must fail
(cd "$TMP/fixture/bin" && sha256sum ffmpeg ffprobe ffplay > ../checksums.txt)
grep -v '  ffplay$' "$TMP/fixture/checksums.txt" > "$TMP/checksums.tmp"
mv "$TMP/checksums.tmp" "$TMP/fixture/checksums.txt"
expect_fail "incomplete checksums" "$TMP/fixture"

# 8. corrupted checksum must fail while all three names remain present
(cd "$TMP/fixture/bin" && sha256sum ffmpeg ffprobe ffplay > ../checksums.txt)
python3 - "$TMP/fixture/checksums.txt" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines()
lines[0] = '0' * 64 + '  ffmpeg'
open(p, 'w').write('\n'.join(lines) + '\n')
PY
expect_fail "checksum mismatch" "$TMP/fixture"

echo "verify_static_test: PASS"
