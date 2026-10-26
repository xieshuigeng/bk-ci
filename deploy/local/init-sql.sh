#!/bin/bash
# 在 mysql 容器内执行：按官方顺序（find|sort）灌入全部 SQL
set -euo pipefail
cd /sql || { echo "cd /sql failed" >&2; exit 1; }
echo "== waiting for mysql =="
until mysqladmin ping -h127.0.0.1 -uroot -p"${MYSQL_ROOT_PASSWORD}" --silent; do sleep 2; done
echo "== grant app user =="
mysql -h127.0.0.1 -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER IF NOT EXISTS 'bk_ci'@'%' IDENTIFIED BY 'bk_ci123'; GRANT ALL PRIVILEGES ON *.* TO 'bk_ci'@'%' WITH GRANT OPTION; FLUSH PRIVILEGES;"
echo "== run sql files =="
count=0
while IFS= read -r SQL; do
  echo ">> $SQL"
  mysql -h127.0.0.1 -uroot -p"${MYSQL_ROOT_PASSWORD}" --default-character-set=utf8mb4 < "$SQL"
  count=$((count + 1))
done < <(find . -type f -name "*.sql" | sort)
echo "== init done: ${count} files =="
