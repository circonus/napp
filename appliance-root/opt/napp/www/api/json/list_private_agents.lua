local req = http:request()
local post = req:form()

http:header('Content-Type', 'application/json')
local code, data = list_private_agents(post)
http:status(code, "PROXIED")
http:write(data)

