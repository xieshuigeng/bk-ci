package com.tencent.bk.devops.iamstub.api

data class ResponseEnvelope<T>(
    val code: Long = 0,
    val message: String = "OK",
    val result: Boolean = true,
    val data: T? = null
) {
    companion object {
        fun <T> ok(data: T): ResponseEnvelope<T> = ResponseEnvelope(data = data)
    }
}
