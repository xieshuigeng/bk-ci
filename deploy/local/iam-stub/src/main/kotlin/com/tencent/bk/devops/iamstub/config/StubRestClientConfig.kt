package com.tencent.bk.devops.iamstub.config

import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.web.client.RestTemplate

@Configuration
open class StubRestClientConfig {
    @Bean
    open fun restTemplate(): RestTemplate = RestTemplate()
}
