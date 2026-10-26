# bk-ci 本地 Docker 完整部署实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行进度（2026-10-20 暂停）:** Task 1–8 已完成并通过两段审查（偏差见 handoff `/tmp/opencode/handoff-bkci-docker-deploy-2026-10-20.md`）；**Task 9 起未执行**。全程未 commit。继续前先读该 handoff。

**Goal:** 在本机用自行构建的网关/后端/前端三个镜像 + docker compose 编排全部依赖（MySQL/Redis/ES/RabbitMQ/Consul），完整跑起 bk-ci v4.2.0-rc.7 并完成端到端冒烟。

**Architecture:** 单机单 compose 项目 `bkci`。后端镜像内含 20+ 个微服务目录，每服务一个容器，入口脚本 `source service.env` 后以 `-Dspring.config.location` 挂载宿主机渲染好的 `common.yml`/`application-<ms>.yml` 启动。配置由 release 包内 `render_tpl` + `bkenv.properties` 渲染（与官方 Helm/裸机同一套机制）。服务经 Spring Cloud Consul 注册（容器 IP），OpenResty 网关按 Consul 路由转发。

**Tech Stack:** Docker 24 + compose、bk-ci v4.2.0-rc.7 release 包（`bkci-slim.tar.gz`）、MySQL 8.0、Redis 7.2、Elasticsearch 7.17、RabbitMQ（延迟消息版）、Consul 1.18、OpenResty。

**计划制定日期:** 2026-10-20（基于仓库 `master@367b10e4` 与 release `v4.2.0-rc.7` 实测探查）

---

## 关键事实（探查结论，执行者必须知道）

1. **release 包**：`bkci-slim.tar.gz`（489MB，已下载到仓库根目录）。顶层目录是 `ci/`（**不是**脚本期望的 `ci-docker/`），含 22 个微服务目录（各为 exploded Spring Boot：`application.yml`、`service.env`、`lib/`）、`frontend/`、`gateway/`、`scripts/`、`support-files/`、`agent-package/`。`0.get_release.sh` 与发布物命名不一致，**手动解包并改名**（Task 2）。
2. **三个镜像 Dockerfile 均无 ENTRYPOINT**（只有 COPY/RUN），启动命令由编排层提供（Helm 同理：gateway/frontend 用 `render_tpl + nginx`，backend 用脚本+显式 java）。基础镜像 `bkci/jdk:0.0.10-jdk17`、`bkci/openresty:0.0.2`（Docker Hub，走本机 registry 加速器）。
3. **`backend.bkci.sh` 是 K8s 专用**（`spring.profiles.active=prod,kubernetes` + Spring Cloud Kubernetes config），本地**不用它**，改用自写入口脚本（Task 6），与裸机版 `boot-service.sh` 同理：`-Dspring.config.location=file:common.yml,file:application-<ms>.yml`。
4. **配置渲染**：`scripts/render_tpl` 从当前目录读 `./bkenv.properties`（bash source，支持 `KEY=$OTHER` 展开），把模板里的 `__VAR__` 替换后写到 `INSTALL_PATH`（模板名以 `#` 开头时 `#`→`/`）。`render_tpl -c` 可列出所有空占位符。模板在 `ci/support-files/templates/`（`#etc#ci#common.yml`、`#etc#ci#application-<ms>.yml`、`gateway*`、`frontend*`）。
5. **服务间寻址**：`common.yml` 中 consul 只有 `port`/`tags`，**无 host**（Spring Cloud Consul 默认 localhost）→ 容器环境变量 `SPRING_CLOUD_CONSUL_HOST=consul` 覆盖。注册地址用 `SPRING_APPLICATION_JSON` 设 `prefer-ip-address:true`、`register-health-check:false`（服务无 actuator，健康检查会 404 导致实例 critical、Consul DNS 不可解析）。
6. **网关路由**：`gateway/core/lua/init.lua` 有 `domain = "__BK_CI_CONSUL_DOMAIN__"`（bkenv 默认 `consul`），`router_srv.lua` 按 `$service` 解析。Consul DNS 在 8600（非 53），网关容器需 dnsmasq 侧车做 `*.consul` 转发 + 上游公网 DNS（若 Task 11 实测发现 router 走 Consul HTTP API，则该侧车冗余，保留无害）。
7. **前端静态**：frontend 镜像（OpenResty/nginx）容器内 80；网关模板 `gateway#core#frontend.conf` 决定 `/console/` 转发目标 → Task 11 读文件后二选一接线（服务名 alias 或手动 Consul 注册）。
8. **默认插件 9 个**从 GitHub Releases 下载（checkout/run/... 见 `helm-charts/core/ci/base/values.yaml:91-109`），部署走 store 的 `/api/op/pipeline/atom/deploy`（需 `X-DEVOPS-UID: admin`；JWT 默认关闭 `BK_CI_JWT_ENABLE=false`）→ Task 13，下载 URL 前缀替换为 `https://ghfast.top/`。
9. **本机环境**：Docker 24.0.2（registry 加速器已配 `docker.m.daocloud.io` 等 3 个）、磁盘 294G 空闲、内存 31G、`github.com` DNS 不通（用 `ghfast.top` 代理）、`api.github.com`/`ssh.github.com` 可达。目标端口 8080/8500 需空闲。
10. **资源预估**：wave A 后端 17 JVM（`service.env` 默认多为 `-Xms256m -Xmx512m`）≈ 12–16G + 基础设施 ≈ 4G + 网关/前端 ≈ 0.5G ≈ 20G，31G 内存可行；超出时按 Task 10 缓解措施收缩。

## 将创建/修改的文件（文件结构）

| 文件 | 职责 |
|---|---|
| `deploy/local/bkenv.properties` | 渲染变量源（官方 base + 本地覆盖，bash sourceable） |
| `deploy/local/rendered/` | render_tpl 输出：`etc/ci/*.yml`（只读挂载给后端） |
| `deploy/local/entrypoint-service.sh` | 后端单服务启动入口（source service.env + java） |
| `deploy/local/docker-compose.yml` | 全栈编排（infra + 17 后端 + gateway + frontend） |
| `deploy/local/init-sql.sh` | MySQL 初始化（`find|sort` 顺序灌 138 个 SQL，与 Helm init Job 一致） |
| `deploy/local/README.md` | 运维手册（up/down/logs/排障） |

构建上下文产物：`docker-images/core/ci/ci-docker/`（解包改名而来，不入库——已加忽略说明，Task 2 输出 `git status` 应只见 `deploy/local/` 与 `bkci-slim.tar.gz`，两者都在最终 Task 14 询问是否提交）。

---

### Task 1: 前置检查

**Files:** 无（只读检查）

- [ ] **Step 1.1: 确认 compose 与端口**

```bash
docker compose version || docker-compose version
ss -lnt | grep -E ':(8080|8500)\b' || echo "PORTS_FREE"
df -h / | tail -1
free -h | head -2
```

Expected: compose v2（`docker compose version` 输出 `Docker Compose version v2.x`；若是 v1 `docker-compose`，后续命令等价替换）；`PORTS_FREE`；磁盘空闲 >20G；可用内存 >24G。
若 8080/8500 被占：全文将 `8080` 替换为其他空闲端口（如 18080），并同步 `deploy/local/bkenv.properties` 覆盖块中的 `BK_CI_PUBLIC_URL`。

- [ ] **Step 1.2: 确认 release 包在位**

```bash
ls -lh /home/xsg/aicode/bk-ci/bkci-slim.tar.gz
```

Expected: 489M。缺失则下载：
`curl -sL -o bkci-slim.tar.gz "https://ghfast.top/https://github.com/TencentBlueKing/bk-ci/releases/download/v4.2.0-rc.7/bkci-slim.tar.gz"`

- [ ] **Step 1.3: 检查 ES 内核参数**

```bash
sysctl vm.max_map_count
```

Expected: ≥262144。若偏低，提前执行 `sudo sysctl -w vm.max_map_count=262144`（需密码则请用户执行）。<262144 时 ES 大概率启动失败（Task 9 有兜底检查）。

---

### Task 2: 解包 release 到构建上下文

**Files:** 创建 `docker-images/core/ci/ci-docker/`（构建上下文，不入库）

- [ ] **Step 2.1: 解包并改名**

```bash
cd /home/xsg/aicode/bk-ci/docker-images/core/ci
cp ../../../bkci-slim.tar.gz ./bkci-docker.tar.gz
rm -rf ci ci-docker
tar -xzf bkci-docker.tar.gz
mv ci ci-docker
ls ci-docker
```

Expected: 输出含 `agentless ai artifactory assembly auth buildless dispatch dockerhost engine environment frontend gateway jars-private jars-public log metrics misc notify openapi process project quality repository scripts store support-files ticket websocket VERSION` 等（22 服务 + 支撑目录）。

- [ ] **Step 2.2: 确认 git 状态干净**

```bash
cd /home/xsg/aicode/bk-ci && git status --short | head
```

Expected: 仅 `?? bkci-slim.tar.gz`、`?? deploy/`（若已建）、`?? docker-images/core/ci/ci-docker` 等 untracked；无 modified。若有 modified，检查是否误改并恢复。

---

### Task 3: 拉取基础镜像

**Files:** 无

- [ ] **Step 3.1: 拉后端/网关基础镜像**

```bash
docker pull bkci/jdk:0.0.10-jdk17
docker pull bkci/openresty:0.0.2
```

Expected: 拉取成功（本机 registry 加速器生效）。若某镜像拉取失败：
1. 重试一次（加速器偶发失败）；
2. 换加速器前缀逐个试：`docker pull docker.m.daocloud.io/bkci/jdk:0.0.10-jdk17 && docker tag docker.m.daocloud.io/bkci/jdk:0.0.10-jdk17 bkci/jdk:0.0.10-jdk17`（`docker.1ms.run`、`docker.xuanyuan.me` 同理）。

---

### Task 4: 构建三个部署镜像

**Files:** 创建 `docker-images/core/ci/ci-docker/` 内 `.dockerignore`（临时）

- [ ] **Step 4.1: 构建网关镜像**

```bash
cd /home/xsg/aicode/bk-ci/docker-images/core/ci
docker build -t bkci-local/bkci-gateway:v4.2.0-rc.7 . -f ./dockerfile/gateway.Dockerfile
```

Expected: `writing image` 后 `naming to docker.io/bkci-local/bkci-gateway:v4.2.0-rc.7`。

- [ ] **Step 4.2: 构建后端镜像**（体积大，5–15 分钟）

```bash
cd /home/xsg/aicode/bk-ci/docker-images/core/ci
printf './ci/frontend\n' > ./.dockerignore
docker build -t bkci-local/bkci-backend:v4.2.0-rc.7 . -f ./dockerfile/backend.bkci.Dockerfile
rm -f ./.dockerignore
```

Expected: 成功且无 push（脚本 `2.build_backend_bkci_image.sh` 自带 `docker push`，本地部署**不要**用该脚本，用上面的直接 build）。

- [ ] **Step 4.3: 构建前端镜像**

```bash
cd /home/xsg/aicode/bk-ci/docker-images/core/ci
docker build -t bkci-local/bkci-frontend:v4.2.0-rc.7 . -f ./dockerfile/frontend.Dockerfile
docker images | grep bkci-local
```

Expected: 三行 `bkci-local/bkci-gateway|backend|frontend v4.2.0-rc.7`，backend 体积 ≥1G。

---

### Task 5: 渲染配置文件

**Files:**
- Create: `deploy/local/bkenv.properties`
- Create: `deploy/local/rendered/etc/ci/*.yml`（render_tpl 输出）

- [ ] **Step 5.1: 生成 bkenv（base + 覆盖）**

```bash
cd /home/xsg/aicode/bk-ci
mkdir -p deploy/local
cp docker-images/core/ci/ci-docker/scripts/bkenv.properties deploy/local/bkenv.properties
cat >> deploy/local/bkenv.properties <<'EOF'

# ===== 本地 docker compose 部署覆盖（2026-10-20）=====
BK_HOME=/data/bkhome
BK_HTTP_SCHEMA=http
BK_DOMAIN=localhost:8080
BK_CI_PUBLIC_URL=http://localhost:8080
BK_CI_PRIVATE_URL=http://gateway:80
BK_CI_AUTH_PROVIDER=sample
BK_CI_MYSQL_ADDR=mysql:3306
BK_CI_MYSQL_USER=bk_ci
BK_CI_MYSQL_PASSWORD=bk_ci123
BK_CI_REDIS_HOST=redis
BK_CI_REDIS_PORT=6379
BK_CI_REDIS_PASSWORD=
BK_CI_REDIS_DB=0
BK_CI_RABBITMQ_ADDR=rabbitmq:5672
BK_CI_RABBITMQ_USER=bk_ci
BK_CI_RABBITMQ_PASSWORD=bk_ci123
BK_CI_RABBITMQ_VHOST=bk_ci
BK_CI_RABBIT_QUORUM_ENABLE=false
BK_CI_ES_REST_ADDR=es
BK_CI_ES_REST_PORT=9200
BK_CI_ES_CLUSTER_NAME=bkee-es
BK_CI_CONSUL_IP=consul
BK_CI_CONSUL_HTTP_PORT=8500
BK_CI_CONSUL_DOMAIN=consul
BK_CI_MQ_DEFAULT_BINDER=core-rabbit
BK_CI_LOG_STORAGE_TYPE=elasticsearch
EOF
```

（bash source 后写的覆盖 base 同名值；`BK_CI_PUBLIC_URL`/`BK_CI_DOMAIN` 直接给字面值避免嵌套展开问题。）

- [ ] **Step 5.2: 占位符完整性检查**

```bash
cd /home/xsg/aicode/bk-ci/deploy/local
set -a && . ./bkenv.properties && set +a
../..//docker-images/core/ci/ci-docker/scripts/render_tpl -c ../../docker-images/core/ci/ci-docker/support-files/templates/#etc#ci#*.yml
```

（render_tpl 需在**含 bkenv.properties 的目录**执行；相对路径按实际调整，也可用绝对路径。）
Expected: 无 `EMPTY PLACE_HILLDERS` 输出。若出现：逐个把缺失变量加进 `deploy/local/bkenv.properties` 覆盖块（变量名即输出中的 `KEY`；一般取官方文档/相邻变量默认值，空值功能即关闭——用 `grep -n "变量名" ci-docker/scripts/bkenv.properties` 确认 base 是否本来就没有，没有则给空串 `KEY=`）。重复 Step 5.2 直到干净。

- [ ] **Step 5.3: 渲染**

```bash
cd /home/xsg/aicode/bk-ci/deploy/local
set -a && . ./bkenv.properties && set +a
export INSTALL_PATH="$PWD/rendered"
../../docker-images/core/ci/ci-docker/scripts/render_tpl ../../docker-images/core/ci/ci-docker/support-files/templates/#etc#ci#*.yml
ls rendered/etc/ci/
```

Expected: `render #etc#ci#common.yml -> .../rendered/etc/ci/common.yml` 等约 24 行；`ls` 输出 `common.yml application-process.yml application-project.yml ...`。

- [ ] **Step 5.4: 残留占位符检查**

```bash
grep -RInE '__[A-Z][A-Z0-9_]*__' /home/xsg/aicode/bk-ci/deploy/local/rendered/ && echo "FOUND_LEFTOVER" || echo "CLEAN"
```

Expected: `CLEAN`。若 `FOUND_LEFTOVER`：对残留变量回到 Step 5.2 补变量后重新渲染。

- [ ] **Step 5.5: 关键值抽查**

```bash
grep -n "jdbc:mysql" /home/xsg/aicode/bk-ci/deploy/local/rendered/etc/ci/application-process.yml | head -2
grep -n -A3 "consul:" /home/xsg/aicode/bk-ci/deploy/local/rendered/etc/ci/common.yml | head -6
grep -n "host:" /home/xsg/aicode/bk-ci/deploy/local/rendered/etc/ci/common.yml | head -3
```

Expected: url 为 `jdbc:mysql://mysql:3306/devops_ci_process...`；redis host 为 `redis`；consul port `8500`（host 不存在是正常的——由 Task 6 容器环境变量提供）。

---

### Task 6: 后端入口脚本与 compose 编排

**Files:**
- Create: `deploy/local/entrypoint-service.sh`
- Create: `deploy/local/docker-compose.yml`

- [ ] **Step 6.1: 写入口脚本**

创建 `deploy/local/entrypoint-service.sh`：

```bash
#!/bin/bash
# 用法: /entrypoint.sh <ms-name>   (如 process / project / auth)
set -e
MS_NAME="$1"
if [ -z "$MS_NAME" ]; then echo "usage: entrypoint.sh <ms-name>" >&2; exit 2; fi
cd "/data/workspace/${MS_NAME}" || { echo "no such service dir: ${MS_NAME}" >&2; exit 3; }
# service.env 提供 MAIN_CLASS / CLASSPATH / MEM_OPTS / JAVA_TOOL_OPTIONS
source ./service.env
unset SPRING_CONFIG_LOCATION   # 由 -D 显式指定，避免 env 覆盖歧义
exec java ${MEM_OPTS:-} \
  -Dspring.application.name="${MS_NAME}" \
  -Dservice-suffix= \
  -Dspring.config.location="file:/etc/bkci/conf/common.yml,file:/etc/bkci/conf/application-${MS_NAME}.yml" \
  -Dservice.log.dir=./logs/ \
  -Ddevops_gateway="${DEVOPS_GATEWAY:-http://localhost:8080}" \
  -Dbksvc="bk-ci-${MS_NAME}" \
  -classpath ".:lib/*" \
  ${MAIN_CLASS}
```

```bash
chmod +x /home/xsg/aicode/bk-ci/deploy/local/entrypoint-service.sh
```

验证脚本所引用的 `MAIN_CLASS` 存在（抽查 3 个）：
```bash
cd /home/xsg/aicode/bk-ci/docker-images/core/ci/ci-docker
for m in process project auth; do (cd $m && bash -c 'source service.env; echo $m' "m=$m: $MAIN_CLASS"); done
```
Expected: 三行均输出 `com.tencent.devops.*ApplicationKt` 形式。

- [ ] **Step 6.2: 写 compose 文件**

创建 `deploy/local/docker-compose.yml`：

```yaml
name: bkci

networks:
  bkci:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16
          gateway: 172.28.0.1

x-backend: &backend
  image: bkci-local/bkci-backend:v4.2.0-rc.7
  restart: unless-stopped
  networks:
    - bkci
  environment:
    SPRING_CLOUD_CONSUL_HOST: consul
    SPRING_CLOUD_CONSUL_PORT: "8500"
    SPRING_APPLICATION_JSON: '{"spring":{"cloud":{"consul":{"discovery":{"prefer-ip-address":true,"register-health-check":false}}}}}'
    DEVOPS_GATEWAY: http://localhost:8080
    BK_HOME: /data/bkhome
  volumes:
    - ./rendered/etc/ci:/etc/bkci/conf:ro
    - ./entrypoint-service.sh:/entrypoint.sh:ro
  depends_on:
    mysql: { condition: service_healthy }
    redis: { condition: service_healthy }
    rabbitmq: { condition: service_healthy }
    consul: { condition: service_started }
    es: { condition: service_healthy }

x-logging: &default-logging
  driver: json-file
  options: { max-size: "10m", max-file: "3" }

services:
  # ---------- 基础设施 ----------
  mysql:
    image: mysql:8.0.37
    container_name: bkci-mysql
    restart: unless-stopped
    command: --default-authentication-plugin=mysql_native_password --character-set-server=utf8mb4 --collation-server=utf8mb4_bin
    environment:
      MYSQL_ROOT_PASSWORD: root123
    volumes:
      - mysql-data:/var/lib/mysql
      - ../../docker-images/core/ci/ci-docker/support-files/sql:/sql:ro
      - ./init-sql.sh:/init-sql.sh:ro
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1", "-proot123"]
      interval: 5s
      timeout: 5s
      retries: 40
    networks: { bkci: {} }
    logging: *default-logging

  redis:
    image: redis:7.2-alpine
    container_name: bkci-redis
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 20
    networks: { bkci: {} }
    logging: *default-logging

  es:
    image: elastic.m.daocloud.io/elasticsearch/elasticsearch:7.17.22
    container_name: bkci-es
    restart: unless-stopped
    environment:
      discovery.type: single-node
      xpack.security.enabled: "false"
      cluster.name: bkee-es
      ES_JAVA_OPTS: -Xms512m -Xmx512m
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS localhost:9200/_cluster/health?wait_for_status=yellow\\&timeout=5s || exit 1"]
      interval: 10s
      timeout: 8s
      retries: 30
    networks: { bkci: {} }
    logging: *default-logging

  rabbitmq:
    image: bkci/rabbitmq-with-delay:latest
    container_name: bkci-rabbitmq
    restart: unless-stopped
    environment:
      RABBITMQ_DEFAULT_USER: bk_ci
      RABBITMQ_DEFAULT_PASS: bk_ci123
      RABBITMQ_DEFAULT_VHOST: bk_ci
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
      interval: 10s
      timeout: 8s
      retries: 30
    networks: { bkci: {} }
    logging: *default-logging

  consul:
    image: hashicorp/consul:1.18
    container_name: bkci-consul
    restart: unless-stopped
    command: agent -server -bootstrap -ui -client=0.0.0.0 -data-dir=/consul/data
    ports:
      - "8500:8500"
    volumes:
      - consul-data:/consul/data
    networks:
      bkci:
        ipv4_address: 172.28.0.10
    logging: *default-logging

  dnsmasq:
    image: andyshinn/dnsmasq:2.85
    container_name: bkci-dnsmasq
    restart: unless-stopped
    command:
      - --no-resolv
      - --server=/consul/172.28.0.10
      - --server=114.114.114.114
      - --server=223.5.5.5
      - --log-queries
    networks:
      bkci:
        ipv4_address: 172.28.0.53
    logging: *default-logging

  # ---------- 前端 ----------
  frontend:
    image: bkci-local/bkci-frontend:v4.2.0-rc.7
    container_name: bkci-frontend
    restart: unless-stopped
    networks:
      - bkci
    command:
      - /bin/sh
      - -c
      - |
        export INSTALL_PATH=/data/workspace BK_HOME=/data/bkhome
        cd /etc/bkci && /data/workspace/scripts/render_tpl -m . /data/workspace/templates/frontend*
        exec /usr/local/openresty/nginx/sbin/nginx -g 'daemon off;'
    volumes:
      - ./rendered/bkenv.properties:/etc/bkci/bkenv.properties:ro
    healthcheck:
      test: ["CMD-SHELL", "wget -q -O - http://127.0.0.1/healthz || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 15
    logging: *default-logging

  gateway:
    image: bkci-local/bkci-gateway:v4.2.0-rc.7
    container_name: bkci-gateway
    restart: unless-stopped
    ports:
      - "8080:80"
    dns:
      - 172.28.0.53
    networks:
      - bkci
    environment:
      BK_HOME: /data/bkhome
    command:
      - /bin/bash
      - -c
      - |
        export INSTALL_PATH=/data/workspace BK_HOME=/data/bkhome
        cd /etc/bkci && /data/workspace/scripts/render_tpl -m . /data/workspace/templates/gateway*
        exec /usr/local/openresty/nginx/sbin/nginx -g 'daemon off;'
    volumes:
      - ./rendered/bkenv.properties:/etc/bkci/bkenv.properties:ro
    depends_on:
      - consul
      - dnsmasq
    logging: *default-logging

  # ---------- 后端微服务（wave A，17 个）----------
  process:     { <<: *backend, container_name: bkci-process,     command: ["/bin/bash", "/entrypoint.sh", "process"] }
  engine:      { <<: *backend, container_name: bkci-engine,      command: ["/bin/bash", "/entrypoint.sh", "engine"] }
  project:     { <<: *backend, container_name: bkci-project,     command: ["/bin/bash", "/entrypoint.sh", "project"] }
  repository:  { <<: *backend, container_name: bkci-repository,  command: ["/bin/bash", "/entrypoint.sh", "repository"] }
  store:       { <<: *backend, container_name: bkci-store,       command: ["/bin/bash", "/entrypoint.sh", "store"] }
  ticket:      { <<: *backend, container_name: bkci-ticket,      command: ["/bin/bash", "/entrypoint.sh", "ticket"] }
  environment: { <<: *backend, container_name: bkci-environment, command: ["/bin/bash", "/entrypoint.sh", "environment"] }
  dispatch:    { <<: *backend, container_name: bkci-dispatch,    command: ["/bin/bash", "/entrypoint.sh", "dispatch"] }
  quality:     { <<: *backend, container_name: bkci-quality,     command: ["/bin/bash", "/entrypoint.sh", "quality"] }
  log:         { <<: *backend, container_name: bkci-log,         command: ["/bin/bash", "/entrypoint.sh", "log"] }
  notify:      { <<: *backend, container_name: bkci-notify,      command: ["/bin/bash", "/entrypoint.sh", "notify"] }
  auth:        { <<: *backend, container_name: bkci-auth,        command: ["/bin/bash", "/entrypoint.sh", "auth"] }
  openapi:     { <<: *backend, container_name: bkci-openapi,     command: ["/bin/bash", "/entrypoint.sh", "openapi"] }
  websocket:   { <<: *backend, container_name: bkci-websocket,   command: ["/bin/bash", "/entrypoint.sh", "websocket"] }
  misc:        { <<: *backend, container_name: bkci-misc,        command: ["/bin/bash", "/entrypoint.sh", "misc"] }
  artifactory: { <<: *backend, container_name: bkci-artifactory, command: ["/bin/bash", "/entrypoint.sh", "artifactory"] }
  metrics:     { <<: *backend, container_name: bkci-metrics,     command: ["/bin/bash", "/entrypoint.sh", "metrics"] }

volumes:
  mysql-data:
  consul-data:
```

- [ ] **Step 6.3: 校验 compose 语法**

```bash
cd /home/xsg/aicode/bk-ci/deploy/local && docker compose config --quiet && echo COMPOSE_OK
```

Expected: `COMPOSE_OK`（无 YAML 错误）。
若 `docker compose` 不可用（仅 v1）：用 `docker-compose` 替换全部命令。

- [ ] **Step 6.4: 确认 17 个服务目录都在镜像上下文中**

```bash
cd /home/xsg/aicode/bk-ci/docker-images/core/ci/ci-docker
for m in process engine project repository store ticket environment dispatch quality log notify auth openapi websocket misc artifactory metrics; do
  [ -f "$m/service.env" ] || echo "MISSING $m"
done; echo DIR_CHECK_DONE
```

Expected: `DIR_CHECK_DONE` 前无 `MISSING` 行。

---

### Task 7: MySQL 数据库初始化

**Files:**
- Create: `deploy/local/init-sql.sh`
- 修改（数据）: `mysql-data` 卷

- [ ] **Step 7.1: 写初始化脚本**

创建 `deploy/local/init-sql.sh`：

```bash
#!/bin/bash
# 在 mysql 容器内执行：按官方顺序（find|sort）灌入全部 SQL
set -e
cd /sql
echo "== waiting for mysql =="
until mysqladmin ping -h127.0.0.1 -uroot -p"${MYSQL_ROOT_PASSWORD}" --silent; do sleep 2; done
echo "== grant app user =="
mysql -h127.0.0.1 -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER IF NOT EXISTS 'bk_ci'@'%' IDENTIFIED BY 'bk_ci123'; GRANT ALL PRIVILEGES ON *.* TO 'bk_ci'@'%' WITH GRANT OPTION; FLUSH PRIVILEGES;"
echo "== run sql files =="
find . -type f -name "*.sql" | sort | while read -r SQL; do
  echo ">> $SQL"
  mysql -h127.0.0.1 -uroot -p"${MYSQL_ROOT_PASSWORD}" --default-character-set=utf8mb4 < "$SQL"
done
echo "== init done =="
touch /sql/.init-done
```

```bash
chmod +x /home/xsg/aicode/bk-ci/deploy/local/init-sql.sh
```

- [ ] **Step 7.2: 看一眼 0001 建库脚本（确认它只是 CREATE DATABASE/USER）**

```bash
head -30 /home/xsg/aicode/bk-ci/docker-images/core/ci/ci-docker/support-files/sql/0001_ci_create-database_mysql.sql
```

Expected: `CREATE DATABASE IF NOT EXISTS devops_ci_*` 类语句。若含 `CREATE USER ... IDENTIFIED BY '...'`，记下密码（与 bkenv 的 `BK_CI_MYSQL_PASSWORD` 不一致时以其为准，并同步改 `deploy/local/bkenv.properties` 与重新渲染 Step 5.3）。**若它建的用户就是 `bk_ci`**，Step 7.1 的 CREATE USER 用 `CREATE USER IF NOT EXISTS` 幂等无害。

- [ ] **Step 7.3: 启动 MySQL 并灌库**

```bash
cd /home/xsg/aicode/bk-ci/deploy/local
docker compose up -d mysql
docker compose exec -e MYSQL_ROOT_PASSWORD=root123 mysql bash /init-sql.sh 2>&1 | tail -30
```

Expected: 末尾 `== init done ==`。SQL 有 138 个文件，2–10 分钟。
若中途某个 SQL 报错：记录文件名；`CREATE TABLE` 重复类报错（重跑场景）可跳过该文件继续（幂等性按官方 README 应无此问题）；语法/表不存在类错误需把报错全文带回到计划外讨论（说明 release 包与 SQL 版本不匹配）。

- [ ] **Step 7.4: 验证库表**

```bash
docker compose exec mysql mysql -uroot -proot123 -e "SHOW DATABASES;" | tr '\n' ' '; echo
docker compose exec mysql mysql -uroot -proot123 -N -e "SELECT table_schema, COUNT(*) FROM information_schema.tables WHERE table_schema LIKE 'devops%' GROUP BY 1 ORDER BY 1;"
```

Expected: 出现 `devops_ci_process devops_ci_project devops_ci_store devops_ci_repository devops_ci_quality ... devops_ci_archive_process` 等 ≥15 个库，每个库有表（process 库表数量应最多）。

---

### Task 8: 启动基础设施并验证

**Files:** 无新增（操作 compose 服务）

- [ ] **Step 8.1: 启动 infra**

```bash
cd /home/xsg/aicode/bk-ci/deploy/local
docker compose up -d redis es rabbitmq consul dnsmasq
docker compose ps --format 'table {{.Name}}\t{{.Status}}'
```

Expected: 5 个容器 `Up`（es 首次启动 20–40s 转 healthy）。

- [ ] **Step 8.2: 逐项健康验证**

```bash
docker compose exec redis redis-cli ping
docker compose exec consul consul members | head -3
docker compose exec es curl -s localhost:9200/_cluster/health?pretty | grep -E 'status|cluster_name'
docker compose exec rabbitmq rabbitmqctl status | head -5
docker run --rm --network bkci alpine nslookup process.consul 172.28.0.53 || true
```

Expected:
- `PONG`
- consul 一行 `server  ... alive`
- `cluster_name: bkee-es`、`status: yellow`（单节点无副本即 yellow，**green 非必需**）
- rabbitmq `RabbitMQ` 版本行
- nslookup：**此时无服务注册**应报 NXDOMAIN/timeout——但要能连到 dnsmasq（报 `connection refused` 才是 dnsmasq 坏了）。可先 `nslookup baidu.com 172.28.0.53` 验证上游可用（Expected: 返回 IP）。

若 es 因 `max file descriptors` / `max virtual memory areas` 启动失败：`sudo sysctl -w vm.max_map_count=262144` 后 `docker compose up -d es`（Task 1.3 未做的话现在必须做）。
若 `bkci/rabbitmq-with-delay:latest` 拉取失败：改用 `rabbitmq:3.10-management` 并启用延迟插件（插件包经代理下载）：
```bash
# 兜底（仅当 with-delay 镜像不可用）：
# docker pull rabbitmq:3.10-management
# 启动后: docker compose exec rabbitmq rabbitmq-plugins enable rabbitmq_delayed_message_exchange
# （若插件未内置: curl -sL https://ghfast.top/https://github.com/rabbitmq/rabbitmq-delayed-message-exchange/releases/download/3.10.2/rabbitmq_delayed_message_exchange-3.10.2.ez -o /tmp/p.ez && docker cp ... 到 plugins 目录再 enable）
```
若 rabbitmq 首启后验证用户：`docker compose exec rabbitmq rabbitmqctl list_users` 应含 `bk_ci`；`list_vhosts` 含 `bk_ci`。若镜像忽略 DEFAULT_* 环境变量：
```bash
docker compose exec rabbitmq rabbitmqctl add_user bk_ci bk_ci123 || true
docker compose exec rabbitmq rabbitmqctl set_user_tags bk_ci administrator
docker compose exec rabbitmq rabbitmqctl add_vhost bk_ci
docker compose exec rabbitmq rabbitmqctl set_permissions -p bk_ci bk_ci '.*' '.*' '.*'
```

---

### Task 9: 启动 17 个后端服务（wave A）

**Files:** 无新增

- [ ] **Step 9.1: 批量启动**

```bash
cd /home/xsg/aicode/bk-ci/deploy/local
docker compose up -d process engine project repository store ticket environment dispatch quality log notify auth openapi websocket misc artifactory metrics
```

Expected: `Container bkci-xxx  Creating/Started`，无镜像/网络错误。

- [ ] **Step 9.2: 等待并检查启动日志（关键检查点）**

```bash
sleep 60
for m in process project auth store repository dispatch; do
  echo "=== $m ==="
  docker logs bkci-$m 2>&1 | grep -E "Started .*Application|ERROR|APPLICATION FAILED|Caused by" | tail -5
done
```

Expected: 每个服务出现 `Started XxxApplicationKt in NN.NN seconds`；**无** `APPLICATION FAILED TO START`。
常见故障定位（按日志行动）：
- `Connection refused ... 127.0.0.1:3306/6379/5672/9200` → 说明渲染配置没生效（挂载/路径错），检查 `docker inspect bkci-process | grep -A3 Binds` 与渲染值（Task 5.5）
- `No node to service` / consul 连接错 → 检查 `SPRING_CLOUD_CONSUL_HOST` env 是否在（`docker exec bkci-process env | grep CONSUL`）
- `Access denied for user` → MySQL 用户/密码不匹配（Task 7.2/7.3）
- OOMKilled → 内存不足，对重启频繁的服务在 compose 该服务下加 `environment: { JAVA_TOOL_OPTIONS: "-Xmx384m" }`（service.env 的 MEM_OPTS 仍生效，JAVA_TOOL_OPTIONS 追加）；或分批启动（`docker compose stop` 一半再 up）
- `Unable to make ... native` / classpath 错 → `service.env` 的 `CLASSPATH=".:lib/*"` 依赖工作目录，确认 `docker exec bkci-process pwd` 为 `/data/workspace/process`

- [ ] **Step 9.3: 全量状态扫描**

```bash
docker compose ps --format 'table {{.Name}}\t{{.Status}}' | sort
docker compose ps -a --filter "status=exited" --format '{{.Name}}'
```

Expected: 17 个后端 + 5 infra 全 `Up`；`exited` 输出为空。对 exited 的容器：`docker logs bkci-<名>` 定位（回到 Step 9.2 故障表），修完 `docker compose up -d <名>` 重试。

- [ ] **Step 9.4: 验证 Consul 注册**

```bash
curl -s http://localhost:8500/v1/agent/services | python3 -c "import json,sys; d=json.load(sys.stdin); [print(v['Service'], v['Address'] or v['ServiceAddress'], v['Port']) for v in d.values()]" | sort
```

Expected: ≥17 行 `process 172.28.x.x 21921` 形式；**地址不能是 127.0.0.1**（是则 `prefer-ip-address` 没生效，检查 `SPRING_APPLICATION_JSON` 是否被 service.env 覆盖——`docker exec bkci-process env | grep SPRING_APPLICATION_JSON`；若被覆盖，改为在 `deploy/local/rendered/etc/ci/common.yml` 的 `spring.cloud.consul.discovery:` 下直接追加两行 `prefer-ip-address: true` 和 `register-health-check: false` 后 `docker compose up -d --force-recreate` 后端全量）。
端口应与 `bkenv` 的 `*_API_PORT` 一致（process=21921、project=21912、store=21918...）。

- [ ] **Step 9.5: 验证服务互调（冒烟中的质量红线示例）**

```bash
docker exec bkci-gateway sh -c "wget -q -O - http://process.service.consul:21921/api/service/pipeline/management/projects/all" 2>&1 | head -3 || true
```

Expected: 返回 JSON 或业务错误码（非 DNS 解析失败/超时）。若 `process.service.consul` 解析失败但 `process.consul` 成功，说明网关 lua 用的是 `service.consul` 域 → 把 `deploy/local/bkenv.properties` 中 `BK_CI_CONSUL_DOMAIN=consul` 改为 `service.consul`，并给 consul 容器命令加 `-domain=service.consul`（compose 中 `command:` 追加）后 `docker compose up -d consul gateway`，重新渲染（Task 5.3）。此步失败不阻塞——Task 11 会以浏览器实测为准。

---

### Task 10: 启动网关与前端，打通路由

**Files:** 可能微调 `deploy/local/docker-compose.yml`（frontend 接线）

- [ ] **Step 10.1: 启动并验证渲染与 nginx**

```bash
cd /home/xsg/aicode/bk-ci/deploy/local
docker compose up -d frontend gateway
docker logs bkci-frontend 2>&1 | tail -5
docker logs bkci-gateway 2>&1 | tail -5
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/healthz || true
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/
```

Expected: 两容器日志有 `render #... -> ...` 行、无 nginx `[emerg]`；若 backend 自带 healthz 未透出，`/` 返回 `302`（跳 `/console/`）或 `200`。nginx 配置错误（`unexpected end of file` / `unknown directive`）= 渲染出空文件 → 检查 `docker exec bkci-gateway ls -l /data/workspace/gateway/core/` 与 `cat .../server.common.conf` 是否被正确生成（渲染变量缺失会导致空文件——Task 5.2/5.4 回查）。

- [ ] **Step 10.2: 检查网关→前端转发规则**

```bash
docker exec bkci-gateway grep -rn "set \$service" /data/workspace/gateway/core/vhosts/*.conf | head -20
docker exec bkci-gateway cat /data/workspace/gateway/core/vhosts/devops.redirect.conf 2>/dev/null | head -30
docker exec bkci-gateway grep -rn "frontend" /data/workspace/gateway/core/vhosts/ /data/workspace/gateway/core/*.conf | head -10
```

目的：找出 `/console/` 的 upstream 是什么（形如 `$service="frontend"` + `router_srv.lua`，或直接 `proxy_pass http://frontend`）。

**分支 A — router 按 Consul DNS 找 `frontend`（nginx 不会自己注册）**：手动注册前端到 Consul：
```bash
FE_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' bkci-frontend)
curl -s -X PUT http://localhost:8500/v1/agent/service/register -d "{\"Name\":\"frontend\",\"Address\":\"$FE_IP\",\"Port\":80,\"Tags\":[\"devops\"]}"
curl -s "http://localhost:8500/v1/health/service/frontend?passing=true" | head -3
```
Expected: 返回含 `frontend` 的 JSON。把该 `curl` 两行追加到 `deploy/local/README.md` 的"重启后需执行"清单（或写成 `deploy/local/register-frontend.sh`）。

**分支 B — 静态 upstream（如 `proxy_pass http://...`）**：按文件里的主机名给 compose `frontend` 服务加网络别名，例如文件写 `frontend:80` 或 `frontend.service.consul`：
```yaml
  frontend:
    networks:
      bkci:
        aliases: [frontend, frontend.service.consul, frontend.consul]
```
`docker compose up -d frontend gateway` 后重试 Step 10.3。

- [ ] **Step 10.3: 控制台可达性**

```bash
curl -s -o /dev/null -w "%{http_code} %{redirect_url}\n" http://localhost:8080/console/
curl -s http://localhost:8080/console/ | head -5
```

Expected: `200` 且 HTML 开头 `<!DOCTYPE html>`（或先 302 到 `/console/` 再 200）。
若 404/502：
- 404 → 路径没匹配（读 `devops.proxy.conf`/`all.static.server.conf` 中 `/console` 的 location，按其 `$service`/`$url_prefix` 值回到分支 A/B 接线）
- 502/bad gateway → upstream 解析失败：`docker exec bkci-gateway openresty -t`、`docker logs bkci-dnsmasq | tail`（`using nameserver 172.28.0.10#53 for zone consul`）、Consul 里有没有 `frontend`（Step 10.2 分支 A 是否做了）

---

### Task 11: 端到端冒烟

**Files:** 无

- [x] **Step 11.1: sample 登录行为确认**

结果（2026-10-26）：sample provider 以 `admin` 放行；用户接口统一带 `X-DEVOPS-UID: admin`。

```bash
docker exec bkci-gateway cat /data/workspace/gateway/core/lua/auth/auth_user-sample.lua | head -40
```

目的：确认 sample provider 对请求的处理（预期：放行并注入 mock 用户，如 `admin`）。记录其中的用户名/cookie 行为供下一步用。

- [x] **Step 11.2: 浏览器/API 冒烟**

结果（2026-10-26）：`/console/` 返回 200；`demotest` 项目已创建；process/project/store 等业务接口正常。

```bash
# 1) 控制台静态资源
curl -s -o /dev/null -w "console:%{http_code}\n" http://localhost:8080/console/
# 2) 经网关调后端（路径按网关 vhost 规则，先探通用入口）
curl -s -o /dev/null -w "project-api:%{http_code}\n" http://localhost:8080/api/project/user/projects
curl -s -D- -o /dev/null http://localhost:8080/api/project/user/projects 2>/dev/null | grep -E "HTTP/|set-cookie" | head -4
```

Expected: `console:200`；project-api 返回 `200`（业务 JSON）或 `401/403`。
若 401/403：带 sample 用户重试（用户名取自 Step 11.1，常见为 `admin`）：
`curl -b "devops_session=admin" ...` 或按 auth_user-sample.lua 生成的 cookie 名构造；同时 `docker logs bkci-auth | tail`、`docker logs bkci-gateway | tail` 看鉴权拒绝原因。
若 404：读 `docker exec bkci-gateway cat /data/workspace/gateway/core/vhosts/devops.proxy.conf` 中 `/api` 的转发规则，改用其实际路径前缀。

- [ ] **Step 11.3: 用 UI 建项目+流水线（人工/浏览器步骤）**

结果（2026-10-26，API 等价路径）：已用 API 创建 `demotest` 项目、保存 `complex-demo-pipeline` 并触发 build #14；stage-1/2/3 全部成功，日志接口可读。浏览器人工走查仍待执行。

打开 `http://localhost:8080/console/`：
1. 应进入控制台（sample provider 自动登录或 mock 登录页）；
2. 创建项目（如 `demo`）→ 成功进入项目页；
3. 新建流水线 → 编排面板能列出插件（若为空，先做 Task 12 再回来）；
4. 保存并手动触发一条最简流水线（拉码步骤可跳过，直接 `run` 脚本步骤 `echo hello`）→ 构建详情页能看到步骤执行与日志输出。

Expected: 构建走到 `SUCCESS`。构建日志实时输出依赖 websocket/log 服务——日志区空白时：`docker logs bkci-log | tail`、`docker logs bkci-websocket | tail`、`docker logs bkci-engine | tail` 定位。

> 若暂时没有浏览器环境：用 API 完成等价冒烟（建项目 → 建流水线 → 触发 → 查构建状态），所有入口都在 `support-files/apigw/bk_apigw_resources_devops.yaml` 里；仍以 UI 结果为最终验收。

- [x] **Step 11.4: 构建执行链路说明（如触发失败按此排查）**

结果（2026-10-26）：采用方案 2，`dockerhost` + `bkci/ci:jdk17` 已跑通；build #14 三个 stage 全部 SUCCEED。

构建任务链：`process(引擎)` → `dispatch(调度)` → 需要**构建资源**。本地尚无构建机/无编译环境：
- **方案 1（推荐）**：环境管理页面注册一台"第三方构建机"，在宿主机起 agent（release 包 `ci-docker/agent-package/` 有安装包；agent 连网关 `http://localhost:8080`）；
- **方案 2**：启动 wave B 的 `dockerhost`/`agentless` 容器走 Docker 构建（需配置 `dockerhost` 的调度参数，属于波次 B）。
首次冒烟可只验证到"构建排队/等待资源"即算链路通（process/dispatch 日志出现派发记录），完整跑通需上述其一。

---

### Task 11b: 部署 BkRepo（制品库）以打通建项目（计划外新增，用户批准）

**背景（Task 11 实测发现）:** bk-ci v4.2.0-rc.7 建项目时 `SimpleProjectExtService.createExtProjectInfo` **无条件**调用
`BkRepoClient.createBkRepoResource`（容错）与 `updateProjectShareEnabled`（**不容错**，抛 `RemoteServiceException` → 事务回滚）。
调用形如 `${DEVGW}/bkrepo/api/service/repository/api/project/{projectId}/share/enabled?enabled=true`，经 bk-ci 网关
（`router_srv.lua`: `service=="bkrepo"` → `config.bkrepo.domain`）转发到 bkrepo。无 bkrepo 则建项目必失败。

**官方镜像兼容性结论（侦察已确认）:**
- 单体 `bkrepo/bkrepo:latest`（2023-04）**没有** `share/enabled`（其 `ProjectClient` 无该方法）→ 不兼容。
- 拆分 `bkrepo/bkrepo-{gateway,repository,auth}:3.8.9-rc.2`（2026-10）**有**该能力：repository 服务暴露
  `PUT /api/project/{projectId}/share/enabled?enabled=<bool>`（`@RequestParam enabled`），与 bk-ci 的方法/参数完全一致。
- 但拆分 bkrepo 网关的 `router_srv.lua` 有 `allow_services` 白名单（不含 `"service"`）+ `^service(/|$)` 显式 404，
  故 bk-ci 的 `/api/service/<svc>/...` 路径形态被拒。**修复只需一条 nginx rewrite**（在 bk-ci 网关侧）：
  `^/bkrepo/api/service/([\w-_]+)/(.*)` → `/bkrepo/$1/$2`。BkRepoClient.kt 全部调用均为该形态，一条规则覆盖全部。
- 配置模板**已内置于 gateway 镜像** `/data/workspace/templates/`（`render_tpl` + `__BK_REPO_*__` env），无需上游源码仓库（该 repo 现 404）。

**Files:** `deploy/local/docker-compose.yml`（+3 bkrepo 服务 + mongodb），可能新增 `deploy/local/bkrepo.env`

- [x] **Step 11b.1: 拉取镜像（走可用 mirror）**
```bash
for i in bkrepo-gateway bkrepo-repository bkrepo-auth; do
  docker pull dockerproxy.net/bkrepo/$i:3.8.9-rc.2 || docker pull docker.1ms.run/bkrepo/$i:3.8.9-rc.2
done
docker image inspect dockerproxy.net/bkrepo/bkrepo-repository:3.8.9-rc.2 --format '{{.Id}} {{.Created}}'
```
Expected: 三个镜像就位；inspect 贴真实输出（禁止虚报）。

- [x] **Step 11b.2: compose 追加依赖与 bkrepo 服务**
- `mongo:6`（或 bkrepo 要求的版本）容器 `bkci-bkrepo-mongo`，卷 `bkrepo-mongo-data`；**勿复用宿主 mongo**。
- `bkrepo-repository` / `bkrepo-auth`：`BK_REPO_MONGODB_URI`、`BK_REPO_REDIS_HOST=redis`、`BK_REPO_SERVICE_PREFIX=bkrepo-`、
  consul 地址、`BK_REPO_STORAGE_TYPE=filesystem`；注册到 `bkci` 网络；auth 配 devops 模式指向 bk-ci 公网 URL（见下）。
- `bkrepo-gateway`：网络别名 `bkrepo.local`；`BK_REPO_GATEWAY_DNS_ADDR` 指向可解析 consul 的 DNS（`172.28.0.53` 或 `127.0.0.11`）；
  `__BK_REPO_*__` 占位符按镜像 `templates/` 逐一填实（`docker run --rm --entrypoint sh <gw> -c 'grep -rn __BK_REPO_ <templates>'` 取全集）。
- 依赖健康顺序：mongo/redis/consul → repository/auth → gateway。

- [x] **Step 11b.3: bk-ci 网关加 rewrite 并重建**

> 实测无需额外 rewrite：网关镜像模板 `vhosts/devops.artifactory.bkrepo.conf` 已内置
> `location ~ /(ms/|)bkrepo/api/service/(.*)` + `proxy_pass http://$target/$2`，
> 可把 `/bkrepo/api/service/repository/api/...` 正确转发为 `/repository/api/...`。
在 `docker-compose.yml` 的 gateway `command`（render 之后、exec 之前）加：
```sh
sed -i 's|<注入点>|...|' ...   # 或在 render 出的 devops.<> 里加 location
```
推荐以独立 vhost 片段落到 gateway core（render 后 `include`），规则：
`rewrite ^/bkrepo/api/service/([\w-_]+)/(.*) /bkrepo/$1/$2 break;`（保留到 bkrepo 网关再 proxy_pass）。
加断言（`grep -q` 规则存在否则 exit 1）。`docker compose up -d --force-recreate gateway`。

- [x] **Step 11b.4: 验证 bkrepo 可达 + 建项目成功**
```bash
docker exec bkci-gateway getent hosts bkrepo.local          # → bkrepo-gateway IP
docker exec bkci-gateway sh -c "wget -qO- http://bkrepo.local/repository/api/project/list -H 'Authorization: ...'" | head -c 300
# 建项目：
curl -s -X POST -H "Content-Type: application/json" -H "X-DEVOPS-UID: admin" \
  -d '{"projectName":"demotest","englishName":"demotest","projectType":1,"description":"t","creator":"admin"}' \
  -w "\n%{http_code}\n" http://localhost:8080/project/api/user/projects/
docker exec bkci-mysql mysql -ubk_ci -pbk_ci123 -e "SELECT project_code FROM devops_ci_project.T_PROJECT"
```
Expected: bkrepo 响应非 404；建项目返回 code 0；`T_PROJECT` 出现 `demotest`（无回滚）。

- [x] **Step 11b.5: 重启后清单** 追加到 README：bkrepo 依赖 mongo 卷与别名 `bkrepo.local`；重建后 `register-frontend.sh` 之外无需额外注册。

**若 Step 11b.2/11b.4 因鉴权握手（repository 的 `PermissionManager` 是否接受 bk-ci 头）失败**：回退到
"接受限制"路径（Task 11 记为已知限制），进入 Task 12/13，并在 README 记录。**不得虚报成功。**

---

### Task 12: 安装默认插件（9 个，已完成 9/9）

**Files:** 无（数据写入 store/artifactory）

- [x] **Step 12.1: 确认 store/artifactory 就绪**

```bash
GW=http://localhost:8080
curl -s -o /dev/null -w "%{http_code}\n" \
  -H "X-DEVOPS-TOKEN: devops" -H "X-DEVOPS-UID: admin" \
  "$GW/store/api/service/pipeline/atom/codes/checkout/versions/1.0.0"
docker logs bkci-store 2>&1 | tail -3
```

Expected: `200`（store 就绪）。**注意**：路径必须带服务前缀 `/store`；`/api/service/...` 不匹配网关后端路由，会返回 502（并非 store 故障）。

结果（2026-10-23）：`200`；store 已注册 Consul 且监听 `21918`。

- [x] **Step 12.2: （如需）生成 JWT — 结论：本部署不需要**

**实测**：op 路由 `/auth/op` 校验的是 `bk_token` Cookie（`auth_op.lua`），JWT 头无法通过；因此改用直连 store 容器调用 op 接口。`bkenv.properties` 中已有 RSA 密钥（Step 5.2 生成），`BK_CI_JWT_ENABLE` 已于验证后回退为 `false`。

以下为原始备用流程（仅供参考）：
```bash
cd /home/xsg/aicode/bk-ci/deploy/local
eval "$(bash ../../docker-images/core/ci/ci-docker/scripts/bk-ci-gen-jwt-env.sh)"
# 把输出的两行 KEY=VALUE 追加到 deploy/local/bkenv.properties（勿提交私钥到公开仓库）
grep -q BK_CI_JWT_RSA_PRIVATE_KEY bkenv.properties || cat >> bkenv.properties <<EOF
BK_CI_JWT_RSA_PRIVATE_KEY="$BK_CI_JWT_RSA_PRIVATE_KEY"
BK_CI_JWT_RSA_PUBLIC_KEY="$BK_CI_JWT_RSA_PUBLIC_KEY"
BK_CI_JWT_ENABLE=true
EOF
# 重新渲染（Step 5.3）并滚动重启后端
docker compose up -d --force-recreate process project store artifactory auth openapi
JWT_TOKEN=$(cd ../../docker-images/core/ci/ci-docker && bash scripts/bk-ci-gen-jwt-token.sh "$BK_CI_JWT_RSA_PRIVATE_KEY" "init-plugin")
echo "TOKEN=$JWT_TOKEN"   # 10 分钟有效
```

- [x] **Step 12.3: 下载并部署 9 个插件（已完成 9/9）**

```bash
cd /tmp/opencode && mkdir -p atoms && cd atoms
BASE=https://ghfast.top/https://github.com/TencentBlueKing
curl -sL -o checkout.zip     $BASE/ci-checkout/releases/download/v2.0.13/checkout_en.zip
curl -sL -o run.zip          $BASE/ci-run/releases/download/v1.0.5/run-v1.0.5.zip
curl -sL -o SubPipelineExec.zip $BASE/ci-SubPipelineExec/releases/download/v1.0.6/ci-SubPipelineExec_en.zip
curl -sL -o uploadArtifact.zip  $BASE/ci-uploadArtifact/releases/download/v2.0.1/uploadArtifact_en.zip
curl -sL -o uploadReport.zip    $BASE/ci-uploadReport/releases/download/v1.0.1/uploadReport_en.zip
curl -sL -o AcrossProjectDistribution.zip $BASE/ci-AcrossProjectDistribution/releases/download/v1.1.1/AcrossProjectDistribution_en.zip
curl -sL -o downloadArtifact.zip $BASE/ci-downloadArtifact/releases/download/v1.0.2/downloadArtifact_en.zip
curl -sL -o PerforceSync.zip $BASE/ci-plugin-perforce-sync/releases/download/v1.0.13/PerforceSync_en.zip
curl -sL -o CodeCCCheckAtom.zip $BASE/ci-CodeCCCheckAtom/releases/download/v0.0.12/CodeCCCheckAtom_en.zip
ls -lh *.zip   # 每个应 ≥10KB（404 页面也可能是 HTML —— 用 file 命令确认是 Zip）
```

**CodeCCCheckAtom 说明（2026-10-23）**：官方 `ci-CodeCCCheckAtom` 仓库 API 返回 404，`v0.0.12`/`v0.2.1` 资产经 ghfast 均为 404（仓库已删除）。改用公开 fork `huangjiao-heart/CodeCCCheckAtom`（2021-07 源码）自行构建插件包：前端 `node:14-alpine` + npmmirror 构建；后端用 `gradle:6.9-jdk8` 容器构建（原 gradle 4.8.1/JDK8 因 PKIX 证书失败，且仓库缺 `shadow:5.1.0`，需补 `https://plugins.gradle.org/m2`）。为兼容 v4.2 store，在 `task.json` 中补 `releaseInfo`（`logoUrl` 用包内 `file/codeCC.png`，`frontendType=SPECIAL`），产物见 `/tmp/opencode/atoms/CodeCCCheckAtom.zip`。安装后已设默认并验证 `defaultFlag=true`。注意该 fork 为旧版（JDK8/2021），仅完成安装验证；流水线运行时兼容性未验证。

部署（op 接口走网关需登录 Cookie，因此**直连 store 容器**；`X-DEVOPS-UID: admin` 为 op 接口约定）：

```bash
STORE_PORT=21918
for code in checkout run SubPipelineExec uploadArtifact uploadReport AcrossProjectDistribution downloadArtifact PerforceSync CodeCCCheckAtom; do
  docker cp /tmp/opencode/atoms/$code.zip bkci-store:/tmp/$code.zip
  docker exec bkci-store curl -sS -XPOST "http://127.0.0.1:$STORE_PORT/api/op/pipeline/atom/deploy" \
    -H "X-DEVOPS-UID: admin" -F atomCode=$code -F file=@/tmp/$code.zip
  echo " <= deploy $code"
  docker exec bkci-store curl -sS -XPOST "http://127.0.0.1:$STORE_PORT/api/op/pipeline/atom/default/atomCodes/$code" \
    -H "X-DEVOPS-UID: admin"
  echo " <= default $code"
done
```

Expected: 两个接口均返回 `{"status":0,"data":true}`；重复 deploy 报"版本已存在"可忽略。
注意：插件包内 `releaseInfo.versionInfo.version` 均为 `1.0.0`（仓库 release tag 如 v2.0.13 不是插件版本号）。

结果（2026-10-23）：9 个插件全部安装并设为默认；store 插件总数 26（17 个内置 + 9 个新装）。CodeCCCheckAtom 由公开 fork 构建，构建/补 `releaseInfo` 步骤见上方说明。

- [x] **Step 12.4: 验证插件可被流水线编排使用**

```bash
GW=http://localhost:8080
curl -s -H "X-DEVOPS-TOKEN: devops" -H "X-DEVOPS-UID: admin" \
  "$GW/store/api/service/pipeline/atom/codes/checkout/versions/1.0.0" | head -c 300; echo
```
Expected: JSON 含 `"atomCode":"checkout"`。UI 新建流水线时插件选择器应出现 `checkout`/`run` 等。

结果（2026-10-23）：9 个插件逐一查询均返回 `status:0` 且含正确 `atomCode`；`defaultFlag=true`。CodeCCCheckAtom 查询结果：`atomCode=CodeCCCheckAtom`、`version=1.0.0`、`atomStatus=RELEASED`、`defaultFlag=true`。

---

### Task 13: 可选服务（wave B）与最终验收

**Files:** 无（compose 追加 4 个服务，按需）

- [ ] **Step 13.1: 按需启动 wave B**

`ai`（AI 助手，需 LLM 环境变量否则仅空转）、`buildless`、`dockerhost`、`agentless`（Docker 构建资源）。追加到 compose（复制一行 wave A 格式，如 `ai: { <<: *backend, container_name: bkci-ai, command: ["/bin/bash", "/entrypoint.sh", "ai"] }`），`docker compose up -d ai` 并按 Task 9.2 方式验证日志。**`assembly` 不启动**（单体包与 wave A 服务重复）。

- [x] **Step 13.2: 全栈健康总览**

```bash
cd /home/xsg/aicode/bk-ci/deploy/local
docker compose ps --format 'table {{.Name}}\t{{.Status}}' | sort
curl -s http://localhost:8500/v1/agent/services | grep -o '"Service":"[a-z]*"' | sort | uniq -c
docker compose logs --since 5m 2>&1 | grep -ciE "APPLICATION FAILED|OutOfMemory" || true
```

Expected: 全部 `Up`（healthy 标记的都 healthy）；Consul 服务数 ≥17+frontend；近 5 分钟无启动失败/OOM。

- [x] **Step 13.3: 验收清单（API 级，2026-10-26）**

- [x] `http://localhost:8080/console/` 返回 200；`demotest` 项目已创建
- [x] 9 个默认插件均可经 store service 接口查询，`status=0`、`defaultFlag=true`
- [x] 已保存并触发流水线；build #14（`b-65889176dd294c0aa5a9591e499099ef`）stage-1/2/3 全部 `SUCCEED`，日志接口返回 330 行（含 `build A`/`build B`/`run lint`/`run unit tests`）
- [x] 运行中容器均为 `Up`；`engine` 因与 process 重复消费被放入 `legacy-engine` profile 并保持停止
- [ ] 浏览器人工走查：建项目→新建流水线→选插件→触发→在构建详情页查看日志（当前仅完成 API 级验证）

- [x] **Step 13.4: 写运维手册**

创建 `deploy/local/README.md`：

```markdown
# bk-ci 本地 Docker 部署（v4.2.0-rc.7）

## 启停
cd deploy/local
docker compose up -d            # 全量
docker compose up -d mysql redis es rabbitmq consul dnsmasq   # 仅基础设施
docker compose stop / down      # 停止 / 停止并删数据卷（down -v 危险：清空数据库）

## 访问
控制台: http://localhost:8080/console/   (鉴权: sample 本地 mock)
Consul UI: http://localhost:8500

## 日志
docker compose logs -f process          # 单服务
docker compose logs --since 30m | grep -i error

## 重启后必做
FE_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' bkci-frontend)
curl -s -X PUT http://localhost:8500/v1/agent/service/register \
  -d "{\"Name\":\"frontend\",\"Address\":\"$FE_IP\",\"Port\":80,\"Tags\":[\"devops\"]}"

## 渲染配置改动
vi bkenv.properties && # 重新渲染:
set -a && . ./bkenv.properties && set +a && export INSTALL_PATH="$PWD/rendered" &&
../../docker-images/core/ci/ci-docker/scripts/render_tpl ../../docker-images/core/ci/ci-docker/support-files/templates/#etc#ci#*.yml
docker compose up -d --force-recreate <变更涉及的服务或 gateway/frontend>

## 常见故障
- ES 起不来: sudo sysctl -w vm.max_map_count=262144 && docker compose up -d es
- 某服务连 127.0.0.1:3306: 渲染/挂载问题 → 重跑渲染, 检查 rendered/etc/ci/application-<ms>.yml
- 网关 502: docker logs bkci-dnsmasq; curl localhost:8500/v1/agent/services
- 内存不足: docker compose ps 查 OOMKilled, 给该服务加 JAVA_TOOL_OPTIONS=-Xmx384m
```

- [ ] **Step 13.5: （询问用户后执行）提交 deploy/local 到 fork**

```bash
cd /home/xsg/aicode/bk-ci
git status --short
# 仅在用户确认后:
git add deploy/local docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md
git commit -m "deploy: 本地 docker compose 部署配置与实施计划"
git push mine master
```

**不要**提交：`bkci-slim.tar.gz`（489M 发布物）、`docker-images/core/ci/ci-docker/`（解包目录）、`deploy/local/rendered/`（渲染产物，含环境值）。将三者写入 `.gitignore` 也在此步一并询问用户。

---

## 自查（计划制定者已执行）

1. **覆盖检查**：用户需求"构建镜像+本地完整起服务" → Task 2–4（构建）、Task 5–10（起服务）、Task 11（冒烟）、Task 12（插件，流水线可用的前提）、Task 13（验收）✓；release 资产命名不一致 → Task 2 手动解包 ✓；无官方 compose → Task 6 全量给出 ✓；网络受限（GitHub）→ 全部下载步骤走 `ghfast.top` 前缀 ✓。
2. **占位符扫描**：无 TBD/TODO；分支步骤（Task 9.2/10.2/11.x/12.2）均给出确切命令与两种结果的处置，运行时未知量（router 实现、0001 细节、sample 登录行为）以"先读文件再二选一"形式写实，不留空。
3. **一致性检查**：端口（8080 网关 / 21921 process 等取自 bkenv 默认）、库名（`devops_ci_process`）、镜像 tag（`v4.2.0-rc.7`）、路径（`/etc/bkci/conf`、`/data/workspace`）、变量名（`SPRING_CLOUD_CONSUL_HOST`、`BK_CI_*`）前后一致；compose anchor 字段与 Task 5/6 挂载路径互相咬合。

---

## 附录：实施总结（2026-10-23）

### 整体目标
在 `/home/xsg/aicode/bk-ci` 使用 Docker Compose 本地部署 **bk-ci v4.2.0-rc.7**，使其能正常访问控制台、创建项目、使用默认插件并具备流水线编排能力。

### 执行步骤与过程

#### 1) 镜像构建与基础准备（Task 1-4）
| 步骤 | 内容 | 结果 |
|---|---|---|
| Task 1-2 | 获取 `bkci-slim.tar.gz` 等发布物，手动解包（release 命名不一致），基于源码/发布物构建本地镜像：`bkci-local/bkci-backend:v4.2.0-rc.7`、`bkci-local/bkci-frontend:v4.2.0-rc.7`、`bkci-local/bkci-gateway:v4.2.0-rc.7` | 成功，镜像构建完成 |
| Task 3-4 | 准备基础设施镜像（`mysql:8.0.37`、`redis:7.2-alpine`、`rabbitmq-with-delay`、`elasticsearch:7.17.22`、`consul:1.18`、`dnsmasq`） | 就绪 |

#### 2) 配置、渲染与编排（Task 5-10）
| 步骤 | 内容 | 结果 |
|---|---|---|
| Task 5 | 准备 `deploy/local/bkenv.properties`，配置各服务连接、域名、密钥等。涉及 JWT 密钥生成（后续验证后回退为 `BK_CI_JWT_ENABLE=false`） | 配置完成 |
| Task 6 | 编写 `deploy/local/docker-compose.yml`，采用 anchor 复用后端配置，定义 wave A 全量服务 | 编排文件完成 |
| Task 7-8 | 准备挂载目录、环境变量，使用 `docker-images/core/ci/ci-docker/scripts/render_tpl -m .` 配合 `INSTALL_PATH="$PWD/rendered"` 渲染模板生成 `rendered/etc/ci/*.yml` | 渲染成功 |
| Task 9-10 | 按顺序启动基础设施（mysql/redis/rabbitmq/es/consul/dnsmasq）→ 后端微服务（process/project/store/auth 等）→ gateway/frontend。过程中修复多处网关路由、Consul 域名、前端接线等问题 | 全部 wave A 服务启动成功 |

#### 3) 端到端冒烟与 BkRepo（Task 11、Task 11b）
| 步骤 | 内容 | 结果 |
|---|---|---|
| Task 11 | 控制台访问、API 冒烟。发现创建项目时 `SimpleProjectExtService` 无条件调用制品库接口导致建项目失败 | 识别到阻塞点 |
| Task 11b（计划外新增，经同意） | 部署 **BkRepo 3.8.9-rc.2**（`bkci-bkrepo-auth/gateway/repository/mongo`），配置 `BK_CI_BKREPO_AUTHORIZATION`，打通建项目链路。修复宿主机/frontend 与 Consul 注册问题（使用 `register-frontend.sh` + 重启 gateway） | 建项目成功，控制台可正常使用 |

#### 4) 默认插件安装（Task 12）
| 步骤 | 内容 | 结果 |
|---|---|---|
| Task 12.1 | 确认 store/artifactory 就绪（网关需带 `/store` 前缀） | 就绪 |
| Task 12.2 | 实测发现 op 接口走 `auth/op` 需 `bk_token` Cookie 而非 JWT Header，改用**直连 store 容器** 调用 `/api/op/pipeline/atom/...`。JWT 相关配置验证后回退关闭 | 确定正确调用方式 |
| Task 12.3 | 下载并部署官方 8 个插件：`checkout`、`run`、`SubPipelineExec`、`uploadArtifact`、`uploadReport`、`AcrossProjectDistribution`、`downloadArtifact`、`PerforceSync`。**CodeCCCheckAtom** 官方仓库/Release 已 404。改用公开 fork `huangjiao-heart/CodeCCCheckAtom`：用 `node:14-alpine` 构建前端，用 `gradle:6.9-jdk8` 容器构建后端（原 gradle 4.8.1 因 PKIX 证书失败，补充 `plugins.gradle.org/m2`），并为旧版 `task.json` 补充 `releaseInfo`（`frontendType=SPECIAL`、logo 使用包内 `file/codeCC.png`）、修复 `deFmands` -> `demands` 等字段后打包部署并设为默认 | **全部 9 个插件安装并设为默认** |
| Task 12.4 | 经网关 service 接口逐一验证全部 9 个插件 | 全部 `status:0`、`atomCode` 正确、`defaultFlag=true` |

#### 5) 健康检查（Task 13.2）
| 步骤 | 内容 | 结果 |
|---|---|---|
| Task 13.2 | 检查 `docker compose ps`、Consul 注册、近 5 分钟日志 | 全部 `bkci-*` `Up`（mysql/rabbitmq/redis/es/frontend healthy），Consul 注册 **25** 个服务，近 5 分钟无 `APPLICATION FAILED`/`OutOfMemory` |

### 最终成果
- **环境可用**：控制台可通过宿主机 nginx 转发访问 `http://<服务器IP>/console/`（网关暴露 8080，宿主机 nginx 实际对外代理）
- **项目创建**：已可成功创建项目（bkrepo 已打通）
- **插件就绪**：流水线插件选择器可见全部 **9** 个默认插件，均已设为默认
- **配置文档**：更新 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md`（Task 12 标记 9/9，Task 13.2 标记完成）及 `deploy/local/README.md`（补充默认插件说明、补装命令、CodeCC 构建说明及已知限制）

### 遗留问题与待办（细化）

#### 必要待办（建议完成）
| 项目 | 状态 | 说明 | 建议处理方式 |
|---|---|---|---|
| **Task 13.1 - Wave B** | 未做（按需） | `ai`、`buildless`、`dockerhost`、`agentless` 等可选服务。当前环境**没有构建机/编译环境**，触发流水线时 `dispatch` 会找不到构建资源而排队等待 | 若要真正跑通 `echo hello` 等构建任务再启用。可先注册第三方构建机（agent）或启动 `dockerhost`。`assembly` 明确不启动（与 wave A 重复） |
| **Task 13.3 - 最终 UI 验收** | 未做（人工操作） | 需在浏览器完成：建项目 → 新建流水线 → 选用默认插件 → 触发最简流水线（如 `echo hello`）→ 确认构建详情页可见执行步骤及日志 | 建议在当前可访问的控制台上走一遍全流程验证。若一直处于"等待构建资源"也属于链路打通（process/dispatch 正常派发） |
| **Task 13.4 - 运维手册** | 部分完成 | `deploy/local/README.md` 已大幅更新（启动/停止、渲染、常见故障、默认插件等） | 基本够用，如需更正式的"运维手册"可按计划 13.4 模板再补充，但当前已覆盖日常启停、重渲染、排障要点 |

#### 需用户确认后执行
| 项目 | 状态 | 说明 | 建议处理方式 |
|---|---|---|---|
| **Task 13.5 - 提交到 Git** | 未做（需确认） | 仅在用户确认后提交 `deploy/local/` 和 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md`。**严禁**提交 `deploy/local/rendered/`（含环境密钥/配置）、`bkci-slim.tar.gz`（489M）、解包目录（`docker-images/core/ci/ci-docker/` 等） | 建议先确认是否要提交，若提交需一并考虑将上述大文件/渲染产物加入 `.gitignore` |

#### 已知风险与遗留问题
| 问题 | 严重度 | 说明 | 建议 |
|---|---|---|---|
| **CodeCCCheckAtom 运行时兼容性** | 中 | 使用 2021 年的公开 fork 自行构建，目标环境是 bk-ci v4.2.0-rc.7（JDK17）。仅验证了**安装、上架、设为默认**，**未验证真实流水线运行** | 首次用到该插件时密切关注构建日志、类加载/SDK 兼容报错。若报错可考虑换用合适版本或暂时不使用该插件 |
| **前端 Consul 注册易丢失** | 低 | 历史上曾出现 `frontend` 从 Consul 消失导致网关转发 502 的情况，之前用 `register-frontend.sh` 修复 | 重启宿主机、重启部分容器或网关异常时可重新执行 `./register-frontend.sh && docker compose restart gateway` |
| **宿主机多套 Nginx** | 低（已解决） | 机器同时存在宿主机 `nginx`（:80）和 `bkci-gateway` 容器 `openresty`（映射 :8080）。远程访问需走宿主机 nginx 转发或直接放行 8080。当前已可正常远程访问 | 如后续改动站点配置需注意避免把 80 配置成冲突的 upstream |
| **渲染产物敏感** | 低 | `deploy/local/rendered/` 含渲染后的配置（涉及密钥、内部地址等） | 严格不要提交到仓库，保持本地使用即可 |
| **Consul 注册残留** | 已解决 | 容器重建后 Consul 会保留旧 IP 实例，网关可能转发到失效 IP 导致 502。已新增 `deploy/local/consul-cleanup.sh`（支持 `--dry-run`），按当前容器 IP 清理残留 | 容器重建/重启后运行 `./consul-cleanup.sh`，README 已列为重启后第 3 步 |
| **前端 locale 文件名不匹配** | 已解决 | 后端 `locales/get` 返回 `zh_CN`，控制台启动脚本原样写入 `window.INIT_LOCALE`，前端资源实际文件名为 `zh-CN.json`，导致 `/codelib/zh_CN.json` 等 404、codelib 页面打不开。已在 `frontend#console#index.html` 启动脚本中把 `_` 统一替换为 `-`，并同步修正 `src/frontend/locale/index.js` 的默认 locale 归一化与别名表 | 已重建 frontend 镜像并重新注册 Consul；浏览器需硬刷新以加载新 `index.html` |
| **构建资源缺失** | 中（取决于验收需求） | 若要完整走通"构建详情页有日志并成功"需构建机资源。当前仅验证了编排、插件、建项目等前置链路 | 按实际需求决定是否做 13.1 或注册 agent |

### 2026-10-23 续：RabbitMQ 事件丢失与 stage-2 排查

#### 1) RabbitMQ: `x-delayed-message` 插件未启用（已修复）

**现象**：构建创建后长期停留在 `QUEUE`；engine 收不到 `PipelineBuildStartEvent`，日志反复出现 `Failed to declare queue` / `unknown exchange type 'x-delayed-message'`。

**根因**：镜像内已带 `rabbitmq_delayed_message_exchange 3.8.9+1.g8f537ac`，但默认**未启用**。所有业务 exchange 都声明为 `x-delayed-message`，声明失败后队列只绑定到默认 exchange，构建事件无法路由。

**修复**：
1. 运行中的容器内启用插件：
   ```bash
   docker exec bkci-rabbitmq rabbitmq-plugins enable rabbitmq_delayed_message_exchange
   ```
2. 在 `deploy/local/docker-compose.yml` 的 `rabbitmq` 服务增加 command，容器重建后也生效：
   ```yaml
   command: ["sh", "-c", "rabbitmq-plugins enable --offline rabbitmq_delayed_message_exchange && exec rabbitmq-server"]
   ```
3. 删除此前手工创建的 topic exchange/queue（保留 `amq.*`、`openapiLogEventConsumer-out-0`、`configPropsSingleton-out-0`），重启全部后端服务。重启后 97 个 exchange 均以 `x-delayed-message` 正确重建，构建事件恢复。

#### 2) 构建启动已打通，stage-1 成功

- 流水线：`p-17fdae4c01774adaa693dc36c3872352`（`complex-demo-pipeline`，项目 `demotest`）。
- 构建 num6 `b-686fba18e00b4ff19619e44730e811cd`：已进入 RUNNING，stage-1 SUCCEED，stage-2 FAILED。
- 说明 process → engine → dispatch 的事件链路已经正常。

#### 3) 当前卡点：stage-2 的 VM 容器缺少 `dispatchType`

**现象**：stage-2 的 `startVM-1`、`startVM-2` 立即失败，任务错误码 `2189504`（构建机拉起出错）。

**根因**：engine 日志 `DispatchTypeBuilder.getDispatchType(DispatchTypeBuilder.kt:80)` 抛 `NullPointerException`。流水线模型里 3 个 `vmBuild` 容器都没有 `dispatchType`，也没有 `dockerBuildVersion`，代码走到 `DockerDispatchType(param.dockerBuildVersion!!)` 时为空指针。

**已做**：直接更新 `devops_ci_process.T_PIPELINE_RESOURCE_VERSION` 中该流水线 version 1 的 `MODEL`，为容器 1/2/3 补上：
```json
"dispatchType": {
  "buildType": "DOCKER",
  "value": "bkci/ci:latest",
  "imageType": "BKDEVOPS"
},
"dockerBuildVersion": "bkci/ci:latest"
```
更新已落库（`MODEL like '%dispatchType%'` 为真），但新触发的构建 num7/num8 的 `T_PIPELINE_BUILD_TASK.TASK_PARAMS` 仍然没有 `dispatchType`，stage-2 依旧失败。

**下一步（明天从这里继续）**：
1. 确认模型读取是否有缓存/快照。直接改 DB 后 process/engine 可能仍读旧模型；优选通过正式 API 重新保存流水线，或重启 process/engine 使缓存失效。
2. 触发新构建后先验证：
   ```bash
   docker exec bkci-mysql mysql -ubk_ci -pbk_ci123 -N -r -e \
     'select TASK_ID,TASK_PARAMS from devops_ci_process.T_PIPELINE_BUILD_TASK where BUILD_ID="<buildId>" and TASK_ID like "startVM%";' 2>/dev/null
   ```
   确认 `TASK_PARAMS` 中包含 `dispatchType` / `dockerBuildVersion`。
3. 再跟踪 stage-2 容器是否真正拉起、`bkci/ci:latest` 是否可用、agent jar 是否下载成功。
4. 跑通 stage-2 后继续 stage-3 与 UI/质量红线验收。

**相关构建状态**：
- num7 `b-70e5b35e1d6f45fb85afa3bb2165206d`：FAILED（stage-2 同样 2189504）。
- num8 `b-950c0849509e43b9bac33d2f95e77582`：FAILED，`TASK_PARAMS` 仍旧值，验证了模型重载问题尚未解决。

### 2026-10-26 续：stage-2/3 与构建日志已跑通

**结果**：build #14 `b-65889176dd294c0aa5a9591e499099ef` 全流程成功。

- stage-1/2/3 的 `T_PIPELINE_BUILD_STAGE.STATUS` 均为 `0`（SUCCEED）。
- 两个 stage-2 容器和一个 stage-3 容器均从本地 registry 拉取 `127.0.0.1:5000/bkci/ci:jdk17`；容器内 Java 为 Temurin 17.0.19，agent 以 `-Ddevops.gateway=http://172.20.4.188:8080` 启动。
- stage-2 的 `buildResult=true`，日志中可见 `build A on ...`、`build B on ...`；stage-3 可见 `run lint`、`run unit tests`。
- 构建日志接口 `/log/api/user/logs/...` 返回 330 行、`finished=true`。

**期间修复的两个问题**：

1. **RabbitMQ 重置后日志消费者未恢复**：`log` 服务的 AMQP 消费者因认证失败停止，`default.build.log.*` 队列 `consumers=0`，构建成功但无日志。`docker restart bkci-log` 后消费者恢复，积压事件补消费并写入 ES。
2. **process 与 engine 重复消费**：`boot-process` 已依赖 `biz-engine`，独立 `engine` 会重复消费 START/stage 事件。已在 compose 中给 `engine` 加 `profiles: ["legacy-engine"]`，默认不启动；`common.yml` 保留 `bkScs.consumer.concurrency.*: 1` 作为保护。

**当前状态一句话总结**
**部署、BkRepo、9 个默认插件、RabbitMQ 事件链路、JDK17 构建镜像与 stage-1/2/3 均已打通；build #14 成功且日志可查。剩余仅为浏览器人工 UI 走查与用户确认后的 Git 提交。**
