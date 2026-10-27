#!/usr/bin/env bash
# 补齐原子/分类图标静态文件（等价官方 bk-ci-setup.sh 的 setup_ci_artifactory 复制步骤）。
# 何时执行: 首次部署后、或 bkci-artifactory 容器/数据卷重建后。幂等，可重复执行。
#
# 两类缺失:
#   1) 内置 logo（?filePath=/file/png/*.png）: 镜像内置于容器内 /data/workspace/support-files/file,
#      官方安装时复制进存储根; 本地 compose 未跑官方安装脚本, 故全部 500。
#   2) zip 直装插件的 logo（/file/download/%252F...%252F$<hash>.<hash>.png）: 元数据里的 URL 由官方
#      发布流程生成（双重 URL 编码, 解码后为 //file/$<hash>.<hash>.png）, 本地
#      /api/op/pipeline/atom/deploy 不上传图标文件 → 用 $ATOMS_DIR/<atomCode>.zip 包内图片按解码后文件名落位。
#
# 无法补齐: codeTapdWebHookTrigger / codeScmGitWebHookTrigger 的 tapdTrigger.png、scmGitTrigger.png
# 社区包内未附带（SaaS 专属）, 校验时仍会是 500。
#
# 不用 set -e: 本脚本按条目独立容错, 单项失败不应中断其余补齐。
set -uo pipefail
cd "$(dirname "$0")"

GW=${GW:-http://localhost:8080}
ATOMS_DIR=${ATOMS_DIR:-/tmp/opencode/atoms}
STORE_PORT=${STORE_PORT:-21918}
DEVOPS_UID=${DEVOPS_UID:-admin}
FE_TMP=/tmp/opencode/atom-logos

BASE=$(grep -m1 archiveLocalBasePath rendered/etc/ci/application-artifactory.yml | awk '{print $2}')
[ -n "$BASE" ] || { echo '未能从 rendered/etc/ci/application-artifactory.yml 解析 archiveLocalBasePath' >&2; exit 1; }
echo "artifactory 存储根: $BASE"

# 输出 "<atomCode>\t<存储根/file 下的目标文件名>"; 只处理插件型 logo（无 ?filePath= 查询串）
plugin_logo_targets () {
  docker exec bkci-store curl -sS "http://127.0.0.1:$STORE_PORT/api/op/pipeline/atom/?page=1&pageSize=100" \
      -H "X-DEVOPS-UID: $DEVOPS_UID" \
    | python3 -c '
import json, sys, urllib.parse as up
seen = set()
for r in json.load(sys.stdin)["data"]["records"]:
    url = r.get("logoUrl") or ""
    if not url or "?" in url:
        continue                      # 带 ?filePath= 的是内置静态 logo, 由第 1 步整目录复制解决
    path = up.unquote(up.unquote(up.urlsplit(url).path))
    name = path.split("/")[-1]
    key = (r["atomCode"], name)
    if name and key not in seen:
        seen.add(key)
        print("%s\t%s" % (r["atomCode"], name))
'
}

in_storage () { local got; got=$(docker exec bkci-artifactory sh -c "test -f '$1' && echo yes" 2>/dev/null); [ "$got" = yes ]; }

echo '[1/3] 内置 logo 静态文件'
# 层级注意: 目标是 <存储根>/file/png/*.png, 复制 file 目录的"内容", 浅一层会仍然 500
docker exec bkci-artifactory sh -c \
  "mkdir -p '$BASE/file' && cp -rn /data/workspace/support-files/file/. '$BASE/file/' && echo '  完成(已存在的不覆盖)'"

echo '[2/3] zip 直装插件 logo'
mkdir -p "$FE_TMP"
plugin_logo_targets | while read -r code target; do
  if in_storage "$BASE/file/$target"; then
    printf '  %-30s 已存在, 跳过\n' "$code"
    continue
  fi
  zip="$ATOMS_DIR/$code.zip"
  if [ ! -f "$zip" ]; then
    printf '  %-30s 缺安装包 %s, 未补齐\n' "$code" "$zip"
    continue
  fi
  pngs=$(unzip -l "$zip" | awk '{print $NF}' | grep -E '\.png$' || true)
  src=$(printf '%s\n' "$pngs" | grep -i logo || true)
  [ -n "$src" ] || src=$(printf '%s\n' "$pngs" | head -1)
  if [ -z "$src" ]; then
    printf '  %-30s 安装包内无 png, 未补齐\n' "$code"
    continue
  fi
  unzip -p "$zip" "$src" > "$FE_TMP/$code.png"
  docker cp "$FE_TMP/$code.png" "bkci-artifactory:$BASE/file/$target"
  printf '  %-30s %s -> file/%s\n' "$code" "${src##*/}" "$target"
done

echo '[3/3] 校验（经网关, 期望全部 200）'
docker exec bkci-store curl -sS "http://127.0.0.1:$STORE_PORT/api/op/pipeline/atom/?page=1&pageSize=100" \
    -H "X-DEVOPS-UID: $DEVOPS_UID" \
  | python3 -c '
import json, sys
seen = set()
for r in json.load(sys.stdin)["data"]["records"]:
    url = r.get("logoUrl")
    if url and url not in seen:
        seen.add(url)
        print(r["atomCode"], url)
' | while read -r code url; do
  printf '  %-30s %s\n' "$code" \
    "$(curl -s -o /dev/null -w '%{http_code}' -H "X-DEVOPS-UID: $DEVOPS_UID" -H 'X-DEVOPS-TOKEN: devops' "$GW$url")"
done
if in_storage "$BASE/file/png/SERVER.png"; then
  printf '  %-30s %s\n' '分类图标 SERVER' \
    "$(curl -s -o /dev/null -w '%{http_code}' -H "X-DEVOPS-UID: $DEVOPS_UID" -H 'X-DEVOPS-TOKEN: devops' \
       "$GW/ms/artifactory/api/user/artifactories/file/download?filePath=%2Ffile%2Fpng%2FSERVER.png&logo=true")"
fi
