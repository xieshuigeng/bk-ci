#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/ffmpeg-pipeline.json"

python3 "$ROOT/pipeline/render_pipeline.py" \
  --template "$ROOT/pipeline/ffmpeg-pipeline.template.json" \
  --project-id proj-test --project-code code-test --pipeline-id p-test \
  --artifactory-base-url http://artifactory.invalid:21920 \
  --gateway http://gateway.invalid:8080 \
  --build-image image.invalid/bkci:test \
  --output "$OUT"

python3 -m json.tool "$OUT" >/dev/null
! grep -qE '__|@file:|@base64:|172\.|p-8bb091809f5d4c04ac88fe7ef525f617|demotest' "$OUT"

python3 - "$OUT" "$ROOT/scripts/build-in-container.sh" <<'PY'
import base64, json, re, sys
doc = json.load(open(sys.argv[1]))
text = doc["stages"][1]["containers"][0]["elements"][0]["script"]
expected = open(sys.argv[2], "rb").read()
m = re.search(r'INNER_BUILD_SCRIPT_B64="([^"]+)"', text)
assert m, "rendered script is missing INNER_BUILD_SCRIPT_B64"
assert base64.b64decode(m.group(1)) == expected, "inner script drift"
PY
echo "render_pipeline_test: PASS"
