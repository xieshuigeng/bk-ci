#!/usr/bin/env bash
# 初始化 bkrepo 平台账号与管理员，供 bk-ci 通过平台认证调用 bkrepo API。
# 幂等；首次部署或清空 bkrepo-mongo-data 后执行一次即可。
# 平台账号凭据须与 bkenv.properties 的 BK_CI_BKREPO_AUTHORIZATION 保持一致：
#   Platform base64("bk_ci:devops") = Platform YmtfY2k6ZGV2b3Bz
set -euo pipefail

CONTAINER="${1:-bkci-bkrepo-mongo}"

docker exec -i "$CONTAINER" mongo --quiet bkrepo <<'JS'
const now = new Date();

db.account.updateOne(
  { appId: "bk_ci" },
  {
    $set: {
      _class: "com.tencent.bkrepo.auth.model.TAccount",
      appId: "bk_ci",
      locked: false,
      credentials: [{
        accessKey: "bk_ci",
        secretKey: "devops",
        createdAt: now,
        status: "ENABLE",
        authorizationGrantType: "PLATFORM"
      }],
      owner: "admin",
      authorizationGrantTypes: ["PLATFORM"],
      homepageUrl: "http://localhost",
      redirectUri: "http://localhost",
      avatarUrl: "",
      scope: ["PROJECT", "REPO", "NODE", "ENDPOINT", "SYSTEM"],
      limit: "MANAGE",
      // 允许该平台账号访问所有项目；空列表会导致项目级权限校验始终失败
      scopeDesc: [{ field: "PROJECT", value: "", operation: "PREFIX" }],
      description: "bk-ci platform account",
      lastModifiedDate: now
    },
    $setOnInsert: { createdDate: now }
  },
  { upsert: true }
);

// admin 默认由 bkrepo 在首次建项目时自动创建（admin=false）；
// devops 权限实现会优先把 admin=true 的用户视为超级管理员。
db.user.updateOne(
  { userId: "admin" },
  {
    $set: {
      _class: "com.tencent.bkrepo.auth.model.TUser",
      admin: true,
      locked: false,
      lastModifiedDate: now
    },
    $setOnInsert: {
      userId: "admin",
      name: "admin",
      pwd: "",
      tokens: [],
      roles: [],
      asstUsers: [],
      group: false,
      email: "",
      phone: "",
      accounts: [],
      source: "PAAS",
      createdDate: now,
      tenantId: null
    }
  },
  { upsert: true }
);

print("bkrepo bootstrap ok: account appId=bk_ci, user admin(admin=true)");
JS
