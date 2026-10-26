#!/usr/bin/env bash
# 清理 Consul 中因容器重建而残留的旧服务实例。
# 用法: ./consul-cleanup.sh [--dry-run]
set -euo pipefail

CONSUL=${CONSUL:-http://127.0.0.1:8500}
DRY_RUN=0
[[ ${1:-} == "--dry-run" ]] && DRY_RUN=1

declare -A CONTAINER=(
  [artifactory]=bkci-artifactory [auth]=bkci-auth [dispatch]=bkci-dispatch
  [engine]=bkci-engine [environment]=bkci-environment [frontend]=bkci-frontend
  [log]=bkci-log [metrics]=bkci-metrics [misc]=bkci-misc [notify]=bkci-notify
  [openapi]=bkci-openapi [process]=bkci-process [project]=bkci-project
  [quality]=bkci-quality [repository]=bkci-repository [store]=bkci-store
  [ticket]=bkci-ticket [websocket]=bkci-websocket
  [bkrepo-auth]=bkci-bkrepo-auth [bkrepo-repository]=bkci-bkrepo-repository
)

services_json=$(curl -fsS "$CONSUL/v1/agent/services")
removed=0

for svc in "${!CONTAINER[@]}"; do
  ctr=${CONTAINER[$svc]}
  ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$ctr" 2>/dev/null || true)
  if [[ -z "$ip" ]]; then
    echo "skip $svc: container $ctr not running"
    continue
  fi
  # id<TAB>address 列表；保留第一个与当前容器 IP 匹配的实例
  mapfile -t ids < <(SERVICES_JSON="$services_json" python3 - "$svc" "$ip" << 'PY'
import json, os, sys
svc, ip = sys.argv[1], sys.argv[2]
data = json.loads(os.environ["SERVICES_JSON"])
kept = False
for sid, item in data.items():
    if item.get('Service') != svc:
        continue
    if item.get('Address') == ip and not kept:
        kept = True
        continue
    print(sid)
PY
)
  for sid in "${ids[@]}"; do
    [[ -z "$sid" ]] && continue
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "would deregister $sid ($svc)"
    else
      curl -fsS -X PUT "$CONSUL/v1/agent/service/deregister/$sid" >/dev/null
      echo "deregistered $sid ($svc)"
    fi
    removed=$((removed + 1))
  done
done

if [[ $DRY_RUN -eq 1 ]]; then echo "done: $removed stale instance(s) (dry-run)"; else echo "done: $removed stale instance(s) removed"; fi
