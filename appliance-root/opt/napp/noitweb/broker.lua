module(..., package.seeall)

local sessions = {}
local HttpClient = require('noit.HttpClient') 
local json = require('json')
local noit = require('noit')
local mtev = require('mtev')

function new_session()
  local uuid = noit.uuid()
  sessions[uuid] = { }
  sessions[uuid]["expires"] = os.time() + 86400
  return uuid
end

function generate_key(keyfile)
  local rsa = mtev.newrsa()
  if rsa == nil then
    return -1, "keygen failed"
  end
  local fd = noit.open(keyfile,
                       bit.bor(O_CREAT,O_TRUNC,O_WRONLY), tonumber(0600,8))
  if fd < 0 then
    return fd, "Could not store broker private key"
  end
  noit.write(fd, rsa:pem())
  noit.close(fd)
  noit.chmod(keyfile, tonumber(0400, 8))
  return 0
end

function generate_csr(subject, csrfile)
  local pki = pki_info()
  local inp = io.open(pki.key.file, "rb")
  if inp == nil then return -1, "could not open private key" end
  local keydata = inp:read("*all")
  inp:close();
  local key = mtev.newrsa(keydata)
  if key == nil then return -1, "private key invalid" end
  local subj = {}
  for k, v in string.gmatch(subject, "(%w+)=([^/]+)") do
    subj[k] = v
  end
  local req = key:gencsr({ subject=subj })
  
  local fd = noit.open(pki.csr.file,
                       bit.bor(O_CREAT,O_TRUNC,O_WRONLY), tonumber(0644,8))
  if fd < 0 then
    return fd, "Could not store broker CSR"
  end
  noit.write(fd, req:pem())
  noit.close(fd)
  noit.chmod(pki.csr.file, tonumber(0400, 8))
  return 0
end

function get_subject()
  local inp = io.open('/opt/napp/etc/ssl/appliance.csr', "rb")
  if inp == nil then return nil end
  local data = inp:read("*all")
  inp:close();
  if data == nil then return nil end
  local req = mtev.newreq(data)
  if req == nil then return nil end
  local cn = req.subject:match("CN=([^/\n]+)")
  return cn
end

function fetch_url(url)
  local callbacks = { }
  local client = HttpClient:new(callbacks)
  local body = ''
  callbacks.consume = function (str)
    body = body .. str
  end
  local port = 80
  local target
  local schema, host, uri = url:match("^(https?)://([^/]+)(/.*)$")
  if uri == nil then return false, nil, "could not parse URL" end
  target = host
  if schema == "https" then port = 443 end
  local hostwoport, aport = host:match("^(.*):(%d+)$")
  if (aport or 0) > 0 then
    target = hostwoport
    port = aport
  end
  if not noit.valid_ip(target) then
    local dns = noit.dns()
    local r = dns:lookup(host)
    if r == nil or r.a == nil then return false, nil, "could not resolve host" end
    target = r.a
  end
  client:connect(target, port, schema == "https", host)
  client:do_request("GET", uri, { Host=host })
  client:get_response()
  return true, client.code, body
end

function fetch_url_to_file(url, file, mode)
  local success, code, body = fetch_url(url)
  if not success then return success, body end
  if code ~= 200 then return false, "fetching url failed: HTTP CODE " .. code end
  if body:len() == 0 then return false, "fetching url failed: blank document" end
  -- fetch the previous contents
  local inp = io.open(file, "rb")
  if inp ~= nil then
    local data = inp:read("*all")
    inp:close();
    -- short-circuit if the contents haven't changed
    if data == body then return true end
  end

  local fd = noit.open(file, bit.bor(O_WRONLY,O_TRUNC,O_CREAT), mode)
  if fd >= 0 then
    local len, error = noit.write(fd, body)
    noit.close(fd)
    if len ~= body:len() then return false, "failed write: " .. (error or "unknown") end
    return true
  end
  return false, "failed to open target file for writing"
end

function fetchCA(type, new_pki_url)
  local url = circonus_url()
  local try_url = url
  if new_pki_url ~= nil then try_url = new_pki_url end
  try_url = string.gsub(try_url, "/*$", "")
  if type == 'ca' then try_url = try_url .. "/pki/ca.crt"
  else try_url = try_url .. "/pki/ca.crl" end
  local xpath = '//listeners//listener[@type="control_dispatch"]/ancestor-or-self::node()/sslconfig/'
  local file
  if type == "ca" then
    file = noit.conf(xpath .. "ca_chain")
  elseif type == "crl" then
    file = noit.conf(xpath .. "crl")
  else
    return false, "unsupported type"
  end
  if file ~= nil then
    noit.log("error", "Fetching -> " .. try_url .. "\n")
    local rv, error = fetch_url_to_file(try_url, file, tonumber(0644,8))
    if rv then
      if new_pki_url ~= nil and new_pki_url ~= url then
        noit.conf_get_string("/noit/circonus/appliance/circonus_url", new_pki_url)
      end
      return true
    end
    return false, error
  end
  return true, type .. " not supported on this broker"
end

function proxy_post(url, keys, form)
  local callbacks = { }
  local client = HttpClient:new(callbacks)
  local body = ''
  callbacks.consume = function (str)
    body = body .. str
  end
  local port = 80
  local target
  local schema, host, uri = url:match("^(https?)://([^/]+)(/.*)$")
  if uri == nil then return 0, "could not parse URL" end
  target = host
  if schema == "https" then port = 443 end
  local hostwoport, aport = host:match("^(.*):(%d+)$")
  if (aport or 0) > 0 then
    target = hostwoport
    port = aport
  end
  if not noit.valid_ip(target) then
    local dns = noit.dns()
    local r = dns:lookup(host)
    if r == nil or r.a == nil then return 0, "could not resolve host" end
    target = r.a
  end

  local payload = {}
  if keys == nil then keys = {} end
  for i, key in pairs(keys) do
     local pair = noit.extras.url_encode(key)
     if form[key] ~= nil then
       pair = pair .. '=' .. noit.extras.url_encode(form[key])
     end
     table.insert(payload, pair)
  end
  -- make a string out of this
  payload = table.concat(payload, '&')

  client:connect(target, port, schema == "https", host)
  client:do_request("POST", uri,
                    { Host=host, Accept='*/*',
                      ['Content-Type']="application/x-www-form-urlencoded" },
                    payload)
  client:get_response()
  return client.code, body
end

function list_accounts(form)
  return proxy_post(circonus_url() .. "/api/json/list_accounts",
                    { "email", "password" },
                    form)
end

function list_private_agents(form)
  return proxy_post(circonus_url() .. "/api/json/list_private_agents",
                    { "email", "password", "account" },
                    form)
end

function submit_agent_csr(form)
  local pki = pki_info()
  local inp = io.open(pki.csr.file, "rb")
  form.csr = inp:read("*all")
  inp:close();
  return proxy_post(circonus_url() .. "/api/json/submit_agent_csr",
                    { "email", "password", "account", "csr" },
                    form)
end

function get_agent_info(subject)
  local cn_encoded = noit.extras.url_encode(subject)
  local success, code, body =
    fetch_url(circonus_url() .. "/api/json/agent?cn=" .. cn_encoded)
  return code, body
end

function get_session(uuid)
  local now = os.time()
  -- sweep old sessions out
  for u, a in pairs(sessions) do
    if a["expires"] < now then sessions[u] = nil end
  end
  if(uuid == nil) then return nil end
  return sessions[uuid]
end

function inside()
  return noit.conf_get_boolean("/noit/circonus/appliance//credentials/inside") or false
end

function circonus_url()
  return noit.conf_get_string("/noit/circonus/appliance//credentials/circonus_url") or "https://login.circonus.com"
end

function pki_info()
  local keyfile = noit.conf('//listeners//listener[@type="control_dispatch"]/ancestor-or-self::node()/sslconfig/key_file')
  local csrfile = keyfile:gsub("%.key$", ".csr")
  local certfile = noit.conf('//listeners//listener[@type="control_dispatch"]/ancestor-or-self::node()/sslconfig/certificate_file')
  local crl = noit.conf('//listeners//listener[@type="control_dispatch"]/ancestor-or-self::node()/sslconfig/crl')
  local ca_chain = noit.conf('//listeners//listener[@type="control_dispatch"]/ancestor-or-self::node()/sslconfig/ca_chain')

  local details = {}
  local needs = false

  details["crl"] = { file=crl, exists=not not noit.stat(crl) }
  details["key"] = { file=keyfile, exists=not not noit.stat(keyfile) }
  details["csr"] = { file=csrfile, exists=not not noit.stat(csrfile) }
  details["cert"] = { file=certfile, exists=not not noit.stat(certfile) }
  details["ca"] = { file=ca_chain, exists=not not noit.stat(ca_chain) }
  return details
end

function needs_pki()
  local d = pki_info()
  if (d["crl"].file == nil or d["crl"].exists) and
     d["key"].exists and d["ca"].exists then return false, d end
  return true, d
end

function needs_provisioning()
  local d = pki_info()
  if d["cert"].exists then return false, d end
  local subj = get_subject()
  if subj == nil then return true, d end
  if d["key"].exists and d["csr"].exists then
    local code, body = get_agent_info(subj)
    if code == 200 then
      local pki_info = pki_info()
      local info = json.decode(body)
      if info.csr ~= nil then
        return false, d
      end
    end
  end
  return true, d
end

function needs_certificate()
  local d = pki_info()
  if d["key"].exists and d["cert"].exists then return false, d end
  return true, d
end

function fix_stage(http)
  local hash = '';
  if inside() then hash = 'inside' end
  local req = http:request()
  local username = noit.conf_get_string("/noit/circonus/appliance//credentials/username")
  local password = noit.conf_get_string("/noit/circonus/appliance//credentials/password")
  local session = req:cookie("appsession")  
  if username == nil or password == nil or username == "" or password == "" then
    return "/initial"
  end -- setup ability to login
  if get_session(session) == nil then return "/login" end -- require login
  if req:uri():match("^/api/") then return nil end -- pass through API
  if needs_pki() or req:uri() == "/pki" then return "/pki", hash end -- needs CA and possibly CRL
  if needs_provisioning() then return "/provision", hash end -- needs provisioning
  if needs_certificate() then return "/await_provisioning", hash end -- needs provisioning
  if req:uri() == "/" then return "/dash" end
  return nil
end


function redirect(http, url)
  http:status(302, "REDIRECT")
  http:header('Location', url)
  http:header('Content-Length', '0')
  http:flush_end()
  noit.log("debug", "redirecting, terminating response\n")
end

function inspect(http)
  local req = http:request()
  noit.log("error", "TYPE  : " .. type(req) .. "\n")
  noit.log("error", "URI   : " .. req:uri() .. "\n")
  noit.log("error", "METHOD: " .. req:method() .. "\n")
  noit.log("error", "QUERYSTRING:\n")
  for key, val in pairs(req:querystring()) do
    noit.log("error", "    "..key.." : "..val.."\n")
  end
  noit.log("error", "HEADERS:\n")
  for hdr, val in pairs(req:headers()) do
    noit.log("error", "    "..hdr.." : "..val.."\n")
  end
  local p = req:payload()
  if p == nil then
    noit.log("error", "NO PAYLOAD\n")
  else
    noit.log("error", "PAYLOAD:\n%s\n\n", p);
    for key, val in pairs(req:form()) do
      noit.log("error", "    "..key.." : "..val.."\n")
    end
  end
end

function serve_file(mime_type)
  return function(rest, file, st)
    local http = rest:http()
    local fd, errno = noit.open(file, bit.bor(O_RDONLY,O_NOFOLLOW))
    if ( fd < 0 ) then
      http:status(500, "ERROR")
      http:flush_end()
      return
    end
    http:status(200, "OK")
    http:header("Content-Type", mime_type)
    if not http:option(http.CHUNKED) then http:option(http.CLOSE) end
    http:option(http.GZIP)
    http:write_fd(fd)
    noit.close(fd)
    http:flush_end()
  end
end

function lua_embed(rest, file, st)
  local http = rest:http()
  local inp = io.open(file, "rb")
  local data = inp:read("*all")
  inp:close();

  local f,e
  if type(_ENV) == "table" then
    -- we're in lua 5.2 land... it is a sad place.
    local loader = function(str)
      local cnt = 1
      return function()
        if cnt == 1 then
          cnt = 0
          return "return function(http)\n" .. str .. "\nend\n"
        end
        return nil
      end
    end
    f,e = assert(load(loader(data), file, "bt", _ENV))
  else
    f,e = assert(loadstring("return function(http)\n" .. data .. "\nend\n"))
    setfenv(f, getfenv(2))
  end
  f = f()

  http:status(200, "OK")
  http:header("Content-Type", "text/html")
  if not http:option(http.CHUNKED) then http:option(http.CLOSE) end
  http:option(http.GZIP)
  f(http)
  http:flush_end();
end


local handlers = {
  default = { serve = serve_file("application/unknown") },
  lua = { serve = lua_embed },
  css = { serve = serve_file("text/css") },
  js = { serve = serve_file("text/javascript") },
  ico = { serve = serve_file("image/x-icon") },
  png = { serve = serve_file("image/png") },
  jpg = { serve = serve_file("image/jpeg") },
  jpe = { serve = serve_file("image/jpeg") },
  jpeg = { serve = serve_file("image/jpeg") },
  gif = { serve = serve_file("image/gif") },
  html = { serve = serve_file("text/html") },
}

function file_not_found(rest)
  local http = rest:http()
  http:status(404, "NOT FOUND")
  http:option(http.CLOSE)
  http:flush_end()
end

function serve(rest, config, file, ext)
  local st, errno, error = noit.stat(file)
  if(st == nil or bit.band(st.mode, S_IFREG) == 0) then
    local errfile = config.webroot .. '/404.lua'
    if file == errfile then
      return file_not_found(rest)
    else
      return serve(rest, config, errfile, ext)
    end
  end

  if handlers[ext] == nil then ext = 'default' end
  handlers[ext].serve(rest, file, st)
end

function handler(rest, config)
  local http = rest:http()
  local req = http:request()

  local req_headers = req:headers()
  local host = req:headers("Host")
  local uri = req:uri()
  local extre = noit.pcre("\\.([^\\./]+)$")

  if req:uri():match("^/debug/") then
    local replacement_uri, hash = fix_stage(http)
    if replacement_uri ~= nil and replacement_uri ~= req:uri() then
      if hash then return redirect(http, replacement_uri .. '#' .. hash) end
      return redirect(http, replacement_uri)
    end
    local file = "/opt/noit/prod/share/noit-web" .. req:uri():sub(7)
    if file:match("/$") then file = file .. "/index.html" end
    local rv, m, ext = extre(file)
    serve(rest, config, file, ext)
    return
  end

  local file = config.webroot .. req:uri()

  if config.should_ssl == "true" and not needs_certificate() then
    local redirect_host = host
    local hostwoport, aport = host:match("^(.*):(%d+)$")
    if (hostwoport ~= nil) then
      redirect_host = hostwoport
    end
    redirect(http, "https://" .. redirect_host .. ":43191" .. req:uri())
  end

  if file:match("/$") then file = file .. "index" end

  local rv, m, ext = extre(file)

  if not rv then
    local replacement_uri, hash = fix_stage(http)
    if replacement_uri ~= nil and replacement_uri ~= req:uri() then
      if hash then return redirect(http, replacement_uri .. '#' .. hash) end
      return redirect(http, replacement_uri)
    end
    file = file .. '.lua'
    ext = 'lua'
  end

  serve(rest, config, file, ext)
end

function do_periodically(f, period)
  return function()
    while true do
      local rv, err = pcall(f)
      if not rv then noit.log("error", "lua --> " .. err .. "\n") end
      noit.sleep(period)
    end
  end
end

function write_contents_if_changed(file, body, mode)
  if mode == nil then
     mode = tonumber(0644, 8)
  end
  local inp = io.open(file, "rb")
  if inp ~= nil then
    local data = inp:read("*all")
    inp:close();
    if body == data then return true end
  end
  local fd = noit.open(file, bit.bor(O_WRONLY,O_TRUNC,O_CREAT), mode)
  if fd >= 0 then
    local len, error = noit.write(fd, body)
    noit.close(fd)
    if len ~= body:len() then return false end
    return true
  end
  return false
end

function refresh_cert()
  noit.log("error", "Circonus certificate refresh\n")
  while true do
    local subj = get_subject()
    if subj == nil then
      noit.log("debug", "No subject set (yet)\n")
    else
      local code, body = get_agent_info(subj)
      if code == 200 then
        local pki_info = pki_info()
        local info = json.decode(body)
        if info ~= nil and info.cert ~= nil and info.cert:len() > 0 then
          write_contents_if_changed(pki_info.cert.file, info.cert)
        end
      end
      local info = pki_info()
      if info.cert.exists then break end
      noit.log("error", "Circonus certificate non-existent, polling(5)\n")
    end
    noit.sleep(5)
  end
end

function filtersets_maintain()
  local cnt = noit.filtersets_cull()
  if cnt > 0 then
    noit.log("error", "Culling %s unused filtersets.\n", cnt)
    noit.conf_save()
  end
end

local reverse_sockets = {}
function update_reverse_sockets(info)
  local wanted = {}
  local pki_info = pki_info()
  local sslconfig = {
    certificate_file = pki_info.cert.file,
    key_file = pki_info.key.file,
    ca_chain = pki_info.ca.file
  }
  if pki_info.crl and pki_info.crl.exists then
    sslconfig.crl = pki_info.crl.file
  end
  local subject = get_subject()

  -- if the prefer_reverse_connection flag isn't set, we have no stratcons
  if info.prefer_reverse_connection ~= 1 then
    noit.log("debug", "prefer_reverse_connection is off\n")
    info.stratcons = {}
  end
  for i, key in pairs(info.stratcons) do
    -- resolve the host, if needed
    if not noit.valid_ip(key.host) then
      local dns = noit.dns()
      local r = dns:lookup(key.host)
      if r == nil or r.a == nil then
        r = dns:lookup(key.host, "AAAA")
        if r == nil or r.aaaa == nil then
          noit.log("error", "failed to lookup stratcon '%s' for reverse socket use\n", key.host)
        end
      end
      if r ~= nil then key.host = r.a or r.aaaa end
    end
    wanted[key.host .. " " .. key.port] = key
  end

  -- remove any reverse_sockets that aren't wanted
  for id, details in pairs(reverse_sockets) do
    if wanted[id] == nil then
      -- turn it down
      noit.log("error", "Turning down reverse connection: '%s'\n", id)
      noit.reverse_stop(details.host,details.port)
      reverse_sockets[id] = nil
    end
  end

  -- add any missing reverse_sockets that are wanted
  for id, details in pairs(wanted) do
    if reverse_sockets[id] == nil then
      -- turn it up
      noit.log("error", "Turning up reverse connection: '%s'\n", id)
      noit.reverse_start(details.host,details.port,
                         sslconfig,
                         { cn = details.cn, 
                           endpoint = subject,
                           xbind = "*"
                         })
      reverse_sockets[id] = details
    end
  end
end

function reverse_socket_maintain()
  noit.log("debug", "Checking reverse socket configuration\n")
  while true do
    local subj = get_subject()
    if subj == nil then
      noit.log("debug", "No subject set (yet)\n")
    else
      local code, body = get_agent_info(subj)
      if code == 200 then
        local info = json.decode(body)
        if info ~= nil then
          update_reverse_sockets(info)
          break
        end
      end
      noit.log("error", "Failed to fetch broker info: %d\n", code)
    end
    noit.sleep(5)
  end
end

function start_upkeep()
  noit.coroutine_spawn(do_periodically(filtersets_maintain, 10800))
  noit.coroutine_spawn(do_periodically(reverse_socket_maintain, 60))
  noit.coroutine_spawn(do_periodically(refresh_cert, 3600))
  noit.coroutine_spawn(do_periodically(function() fetchCA('ca') end, 3600))
  noit.coroutine_spawn(do_periodically(function() fetchCA('crl') end, 3600))
end
