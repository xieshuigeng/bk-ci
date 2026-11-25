#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
BAD_TEMPLATE="$ROOT/pipeline/ffmpeg-pipeline.bad-template.json"
trap 'rm -rf "$TMP" "$BAD_TEMPLATE"' EXIT
OUT="$TMP/ffmpeg-pipeline.json"

python3 "$ROOT/pipeline/render_pipeline.py" \
  --template "$ROOT/pipeline/ffmpeg-pipeline.template.json" \
  --project-id proj-test --project-code code-test --pipeline-id p-test \
  --artifactory-base-url http://artifactory.invalid:21920 \
  --gateway http://gateway.invalid:8080 \
  --build-image image.invalid/bkci:test \
  --output "$OUT"

python3 -m json.tool "$OUT" >/dev/null
if grep -qE '__|@file:|@base64:|172\.|p-8bb091809f5d4c04ac88fe7ef525f617|demotest|127\.0\.0\.1:5000/bkci/ci:jdk17|28ee946a59f64949a74f3dee40a1bda4|/data/bkci-local/ffmpeg-out' "$OUT"; then
  echo "FAIL: rendered pipeline contains an unresolved marker or forbidden literal"
  exit 1
fi

python3 - "$OUT" "$ROOT/scripts/build-in-container.sh" <<'PY'
import base64, json, re, sys
doc = json.load(open(sys.argv[1]))
text = doc["stages"][1]["containers"][0]["elements"][0]["script"]
expected = open(sys.argv[2], "rb").read()
m = re.search(r'INNER_BUILD_SCRIPT_B64="([^"]+)"', text)
assert m, "rendered script is missing INNER_BUILD_SCRIPT_B64"
assert base64.b64decode(m.group(1)) == expected, "inner script drift"
PY

# 5. unknown placeholder must fail without writing output
python3 - "$ROOT/pipeline/ffmpeg-pipeline.template.json" "$BAD_TEMPLATE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["name"] = "__UNKNOWN__"
with open(sys.argv[2], "w") as f:
    json.dump(d, f)
PY
BAD_OUT1="$TMP/unknown.json"
if python3 "$ROOT/pipeline/render_pipeline.py" \
  --template "$BAD_TEMPLATE" \
  --project-id proj-test --project-code code-test --pipeline-id p-test \
  --artifactory-base-url http://artifactory.invalid:21920 \
  --gateway http://gateway.invalid:8080 \
  --build-image image.invalid/bkci:test \
  --output "$BAD_OUT1" >/dev/null 2>&1; then
  echo "FAIL: unknown placeholder should have failed"; exit 1
fi
[ ! -e "$BAD_OUT1" ] || { echo "FAIL: unknown placeholder wrote output"; exit 1; }

# 6. forbidden CLI value must fail and remove a stale output file
BAD_OUT2="$TMP/forbidden.json"
echo stale > "$BAD_OUT2"
if python3 "$ROOT/pipeline/render_pipeline.py" \
  --template "$ROOT/pipeline/ffmpeg-pipeline.template.json" \
  --project-id demotest --project-code code-test --pipeline-id p-test \
  --artifactory-base-url http://artifactory.invalid:21920 \
  --gateway http://gateway.invalid:8080 \
  --build-image image.invalid/bkci:test \
  --output "$BAD_OUT2" >/dev/null 2>&1; then
  echo "FAIL: forbidden CLI value should have failed"; exit 1
fi
[ ! -e "$BAD_OUT2" ] || { echo "FAIL: stale output survived failed render"; exit 1; }

echo "render_pipeline_test: PASS"
