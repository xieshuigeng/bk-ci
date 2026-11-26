-- 一次性本地权限数据预置：仅写 devops_ci_auth，不写桩自身的 H2 库。
-- 用法：docker exec -i bkci-mysql mysql -uroot -proot123 devops_ci_auth < deploy/local/iam-stub/setup-local-auth.sql
-- RELATION_ID 必须等于 IAM 桩种子组 id（10001），用户组申请链据此关联成员表。

INSERT INTO T_AUTH_RESOURCE_GROUP (
    PROJECT_CODE, RESOURCE_TYPE, RESOURCE_CODE, RESOURCE_NAME,
    IAM_RESOURCE_CODE, GROUP_CODE, GROUP_NAME, DEFAULT_GROUP, RELATION_ID, DESCRIPTION
)
SELECT 'stub-demo', 'project', 'stub-demo', 'stub-demo',
       'stub-demo', 'developer', 'Developer', b'0', '10001', 'local iam stub group'
WHERE NOT EXISTS (
    SELECT 1 FROM T_AUTH_RESOURCE_GROUP
    WHERE PROJECT_CODE = 'stub-demo'
      AND RESOURCE_TYPE = 'project'
      AND RESOURCE_CODE = 'stub-demo'
      AND GROUP_NAME = 'Developer'
);
