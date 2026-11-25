#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="$ROOT/pipeline/ffmpeg-pipeline.template.json"
S="$ROOT/pipeline/scripts"

for f in "$T" "$S/build-in-bkci.sh" "$S/upload-artifact.sh" "$S/upload-report.sh"; do
  [ -f "$f" ] || { echo "FAIL: missing $f"; exit 1; }
done

python3 -m json.tool "$T" >/dev/null
bash -n "$S/build-in-bkci.sh"
bash -n "$S/upload-artifact.sh"
bash -n "$S/upload-report.sh"

grep -q '@base64:scripts/build-in-container.sh' "$S/build-in-bkci.sh"
! grep -R -qE '172\.|p-8bb091809f5d4c04ac88fe7ef525f617|demotest|127\.0\.0\.1:5000/bkci/ci:jdk17|28ee946a59f64949a74f3dee40a1bda4' "$T" "$S"

python3 - "$T" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["projectId"] == "__PROJECT_ID__"
assert d["pipelineId"] == "__PIPELINE_ID__"
assert d["latestVersion"] == "__LATEST_VERSION__"
assert len(d["stages"]) == 2
els = d["stages"][1]["containers"][0]["elements"]
assert [e["id"] for e in els] == ["e-build", "e-upload-artifact", "e-upload-report"]
assert els[0]["script"] == "@file:pipeline/scripts/build-in-bkci.sh"
assert els[1]["script"] == "@file:pipeline/scripts/upload-artifact.sh"
assert els[2]["script"] == "@file:pipeline/scripts/upload-report.sh"
PY
echo "template_hygiene_test: PASS"
