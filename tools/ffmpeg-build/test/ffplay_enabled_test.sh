#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/../scripts/build-in-container.sh"
source <(sed -n '/^# BEGIN ffplay_enabled$/,/^# END ffplay_enabled$/p' "$BUILD_SCRIPT")

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/bin"

# FFmpeg upstream writes CONFIG_FFPLAY=yes
printf '%s\n' 'CONFIG_FFPLAY=yes' > "$TMP_DIR/config.mak"
ffplay_enabled "$TMP_DIR/config.mak" "$TMP_DIR/bin" || { echo "FAIL: CONFIG_FFPLAY=yes not accepted"; exit 1; }
echo "PASS: CONFIG_FFPLAY=yes accepted"

# Older/other generators may write CONFIG_FFPLAY=1
printf '%s\n' 'CONFIG_FFPLAY=1' > "$TMP_DIR/config.mak"
ffplay_enabled "$TMP_DIR/config.mak" "$TMP_DIR/bin" || { echo "FAIL: CONFIG_FFPLAY=1 not accepted"; exit 1; }
echo "PASS: CONFIG_FFPLAY=1 accepted"

# A built ffplay binary is sufficient evidence even without config line
: > "$TMP_DIR/config.mak"
printf '#!/bin/sh\n' > "$TMP_DIR/bin/ffplay"
chmod +x "$TMP_DIR/bin/ffplay"
ffplay_enabled "$TMP_DIR/config.mak" "$TMP_DIR/bin" || { echo "FAIL: existing ffplay binary not accepted"; exit 1; }
echo "PASS: existing ffplay binary accepted"

# Neither config nor binary means ffplay is not enabled
rm -f "$TMP_DIR/bin/ffplay"
if ffplay_enabled "$TMP_DIR/config.mak" "$TMP_DIR/bin"; then
  echo "FAIL: missing ffplay config and binary accepted"
  exit 1
fi
echo "PASS: missing ffplay config and binary rejected"
