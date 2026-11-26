package com.tencent.bk.devops.iamstub.config

import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter
import java.util.UUID

/**
 * IAM Java SDK 读取每个响应的 X-Request-Id；缺失时 bk-ci 会抛 NPE 并返回 400。
 */
@Component
class RequestIdFilter : OncePerRequestFilter() {
    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain
    ) {
        response.setHeader("X-Request-Id", UUID.randomUUID().toString())
        filterChain.doFilter(request, response)
    }
}
