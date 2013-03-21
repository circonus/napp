local json = require("json")
local req = http:request()
local log = req:querystring("log") or ""
local files = noit.readdir('/opt/napp/etc/updatelogs/',
  function(file) return file == log end
)

http:header('Content-Type', 'text/plain')
if files == nil or files[1] == nil then
  http:status(404, "NOT FOUND")
  http:write("The log '" .. log .. "' is not an option")
else
  local fd, errno = noit.open('/opt/napp/etc/updatelogs/' .. files[1],
                              bit.bor(O_RDONLY,O_NOFOLLOW))
  if(fd == nil) then
    http:status(404, "NOT FOUND")
  else
    http:write_fd(fd)
    noit.close(fd)
  end
end
