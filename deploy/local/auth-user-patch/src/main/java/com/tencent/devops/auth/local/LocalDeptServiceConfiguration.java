/*
 * 本地部署补丁（不属于 bk-ci 业务源码）。
 *
 * 社区版没有注册读取用户中心的 DeptService，Spring 会选中
 * DefaultDeptServiceImpl.getUserInfo() 直接返回 null，导致 rbac 模式下
 * 申请权限接口以 2121090 失败。这里启用 bk-ci 已有的 AuthDeptServiceImpl，
 * 让它从 devops_ci_auth.T_USER_INFO 读取本地预置的 admin 用户。
 */
package com.tencent.devops.auth.local;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.tencent.devops.auth.service.AuthDeptServiceImpl;
import com.tencent.devops.auth.service.DeptService;
import com.tencent.devops.auth.service.UserManageService;
import com.tencent.devops.common.redis.RedisOperation;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;

@Configuration
public class LocalDeptServiceConfiguration {

    @Bean
    @Primary
    public DeptService localAuthDeptService(
        RedisOperation redisOperation,
        ObjectMapper objectMapper,
        UserManageService userManageService
    ) {
        return new AuthDeptServiceImpl(redisOperation, objectMapper, userManageService);
    }
}
