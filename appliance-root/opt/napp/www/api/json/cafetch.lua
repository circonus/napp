http:status(200, "OK")
http:header("Content-Type", "application/json")
local req = http:request()
local json = require("json")
local post = req:form()
local out = {}

local url = pki_url()
local try_url = url
if post.pki_url ~= nil then
  try_url = post.pki_url
end

if post == nil or (post.type ~= 'ca' and post.type ~= 'crl') then
  out = { status="failed", error="bad parameters posted to cafetch" }
else
  if post.type == 'ca' then try_url = try_url .. "/ca.crt"
  else try_url = try_url .. "/ca.crl" end
  local xpath = '//listeners//listener[@type="control_dispatch"]/ancestor-or-self::node()/sslconfig/'
  local file
  if post.type == "ca" then
    file = noit.conf(xpath .. "ca_chain")
  else
    file = noit.conf(xpath .. "crl")
  end
  if file == nil then
    out = { status="failed", error= post.type .. " not supported on this broker" }
  else
    local rv, error = fetch_url_to_file(try_url, file, tonumber(0644,8))
    if rv then
      out = { status="success" }
      if post.pki_url ~= nil and post.pki_url ~= url then
        noit.conf_get_string("/noit/circonus/appliance/pki_url", post.pki_url)
      end
    else
      out = { status="failed", error=error }
    end
  end
end

http:write(json.encode(out))
