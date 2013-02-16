http:status(200, "OK")
http:header("Content-Type", "application/json")
local json = require("json")

local keyfile = noit.conf('//listeners//listener[@type="control_dispatch"]/ancestor-or-self::node()/sslconfig/key_file')
local out = { status="failed", error="config error, no keyfile" }
if keyfile ~= nil then
  local st, errno = noit.stat(keyfile)
  
  if st ~= nil then
    out = { status="success", detail="exists" }
  else
    local rv, error = generate_key(keyfile)
    if rv == 0 then
      out = { status="success", detail="created" }
    else
      out = { status="failed", error=error }
    end
  end
end

http:write(json.encode(out))
