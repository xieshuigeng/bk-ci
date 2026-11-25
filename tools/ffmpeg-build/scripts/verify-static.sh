#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$SCRIPT_DIR/out}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

for name in ffmpeg ffprobe ffplay; do
  bin="$OUT_DIR/bin/$name"
  [ -x "$bin" ] || fail "missing or non-executable: $bin"

  file_out="$(file -b "$bin" 2>&1 || true)"
  case "$file_out" in
    *"statically linked"*) ;;
    *) fail "not statically linked: $bin ($file_out)" ;;
  esac

  ldd_out="$(ldd "$bin" 2>&1 || true)"
  case "$ldd_out" in
    *"not a dynamic executable"*) ;;
    *) fail "dynamic executable: $bin ($ldd_out)" ;;
  esac

  version_out="$("$bin" -version 2>&1 | head -n 1 || true)"
  case "$version_out" in
    *n9.1*) ;;
    *) fail "wrong version: $bin ($version_out)" ;;
  esac
done

if [ -f "$OUT_DIR/checksums.txt" ]; then
  if (cd "$OUT_DIR" && sha256sum -c --quiet checksums.txt) >/dev/null 2>&1; then
    :
  elif (cd "$OUT_DIR/bin" && sha256sum -c --quiet ../checksums.txt) >/dev/null 2>&1; then
    :
  else
    fail "checksum verification failed"
  fi
fi

echo "VERIFY_OK"
