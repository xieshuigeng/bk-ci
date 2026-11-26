#!/bin/sh
# 本地部署补丁（不属于 bk-ci 业务源码）：把渲染后的 iframe 前缀改成运行时同源绝对地址。
#
# devops-permission 的 IAM-Iframe 组件用 `new URL(urlPerfix + '/' + path)` 构造 iframe 地址，
# new URL 的单参数形式只接受绝对 URL：
#   - 写死 http://localhost:8081/...  -> 跨机访问时指向浏览器自身，iframe 报“拒绝连接”
#   - 改成相对路径 /iam-stub          -> new URL 抛 Invalid URL，页面空白
# 因此必须在浏览器运行时用 location.origin 拼出绝对地址。
set -e

for f in /data/workspace/frontend/*/index.html; do
  [ -f "$f" ] || continue
  sed -i \
    -e "s|BK_IAM_URL_PREFIX *= *'[^']*'|BK_IAM_URL_PREFIX = location.origin + '/iam-stub'|g" \
    -e 's|BK_IAM_URL_PREFIX *= *"[^"]*"|BK_IAM_URL_PREFIX = location.origin + "/iam-stub"|g' \
    -e "s|BK_ITSM_URL_PREFIX *= *'[^']*'|BK_ITSM_URL_PREFIX = location.origin + '/itsm-stub'|g" \
    -e 's|BK_ITSM_URL_PREFIX *= *"[^"]*"|BK_ITSM_URL_PREFIX = location.origin + "/itsm-stub"|g' \
    "$f"
done

grep -q "BK_ITSM_URL_PREFIX = location.origin + '/itsm-stub'" \
  /data/workspace/frontend/permission/index.html || {
    echo 'patch iframe prefix failed' >&2
    exit 1
  }
echo 'patched frontend iframe prefixes to runtime same-origin URLs'
