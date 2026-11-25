#!/usr/bin/env bash
# 将本地部署所需的静态图标幂等播种到 artifactory 存储根。
# 用法：ARTIFACTORY_BASE=/path/to/artifactory [BUILTIN_SRC=...] [EXTRA_SRC=...] seed-artifactory-icons.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${ARTIFACTORY_BASE:-}" ]]; then
    conf=""
    for candidate in \
        /etc/bkci/conf/application-artifactory.yml \
        "$SCRIPT_DIR/rendered/etc/ci/application-artifactory.yml" \
        "$SCRIPT_DIR/../rendered/etc/ci/application-artifactory.yml"
    do
        if [[ -f "$candidate" ]]; then
            conf="$candidate"
            break
        fi
    done
    if [[ -z "$conf" ]]; then
        echo "seed-artifactory-icons: cannot find application-artifactory.yml" >&2
        exit 1
    fi
    ARTIFACTORY_BASE="$(grep -m1 -E '^[[:space:]]*archiveLocalBasePath:' "$conf" | awk '{print $2}' || true)"
    if [[ -z "$ARTIFACTORY_BASE" ]]; then
        echo "seed-artifactory-icons: archiveLocalBasePath is empty in $conf" >&2
        exit 1
    fi
fi

BUILTIN_SRC="${BUILTIN_SRC:-/data/workspace/support-files/file}"
EXTRA_SRC="${EXTRA_SRC:-$SCRIPT_DIR/icon-assets}"

if [[ ! -d "$EXTRA_SRC" ]]; then
    echo "seed-artifactory-icons: missing extra icon source: $EXTRA_SRC" >&2
    exit 1
fi

mkdir -p "$ARTIFACTORY_BASE/file"

if [[ -d "$BUILTIN_SRC" ]]; then
    cp -r --update=none "$BUILTIN_SRC/." "$ARTIFACTORY_BASE/file/"
else
    echo "seed-artifactory-icons: skip missing builtin icon source: $BUILTIN_SRC"
fi
cp -r --update=none "$EXTRA_SRC/." "$ARTIFACTORY_BASE/file/"

printf 'seed-artifactory-icons: %s files under %s/file\n' \
    "$(find "$ARTIFACTORY_BASE/file" -type f | wc -l)" "$ARTIFACTORY_BASE"
