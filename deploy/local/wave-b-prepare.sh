#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_ROOT="${BKCI_LOCAL_DATA_ROOT:-/data/bkci-local}"
SOURCE_IMAGE="${BKCI_CI_SOURCE_IMAGE:-bkci-local/ci:latest}"
TARGET_IMAGE="${BKCI_CI_TARGET_IMAGE:-bkci/ci:latest}"
BACKEND_IMAGE="${BKCI_BACKEND_IMAGE:-bkci-local/bkci-backend:v4.2.0-rc.7}"

if ! docker image inspect "${SOURCE_IMAGE}" >/dev/null 2>&1; then
    docker build -t "${SOURCE_IMAGE}" -f "${ROOT_DIR}/ci-build.Dockerfile" "${ROOT_DIR}"
fi
docker tag "${SOURCE_IMAGE}" "${TARGET_IMAGE}"

install -d \
    "${DATA_ROOT}/agent-package/script" \
    "${DATA_ROOT}/agent-package/jar" \
    "${DATA_ROOT}/gateway-files/jar" \
    "${DATA_ROOT}/gateway-files/prod/jar" \
    "${DATA_ROOT}/docker/workspace" \
    "${DATA_ROOT}/docker/apps" \
    "${DATA_ROOT}/docker/common_env" \
    "${DATA_ROOT}/docker/share/project" \
    "${DATA_ROOT}/docker/link" \
    "${DATA_ROOT}/docker/overlayfs" \
    "${DATA_ROOT}/docker/thirdparty/maven_repo" \
    "${DATA_ROOT}/docker/thirdparty/npm_prefix" \
    "${DATA_ROOT}/docker/thirdparty/npm_cache" \
    "${DATA_ROOT}/docker/thirdparty/gradle_caches" \
    "${DATA_ROOT}/docker/thirdparty/go_cache" \
    "${DATA_ROOT}/docker/thirdparty/.ivy2" \
    "${DATA_ROOT}/docker/thirdparty/sbt_cache" \
    "${DATA_ROOT}/docker/thirdparty/yarn_cache" \
    "${DATA_ROOT}/docker/thirdparty/ccache" \
    "${DATA_ROOT}/logs/ci/docker"

CONTAINER_ID="$(docker create "${BACKEND_IMAGE}")"
cleanup() {
    docker rm -f "${CONTAINER_ID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker cp "${CONTAINER_ID}:/data/workspace/agent-package/script/." "${DATA_ROOT}/agent-package/script/"
docker cp "${CONTAINER_ID}:/data/workspace/agent-package/jar/worker-agent.jar" "${DATA_ROOT}/agent-package/jar/worker-agent.jar"

chmod 0755 "${DATA_ROOT}/agent-package/script/init.sh" "${DATA_ROOT}/agent-package/script/docker_init.sh"
install -m 0644 "${DATA_ROOT}/agent-package/script/docker_init.sh" "${DATA_ROOT}/gateway-files/docker_init.sh"
install -m 0644 "${DATA_ROOT}/agent-package/jar/worker-agent.jar" "${DATA_ROOT}/gateway-files/jar/worker-agent.jar"
install -m 0644 "${DATA_ROOT}/agent-package/script/docker_init.sh" "${DATA_ROOT}/gateway-files/prod/docker_init.sh"
install -m 0644 "${DATA_ROOT}/agent-package/jar/worker-agent.jar" "${DATA_ROOT}/gateway-files/prod/jar/worker-agent.jar"

printf 'prepared %s\n' "${DATA_ROOT}"
