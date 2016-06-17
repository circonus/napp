module(..., package.seeall)

local sessions = {}
local cached_agent_info = {}

local HttpClient = require('mtev.HttpClient') 
local json = require('json')
local noit = require('noit')
local mtev = require('mtev')

local CIRCONUS_API_TOKEN_CONF_PATH = "//circonus/appliance//credentials/circonus_api_token"
local CIRCONUS_API_URL_CONF_PATH = "//circonus/appliance//credentials/circonus_api_url"

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
  if uri == nil then return false, nil, "could not parse URL: " .. url end
  target = host
  if schema == "https" then port = 443 end
  local hostwoport, aport = host:match("^(.*):(%d+)$")
  if tonumber(aport) > 0 then
    target = hostwoport
    port = aport
  end
  if not noit.valid_ip(target) then
    local dns = mtev.dns()
    local r = dns:lookup(target)
    if r == nil or r.a == nil then return false, nil, "could not resolve host" end
    target = r.a
  end

  local headers = { Host = host }
  if string.find(url, circonus_api_url()) == 1 then
    headers["X-Circonus-Auth-Token"] = circonus_api_token()
    headers["X-Circonus-App-Name"] = "broker-provision"
    headers["Accept"] = "application/json"
  end

  client:connect(target, port, schema == "https", host)
  client:do_request("GET", uri, headers)
  client:get_response()
  return true, client.code, body
end

function fetch_url_to_file(url, file, mode, transform)
  if file == nil then return false, "No target file" end
  local success, code, body = fetch_url(url)
  if not success then return success, body end
  if code ~= 200 then return false, "fetching url failed: HTTP CODE " .. code end
  if transform ~= nil then body = transform(body) end
  if body == nil or body:len() == 0 then return false, "fetching url failed: blank document" end
  -- fetch the previous contents
  local inp = io.open(file, "rb")
  if inp ~= nil then
    local data = inp:read("*all")
    inp:close();
    -- short-circuit if the contents haven't changed
    if data == body then return true end
  end

  local fd = mtev.open(file, bit.bor(O_WRONLY,O_TRUNC,O_CREAT), mode)
  if fd >= 0 then
    local len, error = mtev.write(fd, body)
    mtev.close(fd)
    if len ~= body:len() then return false, "failed write: " .. (error or "unknown") end
    return true, "updated " .. file
  end
  return false, "failed to open target file for writing"
end

function old_fetchCA(type)
  local url = circonus_url()
  if url == nil then return false, "old endpoint unknown" end
  local try_url = url
  try_url = string.gsub(try_url, "/*$", "")
  if type == 'ca' then try_url = try_url .. "/pki/ca.crt"
  else try_url = try_url .. "/pki/ca.crl" end
  local xpath = '//listeners//listener[@type="control_dispatch"]/ancestor-or-self::node()/sslconfig/'
  local file
  if type == "ca" then
    file = mtev.conf(xpath .. "ca_chain")
  elseif type == "crl" then
    file = mtev.conf(xpath .. "crl")
  else
    return false, "unsupported type"
  end
  if file ~= nil then
    mtev.log("error", "Fetching -> " .. try_url .. "\n")
    local rv, error = fetch_url_to_file(try_url, file, tonumber(0644,8))
    if rv then return true end
    return false, error
  end
  return true, type .. " not supported on this broker"
end

function extract_json_contents(text)
  local doc = mtev.parsejson(text)
  if doc == nil then return nil end
  local obj = doc:document()
  if obj == nil then return nil end
  return obj.contents;
end

function fetchCA(type)
  local rv, err = old_fetchCA(type)
  if not rv then
    local pki = pki_info()
    if type == "ca" then
      mtev.log("debug", "Fetching CA certificate\n")
      local status, err = fetch_url_to_file(circonus_api_url() .. "/pki/ca.crt", pki.ca.file, tonumber(0644,8), extract_json_contents)
      if err then
        mtev.log("error", "Fetching CA certificate %s: %s\n",
                 status and "succeeded" or "failed", err)
      end
    elseif type == "crl" and pki.crl.file ~= nil then
      mtev.log("debug", "Fetching CA CRL\n")
      local status, err =  fetch_url_to_file(circonus_api_url() .. "/pki/ca.crl", pki.crl.file, tonumber(0644,8), extract_json_contents)
      if err then
        mtev.log("error", "Fetching CA CRL %s: %s\n",
                 status and "succeeded" or "failed", err)
      end
    end
  end
  return false, "unknown CA type"
end

function get_agent_info(subject)
  local cn_encoded = mtev.extras.url_encode(subject)

  -- new v2 API
  local success, code, body =
    fetch_url(circonus_api_url() .. "/v2/provision_broker/" .. cn_encoded)
  if code == 200 and body ~= nil then
    local obj = mtev.parsejson(body):document() or {}
    cached_agent_info[subject] = nil
    if obj ~= nil and obj._cert ~= nil and obj._cert:len() > 0 then
      -- move this from '_cert' to 'cert' to ease code change
      obj.cert = obj._cert
      body = mtev.tojson(obj):tostring()
      cached_agent_info[subject] = body
    end
    return code, body
  end
  -- can we fallback to an old method?
  if circonus_url() == nil then return code, body end

  -- old fallback
  local success, code, body =
    fetch_url(circonus_url() .. "/api/json/agent?cn=" .. cn_encoded)
  if code == 200 and body ~= nil then
    local info = json.decode(body)
    --only cache if everything is good
    if info ~= nil and info.cert ~= nil and info.cert:len() > 0 then
      cached_agent_info[subject] = body
    else
      cached_agent_info[subject] = nil
    end
  else
    mtev.log("error", "Failed to fetch broker info in get_agent_info: %d\n", code)
    cached_agent_info[subject] = nil
  end
  return code, body
end

function get_cached_agent_info(subject)
  local code, body
  if cached_agent_info[subject] ~= nil then
    code = 200
    body = cached_agent_info[subject]
  else
    code, body = get_agent_info(subject)
  end
  return code, body
end

function circonus_url()
  local fallback = nil
  if circonus_api_token() == nil then
    fallback = "https://login.circonus.com"
  end
  return mtev.conf_get_string("/noit/circonus/appliance//credentials/circonus_url") or fallback
end
function circonus_api_token()
  return mtev.conf_get_string(CIRCONUS_API_TOKEN_CONF_PATH)
end
function circonus_api_url()
  return mtev.conf_get_string(CIRCONUS_API_URL_CONF_PATH) or "https://api.circonus.com"
end

function pki_info()
  local keyfile = mtev.conf('//listeners//listener[@type="control_dispatch"]/ancestor-or-self::node()/sslconfig/key_file')
  local csrfile = keyfile:gsub("%.key$", ".csr")
  local certfile = mtev.conf('//listeners//listener[@type="control_dispatch"]/ancestor-or-self::node()/sslconfig/certificate_file')
  local crl = mtev.conf('//listeners//listener[@type="control_dispatch"]/ancestor-or-self::node()/sslconfig/crl')
  local ca_chain = mtev.conf('//listeners//listener[@type="control_dispatch"]/ancestor-or-self::node()/sslconfig/ca_chain')

  local details = {}
  local needs = false

  details["crl"] = { file=crl, exists=not not mtev.stat(crl) }
  details["key"] = { file=keyfile, exists=not not mtev.stat(keyfile) }
  details["csr"] = { file=csrfile, exists=not not mtev.stat(csrfile) }
  details["cert"] = { file=certfile, exists=not not mtev.stat(certfile) }
  details["ca"] = { file=ca_chain, exists=not not mtev.stat(ca_chain) }
  return details
end

function needs_certificate()
  local d = pki_info()
  if d["key"].exists and d["cert"].exists then return false, d end
  return true, d
end

function do_periodically(f, period)
  return function()
    while true do
      local rv, err = pcall(f)
      if not rv then mtev.log("error", "lua --> " .. err .. "\n") end
      mtev.sleep(period)
    end
  end
end

-- return (success), (changed)
function write_contents_if_changed(file, body, mode)
  if mode == nil then
     mode = tonumber(0644, 8)
  end
  local inp = io.open(file, "rb")
  if inp ~= nil then
    local data = inp:read("*all")
    inp:close();
    if body == data then return true, false end
  end
  local fd = mtev.open(file, bit.bor(O_WRONLY,O_TRUNC,O_CREAT), mode)
  if fd >= 0 then
    local len, error = mtev.write(fd, body)
    mtev.close(fd)
    if len ~= body:len() then return false end
    return true, true
  end
  return false, true
end

function refresh_cert()
  mtev.log("debug", "Circonus certificate refresh\n")
  while true do
    local subj = get_subject()
    if subj == nil then
      mtev.log("debug", "No subject set (yet)\n")
    else
      local code, body = get_agent_info(subj)
      if code == 200 then
        local pki_info = pki_info()
        local info = mtev.parsejson(body):document()
        if info ~= nil and info.cert ~= nil and info.cert:len() > 0 then
          local success, changed = 
            write_contents_if_changed(pki_info.cert.file, info.cert)
          if not success then mtev.log("error", "Error: failed to write %s\n", pki_info.cert.file)
          elseif changed then mtev.log("error", "updated %s\n", pki_info.cert.file)
          end
        else
          if info == nil then
            mtev.log("error", "Error: Failed to decode agent info json in get_agent_info\n")
          elseif info.cert == nil then
            mtev.log("error", "Error: No agent certificate in get_agent_info\n")
          elseif info.cert:len() <= 0 then
            mtev.log("error", "Error: Agent certificate has invalid length in get_agent_info\n")
          end
        end
      end
      local info = pki_info()
      if info.cert.exists then
        break 
      end
      mtev.log("error", "Circonus certificate non-existent, polling(5)\n")
    end
    mtev.sleep(5)
  end
end

function filtersets_maintain()
  local cnt = noit.filtersets_cull()
  if cnt > 0 then
    mtev.log("error", "Culling %s unused filtersets.\n", cnt)
    mtev.conf_save()
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
    mtev.log("debug", "prefer_reverse_connection is off\n")
    info._stratcons = {}
  end
  for i, key in pairs(info._stratcons) do
    -- resolve the host, if needed
    if not noit.valid_ip(key.host) then
      local dns = mtev.dns()
      local r = dns:lookup(key.host)
      if r == nil or r.a == nil then
        r = dns:lookup(key.host, "AAAA")
        if r == nil or r.aaaa == nil then
          mtev.log("error", "failed to lookup stratcon '%s' for reverse socket use\n", key.host)
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
      mtev.log("error", "Turning down reverse connection: '%s'\n", id)
      mtev.reverse_stop(details.host,details.port)
      reverse_sockets[id] = nil
    end
  end

  -- add any missing reverse_sockets that are wanted
  for id, details in pairs(wanted) do
    if reverse_sockets[id] == nil then
      -- turn it up
      mtev.log("error", "Turning up reverse connection: '%s'\n", id)
      mtev.reverse_start(details.host,details.port,
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
  mtev.log("debug", "Checking reverse socket configuration\n")
  while true do
    local subj = get_subject()
    if subj == nil then
      mtev.log("debug", "No subject set (yet)\n")
    else
      local code, body = get_cached_agent_info(subj)
      if code == 200 then
        local info = mtev.parsejson(body):document()
        if info ~= nil then
          update_reverse_sockets(info)
          break
        end
      end
    end
    mtev.sleep(5)
  end
end

function start_upkeep()
  mtev.coroutine_spawn(do_periodically(filtersets_maintain, 10800))
  mtev.coroutine_spawn(do_periodically(reverse_socket_maintain, 60))
  mtev.coroutine_spawn(do_periodically(refresh_cert, 3600))
  mtev.coroutine_spawn(do_periodically(function() fetchCA('ca') end, 3600))
  mtev.coroutine_spawn(do_periodically(function() fetchCA('crl') end, 3600))
end
