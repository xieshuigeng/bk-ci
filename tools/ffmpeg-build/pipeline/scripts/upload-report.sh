#!/bin/bash
set -euo pipefail
WS="${WORKSPACE:-${bkWorkspace:-/data/devops/workspace}}"
ART="${BK_CI_ARTIFACTORY_BASE_URL:-__ARTIFACTORY_BASE_URL__}"
GW="${devops_gateway:-__BK_CI_GATEWAY__}"; GW=${GW%/}
PID="${BK_CI_PROJECT_NAME:-__PROJECT_CODE__}"
PL="${BK_CI_PIPELINE_ID:-__PIPELINE_ID__}"
BID=${BK_CI_BUILD_ID:?}
AID=${devops_agent_id:-}
ASK=${devops_agent_secret_key:-}
VMSEQ=${devops_vm_seq_id:-1}
VMNAME=${devops_vm_name:-$AID}
EID=e-upload-report
f=""
for d in "$WS/ffmpeg-out-static" "$WS/alpine-rootfs/work/out"; do
  if [ -f "$d/build-report.txt" ]; then f="$d/build-report.txt"; break; fi
done
[ -n "$f" ] || { echo "ERROR: build-report.txt not found"; exit 1; }
bn=$(basename "$f")
code=$(curl -sS -o /tmp/rp.json -w '%{http_code}' -X POST "$ART/api/build/artifactories/file/archive?fileType=BK_REPORT&customFilePath=$EID" -H "X-DEVOPS-PROJECT-ID:$PID" -H "X-DEVOPS-PIPELINE-ID:$PL" -H "X-DEVOPS-BUILD-ID:$BID" -H "X-DEVOPS-AGENT-ID:$AID" -H "X-DEVOPS-AGENT-SECRET-KEY:$ASK" -H "X-DEVOPS-VM-SID:$VMSEQ" -H "X-DEVOPS-BUILD-TYPE:AGENT" -F "file=@$f;filename=$bn")
echo "http=$code"; cat /tmp/rp.json; echo
[ "$code" = "200" ] || exit 1
rc=$(curl -sS -o /tmp/rr.json -w '%{http_code}' -X POST "$GW/ms/process/api/build/reports/$EID?name=ffmpeg-r010-build-report&indexFile=$bn&reportType=INTERNAL" -H "X-DEVOPS-PROJECT-ID:$PID" -H "X-DEVOPS-PIPELINE-ID:$PL" -H "X-DEVOPS-BUILD-ID:$BID" -H "X-DEVOPS-AGENT-ID:$AID" -H "X-DEVOPS-AGENT-SECRET-KEY:$ASK" -H "X-DEVOPS-VM-SID:$VMSEQ" -H "X-DEVOPS-VM-NAME:$VMNAME" -H "X-DEVOPS-BUILD-TYPE:DOCKER")
echo "report_http=$rc"; cat /tmp/rr.json; echo
[ "$rc" = "200" ] || exit 1
