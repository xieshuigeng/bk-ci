#!/usr/bin/env bash
# 在 auth 容器启动时把本地 DeptService 补丁编译进 lib/，然后照常启动 auth。
# 只影响本地容器，不修改镜像内的 bk-ci 业务 class/jar。
set -euo pipefail

src_dir=/opt/local-auth-patch/src/main/java
work_dir=/tmp/local-auth-user-patch
patch_jar=/data/workspace/auth/lib/local-auth-user-patch.jar

rm -rf "$work_dir"
mkdir -p "$work_dir/classes"
# shellcheck disable=SC2046
javac -cp '/data/workspace/auth/lib/*' -d "$work_dir/classes" $(find "$src_dir" -name '*.java')
jar cf "$patch_jar" -C "$work_dir/classes" .
echo "installed local auth patch: $patch_jar"

exec /bin/bash /entrypoint.sh auth
