--[[
Tencent is pleased to support the open source community by making BK-CI 蓝鲸持续集成平台 available.

Copyright (C) 2019 Tencent.  All rights reserved.

BK-CI 蓝鲸持续集成平台 is licensed under the MIT license.

A copy of the MIT License is included in this file.


Terms of the MIT License:
---------------------------------------------------
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]

config = {
  static_dir = "/data/workspace/frontend",
  home_dir = "/data/workspace",
  service_name = "",  -- 指定后台微服务名称，如果对接后端是boot-assembly的单体微服务，则该配置项为bk-ci, 否则请置空会自动路由相应微服务
  service_prefix = "bkrepo-", -- 微服务前缀
  allow_hosts = {
    ""
  },
  allow_headers = "Authorization,Content-Type,withcredentials,credentials,Accept,Origin,User-Agent,Cache-Control,Keep-Alive,X-Requested-With,If-Modified-Since,X-CSRFToken,X-DEVOPS-PROJECT-ID,X-DEVOPS-TASK-ID,X-BKREPO-UID,X-BKREPO-API-TYPE,X-BKREPO-FORCE-REFRESH",
  ns = {
    ip = {
      "consul"
    },
    port = "8600",
    http_port = "8500",
    domain = "consul",
    tag = "devops",
    nodes_url = "/v1/catalog/nodes"
  },
  oauth = {  -- 对接蓝鲸权限中心才需要的配置
    ip = "",
    env = "prod",
    port = "",
    host = "",
    url = "",     -- 接口路径
    app_code = "bk_ci",
    app_secret = "devops",
    apigw_url = ""
  },
  bkrepo = {
    authorization = "",
    domain = "bkrepo.local"
  },
  mode = "dev",
  auth_mode = "devops",
  bkci = {
    host = "devops.bktencent.com",
    port = "80"
  },
  mobileSiteToken = "",
  security_paths = {
  },
  redis = {
    host = "bkci-redis",
    port = "6379",
    pass = "", -- redis 密码，没有密码的话，把这行注释掉
    database = "0",
    pool_size = 5,                     -- 连接池的大小
    max_idle_time = 600000,            -- 保留在连接池的时间
    backlog = 100                     -- 连接等待队列
  },
  service_in_container = "",
  service_in_local = "",
  service_with_bandwidth_check = "false",
  container_url = "",
  enable_multi_tenant_mode = "false",
  op_tenant_id = "",
  bkapigw_public_key = ""
}
  
require("init_common")
require("ip_whitelist")
require("project_router")
