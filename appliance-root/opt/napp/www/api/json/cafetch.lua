http:status(200, "OK")
http:header("Content-Type", "application/json")
local req = http:request()
local json = require("json")
local post = req:form()
local out = {}

if post == nil or (post.type ~= 'ca' and post.type ~= 'crl') then
  out = { status="failed", error="bad parameters posted to cafetch" }
else
  local url = circonus_url()
  if post.circonus_url ~= nil and url ~= post.circonus_url then
    -- set us a new API url
    url = post.circonus_url
    noit.conf_get_string("/noit/circonus/appliance/circonus_url", url)
  end
  local status, error = fetchCA(post.type, url)
  if status then
    out = { status="success" }
  else
    out = { status="failed", error=error }
  end
end

http:write(json.encode(out))
