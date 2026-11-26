-- 一次性本地权限数据预置：仅写 devops_ci_auth，不写桩自身的 H2 库。
-- 用法：docker exec -i bkci-mysql mysql -uroot -proot123 devops_ci_auth < deploy/local/iam-stub/setup-local-auth.sql
-- 项目代码从 devops_ci_project.T_PROJECT 读取（本地默认为 demotest），避免硬编码不存在的项目。
-- RELATION_ID 必须等于 IAM 桩种子组 id（10001），用户组申请链据此关联成员表。

SET @project_code = (SELECT english_name FROM devops_ci_project.T_PROJECT WHERE deleted_at IS NULL ORDER BY ID LIMIT 1);

-- 清理旧版脚本留下的孤立项目行，避免同一 RELATION_ID 出现在两个项目下。
DELETE FROM T_AUTH_RESOURCE_GROUP
WHERE PROJECT_CODE = 'stub-demo' AND GROUP_NAME = 'Developer' AND RELATION_ID = '10001';

-- rbac 模式下“超管可见项目”从 T_AUTH_RESOURCE(resource_type='project') 读取；
-- 本地旧项目是 sample 模式创建的，表里没有这行，补上后我的项目/申请权限才不会空白。
INSERT INTO T_AUTH_RESOURCE (
    PROJECT_CODE, RESOURCE_TYPE, RESOURCE_CODE, RESOURCE_NAME,
    IAM_RESOURCE_CODE, ENABLE, RELATION_ID, CREATE_USER, UPDATE_USER
)
SELECT @project_code, 'project', @project_code, p.project_name,
       @project_code, b'1', '10001', 'system', 'system'
FROM devops_ci_project.T_PROJECT p
WHERE p.english_name = @project_code AND p.deleted_at IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM T_AUTH_RESOURCE
    WHERE PROJECT_CODE = @project_code
      AND RESOURCE_TYPE = 'project'
      AND RESOURCE_CODE = @project_code
  );

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

-- rbac 的申请权限接口会校验 deptService.getUserInfo(userId) 非 null。
-- 社区版没有用户中心，本地补丁启用的 AuthDeptServiceImpl 从该表读取用户资料，
-- 故预置网关注入的 admin。重复执行会刷新同一行，不会产生重复数据。
INSERT INTO T_USER_INFO (
    USER_ID, USER_NAME, ENABLED, DEPARTMENT_NAME, DEPARTMENT_ID,
    FULL_DEPARTMENTS, PATH, DEPARTED, TASK_ID
) VALUES (
    'admin', 'admin', b'1', '本地用户', 1,
    '[{"id":"1","name":"本地用户","full_name":"本地用户"}]', '1', b'0', 'local-seed'
)
ON DUPLICATE KEY UPDATE
    USER_NAME = VALUES(USER_NAME),
    ENABLED = VALUES(ENABLED),
    DEPARTMENT_NAME = VALUES(DEPARTMENT_NAME),
    DEPARTMENT_ID = VALUES(DEPARTMENT_ID),
    FULL_DEPARTMENTS = VALUES(FULL_DEPARTMENTS),
    PATH = VALUES(PATH),
    DEPARTED = VALUES(DEPARTED),
    TASK_ID = VALUES(TASK_ID);
