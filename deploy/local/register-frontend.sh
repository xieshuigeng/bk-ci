#!/usr/bin/env bash
# 将 bkci-frontend 容器注册到 Consul（网关 lua/nginx 通过 Consul DNS frontend.service.consul 解析前端）。
# 何时执行: docker compose up/recreate frontend 之后（IP 变化需重新注册），以及启动 gateway 之前。
set -euo pipefail
cd "$(dirname "$0")"

FE_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' bkci-frontend 2>/dev/null || true)
if [[ -z "$FE_IP" ]]; then
  echo "bkci-frontend 未运行或无 IP，先执行: docker compose up -d frontend" >&2
  exit 1
fi

curl -sf -X PUT http://localhost:8500/v1/agent/service/register \
  -d "{\"Name\":\"frontend\",\"Address\":\"$FE_IP\",\"Port\":80,\"Tags\":[\"devops\"]}" \
  || { echo "consul 8500 未就绪，稍后重试" >&2; exit 1; }

echo "registered frontend -> $FE_IP:80"
echo "若网关已在运行: docker compose restart gateway"
curl -s "http://localhost:8500/v1/health/service/frontend?passing=true"
echo
