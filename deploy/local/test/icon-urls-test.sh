#!/usr/bin/env bash
# 从运行中的本地库收集所有 artifactory 图标 URL，并逐个经网关校验 HTTP 200。
set -euo pipefail

mysql_query() {
    docker exec bkci-mysql mysql -uroot -proot123 -N -B -e "$1" 2>/dev/null
}

columns="$(mysql_query "SELECT CONCAT(TABLE_SCHEMA, '.', TABLE_NAME, '.', COLUMN_NAME) FROM information_schema.columns WHERE TABLE_SCHEMA LIKE 'devops%' AND LOWER(COLUMN_NAME) REGEXP 'icon|logo' ORDER BY 1")"

urls=""
while IFS= read -r column; do
    [[ -n "$column" ]] || continue
    schema="${column%%.*}"
    rest="${column#*.}"
    table="${rest%%.*}"
    column_name="${rest#*.}"
    values="$(mysql_query "SELECT DISTINCT \`$column_name\` FROM \`$schema\`.\`$table\` WHERE \`$column_name\` IS NOT NULL AND \`$column_name\` LIKE '/ms/artifactory/%'")"
    if [[ -n "$values" ]]; then
        urls="$urls"$'\n'"$values"
    fi
done <<< "$columns"

urls="$(printf '%s\n' "$urls" | sed '/^$/d' | sort -u)"
count="$(printf '%s\n' "$urls" | wc -l)"
if [[ "$count" -eq 0 ]]; then
    echo "icon_urls_test: FAIL (no artifactory icon URLs found)" >&2
    exit 1
fi

failures=0
while IFS= read -r url; do
    [[ -n "$url" ]] || continue
    code="$(curl -sS -o /dev/null -w '%{http_code}' \
        -H 'X-DEVOPS-UID: admin' \
        -H 'X-DEVOPS-TOKEN: devops' \
        "http://localhost:8080$url" || echo 000)"
    if [[ "$code" != 200 ]]; then
        echo "icon_urls_test: FAIL http=$code $url" >&2
        failures=$((failures + 1))
    fi
done <<< "$urls"

if [[ "$failures" -gt 0 ]]; then
    echo "icon_urls_test: FAIL ($failures/$count urls broken)" >&2
    exit 1
fi

echo "icon_urls_test: PASS ($count urls)"
