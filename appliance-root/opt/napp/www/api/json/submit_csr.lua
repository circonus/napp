local req = http:request()
local post = req:form()
local json = require('json')

local out = { status="failed", error="incomplete data", post=post }
if req:method() == "POST" and
   post['country_code'] ~= nil and post['state_prov'] ~= nil and
   post['account_name'] ~= nil and post['cn'] ~= nil then
  local subj = '/C=' .. post['country_code'] ..
               '/ST=' .. post['state_prov'] ..
               '/O=' .. post['account_name'] ..
               '/CN=' .. post['cn']
  local rv
  rv, err = generate_csr(subj)
  if rv == 0 then
    rv, body = submit_agent_csr(post)
    if rv == 200 then
      local pinfo = json.decode(body)
      if pinfo.status == "pending" or
         pinfo.error == "cannot provision pending noit" then
        out = { status="success", data=pinfo }
      else
        out = { status="failed", error=err }
      end
    else
      out = { status="failed", error=body }
    end
  else
    out = { status="failed", error=err }
  end
end

http:header('Content-Type', 'application/json')
http:write(json.encode(out))
