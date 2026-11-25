#!/bin/bash
set -euo pipefail
WS="${WORKSPACE:-${bkWorkspace:-/data/devops/workspace}}"
ART="${BK_CI_ARTIFACTORY_BASE_URL:-__ARTIFACTORY_BASE_URL__}"
PID="${BK_CI_PROJECT_NAME:-__PROJECT_CODE__}"
PL="${BK_CI_PIPELINE_ID:-__PIPELINE_ID__}"
BID=${BK_CI_BUILD_ID:?}
AID=${devops_agent_id:-}
ASK=${devops_agent_secret_key:-}
VMSEQ=${devops_vm_seq_id:-1}
SRC1="$WS/ffmpeg-out-static"
SRC2="$WS/alpine-rootfs/work/out"
seen=" "
uploaded=0
for f in "$SRC1/build-report.txt" "$SRC1/checksums.txt" "$SRC1"/ffmpeg-*-musl-static.tar.gz "$SRC2/build-report.txt" "$SRC2/checksums.txt" "$SRC2"/ffmpeg-*-musl-static.tar.gz; do
  [ -f "$f" ] || continue
  bn=$(basename "$f")
  case "$seen" in *" $bn "*) continue;; esac
  seen="$seen$bn "
  echo "uploading $bn from $f"
  code=$(curl -sS -o /tmp/up.json -w '%{http_code}' -X POST "$ART/api/build/artifactories/file/archive?fileType=BK_CUSTOM&customFilePath=/ffmpeg-r010" -H "X-DEVOPS-PROJECT-ID:$PID" -H "X-DEVOPS-PIPELINE-ID:$PL" -H "X-DEVOPS-BUILD-ID:$BID" -H "X-DEVOPS-AGENT-ID:$AID" -H "X-DEVOPS-AGENT-SECRET-KEY:$ASK" -H "X-DEVOPS-VM-SID:$VMSEQ" -H "X-DEVOPS-BUILD-TYPE:AGENT" -F "file=@$f;filename=$bn")
  echo "http=$code"; cat /tmp/up.json; echo
  [ "$code" = "200" ] || exit 1
  uploaded=$((uploaded+1))
done
echo "uploaded=$uploaded files"
[ "$uploaded" -ge 3 ] || { echo "ERROR: expected at least 3 artifacts"; exit 1; }
