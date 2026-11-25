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
  checksum_file="$OUT_DIR/checksums.txt"
  [ -s "$checksum_file" ] || fail "checksums.txt is empty: $checksum_file"

  layout=""
  for name in ffmpeg ffprobe ffplay; do
    count="$(awk -v n="$name" '$2 == n || $2 == "bin/" n { c++ } END { print c+0 }' "$checksum_file")"
    [ "$count" -eq 1 ] || fail "checksums.txt must contain exactly one entry for $name"

    if awk -v n="$name" '$2 == "bin/" n { found=1 } END { exit !found }' "$checksum_file"; then
      name_layout="bin"
    else
      name_layout="bare"
    fi
    if [ -z "$layout" ]; then
      layout="$name_layout"
    elif [ "$layout" != "$name_layout" ]; then
      fail "checksums.txt mixes bare and bin/ paths"
    fi
  done

  if [ "$layout" = "bin" ]; then
    (cd "$OUT_DIR" && sha256sum -c --quiet checksums.txt) >/dev/null 2>&1 \
      || fail "checksum verification failed"
  else
    (cd "$OUT_DIR/bin" && sha256sum -c --quiet ../checksums.txt) >/dev/null 2>&1 \
      || fail "checksum verification failed"
  fi
fi

echo "VERIFY_OK"
