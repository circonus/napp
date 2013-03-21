local req = http:request()
local post = req:form()
local json = require('json')

local url = circonus_url()
if post.api_url ~= nil and url ~= post.api_url then
  -- set us a new API url
  url = post.api_url
  noit.conf_get_string("/noit/circonus/appliance/circonus_url", url)
end
http:header('Content-Type', 'application/json')
local code, data = list_accounts(post)
http:status(code, "PROXIED")
http:write(data)

