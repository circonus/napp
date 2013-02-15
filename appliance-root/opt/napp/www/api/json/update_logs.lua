http:header('Content-Type', 'application/json')
local json = require("json")
local files = noit.readdir('/opt/napp/etc/updatelogs/',
  function(file) return file:match("^[%d]+%.log$") ~= nil end
)

http:write(json.encode(files));
