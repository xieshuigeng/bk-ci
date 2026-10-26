#!/bin/bash
# 用法: /entrypoint.sh <ms-name>   (如 process / project / auth)
set -e
MS_NAME="$1"
if [ -z "$MS_NAME" ]; then echo "usage: entrypoint.sh <ms-name>" >&2; exit 2; fi
cd "/data/workspace/${MS_NAME}" || { echo "no such service dir: ${MS_NAME}" >&2; exit 3; }
# service.env 提供 MAIN_CLASS / CLASSPATH / MEM_OPTS / JAVA_TOOL_OPTIONS
# set -a: service.env 中的 JAVA_TOOL_OPTIONS 等需以环境变量形式传给 java 进程
set -a
source ./service.env
set +a
unset SPRING_CONFIG_LOCATION   # 由 -D 显式指定，避免 env 覆盖歧义
# 配置加载顺序与官方 bk-ci-setup.sh 一致: 模块自带 application.yml -> common.yml -> 模块 application-<ms>.yml
# engine 模块在发行包内没有独立的 application-<ms>.yml (其默认配置在模块自带 application.yml 中, name=engine/port=21917)。
# 仅挂载 common+application-<ms> 会导致 engine 启动失败; 补上模块本地 application.yml 即可对齐官方行为。
conf_files="file:./application.yml"
[ -f /etc/bkci/conf/common.yml ] && conf_files="$conf_files,file:/etc/bkci/conf/common.yml"
[ -f "/etc/bkci/conf/application-${MS_NAME}.yml" ] && conf_files="$conf_files,file:/etc/bkci/conf/application-${MS_NAME}.yml"
exec java ${MEM_OPTS:-} \
  -Dspring.application.name="${MS_NAME}" \
  -Dservice-suffix= \
  -Dspring.config.location="$conf_files" \
  -Dservice.log.dir=./logs/ \
  -Ddevops_gateway="${DEVOPS_GATEWAY:-http://localhost:8080}" \
  -Dbksvc="bk-ci-${MS_NAME}" \
  -classpath ".:lib/*" \
  ${MAIN_CLASS}
