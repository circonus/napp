http:header('Content-Type', 'application/json')
local json = require("json")

local p, inp, out, err = noit.spawn('/opt/napp/etc/check-for-updates',
                                   { 'check-for-updates' }, {} )

local status = 'error'
local packages = {}
if out ~= nil then
  while true do
    local line = out:read("\n")
    local name, version, source = line:match("([^%s]+)%s+([^%s]+)%s+(.+)")
    if name ~= nil and version ~= nil and source ~= nil then
      packages[# packages] = { name=name, version=version, source=source }
    end
  end

  status = 'idle'
  if noit.stat('/opt/napp/etc/doupdates') then
    status = 'requested'
  elseif noit.stat('/opt/napp/etc/doingupdates') then
    status = 'processing'
  end
end

http:write(json.encode({ status=status, packages=packages }))
