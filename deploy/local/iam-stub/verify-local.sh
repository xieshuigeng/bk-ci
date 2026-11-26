#!/usr/bin/env bash
# 本地 IAM/ITSM 桩端到端冒烟验收（在宿主机执行，桩映射到 localhost:8081）
set -euo pipefail

BASE="${IAM_STUB_BASE_URL:-http://localhost:8081}"
SYSTEM="bk_ci_rbac"

fail() { echo "FAIL: $1" >&2; exit 1; }

echo "== 1/10 IAM token 信封 =="
token_body=$(curl -fsS "$BASE/api/v1/model/systems/$SYSTEM/token") || fail "token endpoint unreachable: $BASE/api/v1/model/systems/$SYSTEM/token"
echo "$token_body" | grep -q '"code":0' || fail "token envelope code is not numeric 0: $token_body"
echo "$token_body" | grep -q '"token":"stub-token"' || fail "token payload missing: $token_body"
echo "PASS: token envelope"

echo "== 2/10 IAM 组列表非空 =="
groups_body=$(curl -fsS "$BASE/api/v2/open/management/systems/$SYSTEM/grade_managers/1001/groups/") || fail "group list unreachable"
echo "$groups_body" | grep -Eq '"count":[1-9]' || fail "group list is empty: $groups_body"
echo "PASS: group list"

echo "== 3/10 两个 iframe 页面含工单 =="
sample=$(curl -fsS -X POST -H 'Content-Type: application/json' \
  -d '{"name":"verify-demo","applicant":"verify-user"}' \
  "$BASE/api/v2/open/management/systems/$SYSTEM/grade_managers/-/applications/") || fail "sample application creation failed"
echo "$sample" | grep -q '"sn":"STUB-' || fail "sample application has no STUB sn: $sample"
apply_html=$(curl -fsS "$BASE/iam-stub/apply") || fail "apply page unreachable: $BASE/iam-stub/apply"
echo "$apply_html" | grep -q 'STUB-' || fail "apply page has no application row"
itsm_html=$(curl -fsS "$BASE/itsm-stub/") || fail "itsm page unreachable: $BASE/itsm-stub/"
echo "$itsm_html" | grep -q 'STUB-' || fail "itsm page has no ticket row"
echo "PASS: iframe pages"

echo "== 4/10 ITSM token verify =="
verify_body=$(curl -fsS -X POST -H 'Content-Type: application/json' -d '{"token":"stub-token"}' "$BASE/token/verify/") || fail "itsm token verify unreachable: $BASE/token/verify/"
echo "$verify_body" | grep -q '"is_passed":true' || fail "itsm token verify not passed: $verify_body"
echo "PASS: itsm token verify"

echo "== 5/10 网关用户态 API 免 bk_token 可用 =="
gw_body=$(curl -fsS 'http://localhost:8080/ms/project/api/user/projects?enabled=true') || fail "gateway user API unreachable"
echo "$gw_body" | grep -q '"code":0' || fail "gateway user API error: $gw_body"
echo "PASS: gateway user API"

echo "== 6/10 项目列表含本地预置项目 =="
echo "$gw_body" | grep -Eq '"PROJECT_CODE":"[^"]+"|"projectCode":"[^"]+"' || fail "project list empty: $gw_body"
echo "PASS: project list"

echo "== 7/10 申请权限接口返回用户组（用户信息已同步）=="
apply_groups=$(curl -fsS -X POST -H 'Content-Type: application/json' \
  -d '{"page":1,"pageSize":30,"projectId":"demotest"}' \
  'http://localhost:8080/ms/auth/api/user/auth/apply/demotest/listGroups') || fail "listGroups API unreachable"
echo "$apply_groups" | grep -q '"status":0' || fail "listGroups returned error: $apply_groups"
echo "$apply_groups" | grep -Eq '"count":[1-9]' || fail "listGroups has no groups: $apply_groups"
echo "PASS: listGroups"

echo "== 8/10 iframe 通过同源网关可达 =="
for p in /iam-stub/apply /itsm-stub/; do
  html=$(curl -fsS "http://localhost:8080$p") || fail "same-origin iframe page unreachable: $p"
  echo "$html" | grep -q '<title>' || fail "same-origin iframe page has no title: $p"
done
echo "PASS: same-origin iframes"

echo "== 9/10 前端 iframe 前缀为运行时同源绝对地址 =="
# IAM-Iframe 组件用 new URL(urlPerfix + path)，只接受绝对 URL；
# 相对路径会抛 Invalid URL，写死 localhost 会在跨机访问时拒绝连接。
for p in /permission/my-approval /console/permission/my-approval; do
  html=$(curl -fsS "http://localhost:8080$p") || fail "frontend page unreachable: $p"
  echo "$html" | grep -q 'location.origin' || fail "$p iframe prefix is not runtime same-origin: $(echo "$html" | grep -oE 'BK_(IAM|ITSM)_URL_PREFIX[^,;}]{0,60}' | head -2)"
  echo "$html" | grep -q 'localhost:8081' && fail "$p still hardcodes localhost:8081"
done
echo "PASS: runtime same-origin prefixes"

echo "== 10/10 HTML 不缓存（避免旧 localhost 前缀被浏览器复用）=="
cache_header=$(curl -sI 'http://localhost:8080/permission/my-approval' | grep -i '^cache-control:') || fail "no cache-control header"
echo "$cache_header" | grep -qi 'no-store' || fail "HTML cache-control is not no-store: $cache_header"
echo "PASS: no-store HTML"

echo "ALL PASS"
