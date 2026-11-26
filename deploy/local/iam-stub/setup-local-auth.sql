-- 一次性本地权限数据预置：仅写 devops_ci_auth，不写桩自身的 H2 库。
-- 用法：docker exec -i bkci-mysql mysql -uroot -proot123 devops_ci_auth < deploy/local/iam-stub/setup-local-auth.sql
-- 项目代码从 devops_ci_project.T_PROJECT 读取（本地默认为 demotest），避免硬编码不存在的项目。
-- RELATION_ID 必须等于 IAM 桩种子组 id（10001），用户组申请链据此关联成员表。

SET @project_code = (SELECT english_name FROM devops_ci_project.T_PROJECT WHERE deleted_at IS NULL ORDER BY ID LIMIT 1);

-- 清理旧版脚本留下的孤立项目行，避免同一 RELATION_ID 出现在两个项目下。
DELETE FROM T_AUTH_RESOURCE_GROUP
WHERE PROJECT_CODE = 'stub-demo' AND GROUP_NAME = 'Developer' AND RELATION_ID = '10001';

INSERT INTO T_AUTH_RESOURCE_GROUP (
    PROJECT_CODE, RESOURCE_TYPE, RESOURCE_CODE, RESOURCE_NAME,
    IAM_RESOURCE_CODE, GROUP_CODE, GROUP_NAME, DEFAULT_GROUP, RELATION_ID, DESCRIPTION
)
SELECT @project_code, 'project', @project_code, @project_code,
       @project_code, 'developer', 'Developer', b'0', '10001', 'local iam stub group'
WHERE @project_code IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM T_AUTH_RESOURCE_GROUP
    WHERE PROJECT_CODE = @project_code
      AND RESOURCE_TYPE = 'project'
      AND GROUP_NAME = 'Developer'
  );
