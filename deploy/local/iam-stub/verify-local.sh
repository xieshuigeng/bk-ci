#!/usr/bin/env bash
# 本地 IAM/ITSM 桩端到端冒烟验收（在宿主机执行，桩映射到 localhost:8081）
set -euo pipefail

BASE="${IAM_STUB_BASE_URL:-http://localhost:8081}"
SYSTEM="bk_ci_rbac"

fail() { echo "FAIL: $1" >&2; exit 1; }

echo "== 1/4 IAM token 信封 =="
token_body=$(curl -fsS "$BASE/api/v1/model/systems/$SYSTEM/token") || fail "token endpoint unreachable: $BASE/api/v1/model/systems/$SYSTEM/token"
echo "$token_body" | grep -q '"code":0' || fail "token envelope code is not numeric 0: $token_body"
echo "$token_body" | grep -q '"token":"stub-token"' || fail "token payload missing: $token_body"
echo "PASS: token envelope"

echo "== 2/4 IAM 组列表非空 =="
groups_body=$(curl -fsS "$BASE/api/v2/open/management/systems/$SYSTEM/grade_managers/1001/groups/") || fail "group list unreachable"
echo "$groups_body" | grep -Eq '"count":[1-9]' || fail "group list is empty: $groups_body"
echo "PASS: group list"

echo "== 3/4 两个 iframe 页面含工单 =="
sample=$(curl -fsS -X POST -H 'Content-Type: application/json' \
  -d '{"name":"verify-demo","applicant":"verify-user"}' \
  "$BASE/api/v2/open/management/systems/$SYSTEM/grade_managers/-/applications/") || fail "sample application creation failed"
echo "$sample" | grep -q '"sn":"STUB-' || fail "sample application has no STUB sn: $sample"
apply_html=$(curl -fsS "$BASE/iam-stub/apply") || fail "apply page unreachable: $BASE/iam-stub/apply"
echo "$apply_html" | grep -q 'STUB-' || fail "apply page has no application row"
itsm_html=$(curl -fsS "$BASE/itsm-stub/") || fail "itsm page unreachable: $BASE/itsm-stub/"
echo "$itsm_html" | grep -q 'STUB-' || fail "itsm page has no ticket row"
echo "PASS: iframe pages"

echo "== 4/4 ITSM token verify =="
verify_body=$(curl -fsS -X POST -H 'Content-Type: application/json' -d '{"token":"stub-token"}' "$BASE/token/verify/") || fail "itsm token verify unreachable: $BASE/token/verify/"
echo "$verify_body" | grep -q '"is_passed":true' || fail "itsm token verify not passed: $verify_body"
echo "PASS: itsm token verify"

echo "ALL PASS"
