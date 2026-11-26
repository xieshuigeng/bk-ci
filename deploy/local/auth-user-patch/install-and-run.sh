#!/usr/bin/env bash
# 在 auth 容器启动时把本地 DeptService 补丁编译进 lib/，然后照常启动 auth。
# 只影响本地容器，不修改镜像内的 bk-ci 业务 class/jar。
set -euo pipefail

src_dir=/opt/local-auth-patch/src/main/java
work_dir=/tmp/local-auth-user-patch
patch_jar=/data/workspace/auth/lib/local-auth-user-patch.jar

command -v javac >/dev/null || { echo 'javac not found in auth image' >&2; exit 1; }

rm -rf "$work_dir"
mkdir -p "$work_dir/classes"
# 源码含中文注释；不指定 -encoding 时 javac 会按 locale（镜像默认 US-ASCII）解析并报大量 unmappable character。
# shellcheck disable=SC2046
javac -encoding UTF-8 -cp '/data/workspace/auth/lib/*' -d "$work_dir/classes" $(find "$src_dir" -name '*.java')
jar cf "$patch_jar" -C "$work_dir/classes" .
echo "installed local auth patch: $patch_jar"

exec /bin/bash /entrypoint.sh auth
