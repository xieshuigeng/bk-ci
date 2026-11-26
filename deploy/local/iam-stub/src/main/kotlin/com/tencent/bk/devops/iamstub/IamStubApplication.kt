package com.tencent.bk.devops.iamstub

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
open class IamStubApplication

fun main(args: Array<String>) {
    runApplication<IamStubApplication>(*args)
}
