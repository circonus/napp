module(..., package.seeall)

local sessions = {}
local HttpClient = require('noit.HttpClient') 

function new_session()
  local uuid = noit.uuid()
  sessions[uuid] = { }
  sessions[uuid]["expires"] = os.time() + 86400
  return uuid
end

function generate_key(keyfile)
  local p, inf, outf, errf = noit.spawn(
    "openssl", { 'openssl', 'genrsa', '-out', keyfile, 2048 }, {})
  local rv = p:wait()
  if rv == 0 then
    noit.chmod(keyfile, tonumber(0400, 8))
    return rv
  end
  return rv, errf:read("EOF")
end

function generate_csr(subject, csrfile)
  local pki = pki_info()
  local fd = noit.open('/opt/napp/etc/ssl/ssl_subj.txt',
                       bit.bor(O_CREAT,O_TRUNC,O_WRONLY), tonumber(0644,8))
  if fd < 0 then
    return fd, "Could not store broker PKI CN"
  end
  noit.write(fd, subject)
  noit.close(fd)
  local p, inf, outf, errf = noit.spawn(
    "openssl", { 'openssl', 'req', '-key', pki.key.file,
                 '-days', '365', '-new', '-out', pki.csr.file,
                 '-config', '/opt/napp/etc/napp-openssl.cnf',
                 '-subj', subject}, {})
  local rv = p:wait()
  if rv == 0 then
    noit.chmod(pki.csr.file, tonumber(0444, 8))
    return rv
  end
  return rv, errf:read("EOF")
end

function get_subject()
  local inp = io.open('/opt/napp/etc/ssl/ssl_subj.txt', "rb")
  local data = inp:read("*all")
  inp:close();
  local cn = data:match("CN=([^/]+)")
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
  if code ~= 200 then return false, "fetching url failed: HTTP CODE " .. client.code end
  if body:len() == 0 then return false, "fetching url failed: blank document" end
  local fd = noit.open(file, bit.bor(O_WRONLY,O_TRUNC,O_CREAT), mode)
  if fd >= 0 then
    local len, error = noit.write(fd, body)
    noit.close(fd)
    if len ~= body:len() then return false, "failed write: " .. (error or "unknown") end
    return true
  end
  return false, "failed to open target file for writing"
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
  return noit.conf_get_boolean("/noit/circonus/appliance/inside") or false
end

function pki_url()
  return noit.conf_get_string("/noit/circonus/appliance/pki_url") or "http://s.circonus.com/pki"
end
function circonus_url()
  return noit.conf_get_string("/noit/circonus/appliance/circonus_url") or "https://circonus.com"
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
  if (d["crl"].file == nil or d["crl"].exists) and d["ca"].exists then return false, d end
  return true, d
end

function needs_provisioning()
  local d = pki_info()
  if d["key"].exists and d["csr"].exists then return false, d end
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
  local username = noit.conf_get_string("/noit/circonus/appliance/username")
  local password = noit.conf_get_string("/noit/circonus/appliance/password")
  local session = req:cookie("appsession")  
  if username == nil or password == nil then return "/initial" end -- setup ability to login
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
  http:flush_end()
  error("redirecting, terminating response")
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

  local f,e = assert(loadstring("return function(http)\n" .. data .. "\nend\n"))
  setfenv(f, getfenv(2))
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

  local file = config.webroot .. req:uri()

  if file:match("/$") then file = file .. "index" end

  local extre = noit.pcre("\\.([^\\./]+)$")
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
