package com.tencent.bk.devops.iamstub.api

import com.tencent.bk.devops.iamstub.data.ApplicationRepo
import com.tencent.bk.devops.iamstub.data.TicketRepo
import org.springframework.http.MediaType
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RestController
import org.springframework.web.util.HtmlUtils

@RestController
class IframePageController(
    private val applicationRepo: ApplicationRepo,
    private val ticketRepo: TicketRepo
) {

    @GetMapping("/iam-stub/apply", produces = ["text/html;charset=UTF-8"])
    fun applyPage(): String {
        val rows = applicationRepo.findByStatus("PENDING").joinToString("\n") { app ->
            """
            <tr>
              <td>${esc(app.sn)}</td><td>${esc(app.applicant)}</td><td>${esc(app.groupIds)}</td><td>${esc(app.status)}</td>
              <td><button onclick="approve(${app.id}, true)">通过</button>
                  <button onclick="approve(${app.id}, false)">驳回</button></td>
            </tr>
            """.trimIndent()
        }
        return page(
            "我的申请（IAM 用户组）",
            "<tr><th>单号</th><th>申请人</th><th>用户组</th><th>状态</th><th>操作</th></tr>\n$rows",
            """
            function approve(id, ok) {
              fetch('/stub/api/approve-group', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({id: id, approved: ok})
              }).then(function(r) { return r.json(); }).then(function() { location.reload(); });
            }
            """
        )
    }

    @GetMapping(
        value = ["/itsm-stub/", "/itsm-stub/index.html"],
        produces = [MediaType.TEXT_HTML_VALUE]
    )
    fun approvalPage(): String {
        val rows = ticketRepo.findAll().joinToString("\n") { ticket ->
            """
            <tr>
              <td>${esc(ticket.sn)}</td><td>${esc(ticket.status)}</td>
              <td><button onclick="approve('${esc(ticket.sn)}', true)">通过</button>
                  <button onclick="approve('${esc(ticket.sn)}', false)">驳回</button></td>
            </tr>
            """.trimIndent()
        }
        return page(
            "我的审批（ITSM 项目审批）",
            "<tr><th>工单号</th><th>状态</th><th>操作</th></tr>\n$rows",
            """
            function approve(sn, ok) {
              fetch('/itsm-stub/api/approve', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({sn: sn, approved: ok, callbackUrl: ''})
              }).then(function(r) { return r.json(); }).then(function() { location.reload(); });
            }
            """
        )
    }

    private fun page(title: String, tableBody: String, script: String): String = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <title>${esc(title)}</title>
          <style>
            body { font-family: sans-serif; margin: 16px; color: #313238; }
            h1 { font-size: 18px; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #dfe4ea; padding: 8px 10px; text-align: left; }
            th { background: #f5f7fa; }
            button { margin-right: 6px; cursor: pointer; }
          </style>
        </head>
        <body>
          <h1>${esc(title)}</h1>
          <table>$tableBody</table>
          <script>$script</script>
        </body>
        </html>
    """.trimIndent()

    private fun esc(value: String?): String = HtmlUtils.htmlEscape(value ?: "")
}
