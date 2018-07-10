--
-- Broker Provisioning Tool
--
module("prov", package.seeall)

local HttpClient = require 'mtev.HttpClient'
local API_KEY

local task_provision, task_rebuild, task_list, cn, ip_address,
      CIRCONUS_API_TOKEN_CONF_PATH, CIRCONUS_API_URL_CONF_PATH,
      prog, debug, brokers, set_name, set_long, set_lat, CAcn,
      prefer_reverse, set_ext_host, set_ext_port, make_public,
      task_fetch_certs, cluster_id

prog = "provtool"
prefer_reverse = 0
make_public = 0
CIRCONUS_API_TOKEN_CONF_PATH = "//circonus/appliance//credentials/circonus_api_token"
CIRCONUS_API_URL_CONF_PATH = "//circonus/appliance//credentials/circonus_api_url"

function _P(...) mtev.log("stdout", ...) end
function _E(...) mtev.log("error", ...) end
function _F(...) mtev.log("error", "Fatal Error:\n\n") mtev.log("error", ...) os.exit(2) end
function _D(level, ...) if debug >= level then mtev.log("debug/cli", ...) end end
function tablelength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

function usage()
  _P("%s usage:\n\n", prog)
  _P("# Local configuration\n\n")
  _P("  %s config get <key>\n", prog)
  _P("  %s config set <key> <value>\n", prog)
  config_usage()
  _P("\n")
  _P("# Listing brokers\n\n")
  _P("  %s list\n", prog)
  _P("\n")
  _P("# Provision this broker\n\n")
  _P("  %s provision [-cn <cn>] [-ip <ip>] [-name <name>]\n", prog)
  _P("\t-cn <cn>\tspecify a broker CN, default first unprovisioned\n")
  _P("\t-ip <IP>\tset the broker IP address to which Circonus will connect\n")
  _P("\t-long <longitude>\tset the broker's longitude\n")
  _P("\t-lat <latitude>\tset the broker's latitude\n")
  _P("\t-name <name>\tan optional name for the broker\n")
  _P("\t-ext_host <name>\tpublic facing name for broker\n")
  _P("\t-ext_port <port>\tpublic facing port for broker\n")
  _P("\t-nat\t\ttell Circonus that this broker will dial in\n")
  _P("\t-cluster_id\t\ttell Add this broker to an exsiting cluster_id\n")
  _P("\n")
  _P("# Rebuilding a broker's configuration\n\n")
  _P("  %s rebuild [-cn <cn>]\n", prog)
  _P("\t-cn <cn>\trebuild an arbitrary cn [default: this machine].\n")
  _P("\n")
  _P("# Fetch/renew cerfificate\n\n")
  _P("  %s cert\n", prog)
  _P("  \t-cn <cn>\tspecify a broker CN\n")
  _P("\n")
end

--
-- Cli parser
--
debug = 0
local opts = {
  -- use -d (repeated) for debuging output,
  d = function(n) debug = debug + 1 end
}

function nextargs_iter()
  local i = 1
  return function()
    i = i + 1
    return arg[i-1]
  end
end

function parse_cli()
  local next = nextargs_iter(arg)
  local prog = next()

  local command = next()
  if command == 'config' then
    local subcommand = next()
    if subcommand == 'get' then
      os.exit(do_config_get(next()))
    elseif subcommand == 'set' then
      os.exit(do_config_set(next(), next()))
    end
    _E("invalid config subcommand: %s\n", subcommand)
    usage()
    os.exit(2)
  elseif command == 'list' then task_list = true
  elseif command == 'provision' then
    task_provision = true
    opts.cn = function(n) cn = n() end
    opts.ip = function(n) ip_address = n() end
    opts.name = function(n) set_name = n() end
    opts.long = function(n) set_long = n() end
    opts.nat = function(n) prefer_reverse = 1 end
    opts.lat = function(n) set_lat = n() end
    opts.ext_host = function(n) set_ext_host = n() end
    opts.ext_port = function(n) set_ext_port = n() end
    opts.public = function(n) make_public = 1 end
    opts.cluster_id = function(n) cluster_id = n() end
  elseif command == 'rebuild' then
    task_rebuild = true
    opts.cn = function(n) cn = n() end
  elseif command == 'cert' then
    task_fetch_certs = true
    opts.cn = function(n) cn = n() end
  else usage() os.exit(2)
  end

  for v in next do
    if type(opts[v:sub(2)]) == 'function' then
      opts[v:sub(2)](next)
    else
      usage()
      _F("%s is an invalid option\n", v)
    end
  end
end

--
-- Configuration management
--
local configs = { }
configs['api-url'] = {
  path = CIRCONUS_API_URL_CONF_PATH,
  description = "the Circonus API base url",
  validate = function(val)
    local schema, host, sep, port, uri = string.match(val, "^(https?)://([^:/]*)(:?)([0-9]*)(.*)$")
    if schema == nil or host == nil or
       uri == nil or string.sub(uri or "",-1) == "/" then
      return false, "must be a URL without path like: https://api.circonus.com"
    end
    return true
  end,
  default = "https://api.circonus.com"
}
configs['api-token'] = {
  path = CIRCONUS_API_TOKEN_CONF_PATH,
  validate = function(a)
    if not string.find(a, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
      return false, "must be a valid uuid"
    end
    return true
  end,
  description = "the Circonus API token for provisioning"
}
configs['googleanalytics/client-id'] = {
  path = "//circonus/googleanalytics//config/client_id",
  description = "Google Analytics Client Id"
}
configs['googleanalytics/client-secret'] = {
  path = "//circonus/googleanalytics//config/client_secret",
  description = "Google Analytics Client Secret"
}
configs['googleanalytics/api-key'] = {
  path = "//circonus/googleanalytics//config/api_key",
  description = "Google Analytics API Key"
}

function extract_json_contents(text)
  local doc = mtev.parsejson(text)
  if doc == nil then return nil end
  local obj = doc:document()
  if obj == nil then return nil end
  return obj.contents;
end

function do_config_get(key)
  if key == nil then
    local a = {}
    for n in pairs(configs) do table.insert(a, n) end
    table.sort(a)
    for _,k in pairs(a) do
      _P("%s=%s\n", k, mtev.conf_get_string(configs[k].path))
    end
  elseif not configs[key] then
    _F("Unknown config key: %s\n", key)
  else
    _P("%s\n", mtev.conf_get_string(configs[key].path))
  end
  return 0
end

function do_config_set(key, value)
  if not configs[key] then _F("Unknown config key: %s\n", key) end
  if configs[key].validate then
    local passed, msg = configs[key].validate(value)
    if not passed then
      _F("Cannot set %s:\n%s\n", key, msg or "unknown error")
    end
  end
  mtev.conf_get_string(configs[key].path, value)
end

function config_usage()
  local a = {}
  for n in pairs(configs) do table.insert(a, n) end
  table.sort(a)
  for _,k in pairs(a) do
    local v = configs[k]
    _P("\t%s:\t%s\n", k, v.description)
    if v.default then _P("\t\t\t(default: %s)\n", v.default) end
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
  local fd = mtev.open(file, bit.bor(O_WRONLY,O_TRUNC,O_CREAT), mode)
  if fd >= 0 then
    local len, error = mtev.write(fd, body)
    mtev.close(fd)
    if len ~= body:len() then return false, "bad resulting file length" end
    return true
  end
  return false, "failed to open target file"
end

function circonus_api_token()
  return mtev.conf_get_string(CIRCONUS_API_TOKEN_CONF_PATH)
end

function circonus_api_url()
  return mtev.conf_get_string(CIRCONUS_API_URL_CONF_PATH)
    or "https://api.circonus.com"
end

function _API(endpoint)
  return circonus_api_url() .. endpoint
end


--
-- Circonus API
--
function HTTP(method, url, payload, silent, _pp)
  _pp = _pp or function(o)
    local doc = mtev.parsejson(o)
    if doc == nil then return nil end
    return doc:document()
  end
  local _F, _E = _F, _E
  if silent then _F = function() end  _E = _F end
  local schema, host, sep, port, uri = string.match(url, "^(https?)://([^:/]*)(:?)([0-9]*)(/?.*)$")
  local use_ssl = false
  local headers = {}
  local in_headers = {}

  if string.sub(url, 1, string.len(circonus_api_url())) == circonus_api_url() then
    headers["X-Circonus-Auth-Token"] = API_TOKEN
    headers["X-Circonus-App-Name"] = "broker-provision"
  end

  if port == '' or port == nil then
    if schema == 'http' then
      port = 80
    elseif schema == 'https' then
      port = 443
    else
      error(schema .. " not supported")
    end
  end
  if schema == 'https' then
    use_ssl = true
  end

  local callbacks = { }
  callbacks.consume = function (str)
    if setfirstbyte == 1 then
      firstbytetime = mtev.timeval.now()
      setfirstbyte = 0
    end
    output = output .. (str or '')
  end

  local dns = mtev.dns()
  local r = dns:lookup(host)
  if not r or r.a == nil then
    mtev.log("error", "failed to resolve %s\n", host)
    return -1
  end

  local output = ''
  local callbacks = {}
  callbacks.consume = function (str) output = output .. (str or '') end
  callbacks.headers = function (hdrs) in_headers = hdrs end

  local client = HttpClient:new(callbacks)
  local rv, err = client:connect(r.a, port, use_ssl, host)
  if rv ~= 0 then
    mtev.log("error", "Failed to connect %s\n", err)
    return -1
  end

  _D(1, "%s -> %s %s\n", r.a, method, url)
  _D(2, "> %s\n", payload)

  headers.Host = host
  headers.Accept = 'application/json'
  local rv = client:do_request(method, uri, headers, payload, "1.1")
  client:get_response(1024000)

  _D(2, "< %s\n\n", output)

  if string.sub(url, 1, string.len(circonus_api_url())) == circonus_api_url() then
    if client.code == 403 then
      _F("Permission denied! (bad CIRCONUS_AUTH_TOKEN?)\n")
    end
    if client.code == 401 then
      mtev.log("error", "Looks like your token is pending validation.\n")
      local tok_url = in_headers['x-circonus-token-approval-url']
                  or 'the token management page'
      _F("Please visit %s to approve its use here.\n", tok_url)
    end
    if client.code ~= 200 then
      _E("An unknown error (%s) has occurred accessing: %s\n", client.code, url)
      _E("Please report this issue to support@circonus.com\n")
    end
  end

  return client.code, _pp(output), output
end

function get_ip()
  local code, obj = HTTP("GET", _API("/v2/canhazip"), nil, true)
  if obj ~= nil then return code, obj.ipv4 end
  return code, nil
end

function get_account()
  local code, obj = HTTP("GET", _API("/v2/account/current"))
  if not obj then
    _F("Could not retrieve account information. Is api-url set correctly?\n")
  end
  return obj
end

function get_brokers(type)
  local code, obj, body
  local account = get_account()
  -- superadmin token gets to see all brokers
  if (account._cid == "/account/1") then
    code, obj, body = HTTP("GET", _API("/v2/broker"))
  else
    if type == nil then type = "enterprise" end
    code, obj, body = HTTP("GET", _API("/v2/broker?f__type=" .. type))
  end
  brokers = obj
  return code, obj, body
end

function find_broker(cn)
  if brokers == nil then get_brokers() end
  for _,group in pairs(brokers) do
    for _,broker in pairs(group._details) do
      if broker.cn == cn then return broker end
    end
  end
  return nil
end

function get_broker(cn)
  return HTTP("GET", _API("/v2/provision_broker/" .. mtev.extras.url_encode(cn)))
end

function provision_broker(cn, data)
  local payload = mtev.tojson(data):tostring()
  return HTTP("PUT", _API("/v2/provision_broker/" .. mtev.extras.url_encode(cn)), payload)
end

function fetch_url(url)
  return HTTP("GET", url, nil, true, function(o) return o end)
end

function fetch_url_to_file(url, file, mode, transform)
  local code, body = fetch_url(url)
  if code ~= 200 then return false, body end
  if transform ~= nil then body = transform(body) end
  if body == nil or body:len() == 0 then return false, "blank document" end
  local rv, error = write_contents_if_changed(file, body, mode)
  if not rv then
    return false, error
  end
  return true
end

--
-- PKI Manangment
--
function slurp_file(file)
  if file == nil then return nil end
  local inp = io.open(file, "rb")
  if inp == nil then return nil, nil end
  local data = inp:read("*all")
  inp:close()
  if data == nil then return nil, nil end
  return data
end

function pki_info()
  local keyfile = mtev.conf('//listeners//listener[@type="control_dispatch"]/ancestor-or-self::node()/sslconfig/key_file')
  local csrfile = keyfile:gsub("%.key$", ".csr")
  local certfile = mtev.conf('//listeners//listener[@type="control_dispatch"]/ancestor-or-self::node()/sslconfig/certificate_file')
  local crl = mtev.conf('//listeners//listener[@type="control_dispatch"]/ancestor-or-self::node()/sslconfig/crl')
  local ca_chain = mtev.conf('//listeners//listener[@type="control_dispatch"]/ancestor-or-self::node()/sslconfig/ca_chain')

  local details = {}
  local needs = false

  -- key but no contents
  details.key = { file=keyfile, exists=not not mtev.stat(keyfile) }

  -- all the other bits have the whole file slurped
  details.crl = { file=crl, exists=not not mtev.stat(crl) }
  details.crl.data = slurp_file(details.crl.file)
  details.csr = { file=csrfile, exists=not not mtev.stat(csrfile) }
  details.csr.data = slurp_file(details.csr.file)
  details.cert = { file=certfile, exists=not not mtev.stat(certfile) }
  details.cert.data = slurp_file(details.cert.file)
  details.ca = { file=ca_chain, exists=not not mtev.stat(ca_chain) }
  details.ca.data = slurp_file(details.ca.file)
  return details
end

function generate_key(keyfile)
  local rsa = mtev.newrsa()
  if rsa == nil then
    return -1, "keygen failed"
  end
  local fd = mtev.open(keyfile,
                       bit.bor(O_CREAT,O_TRUNC,O_WRONLY), tonumber(0600,8))
  if fd < 0 then
    return fd, "Could not store broker private key"
  end
  mtev.write(fd, rsa:pem())
  mtev.close(fd)
  mtev.chmod(keyfile, tonumber(0600, 8))
  return 0
end

function generate_csr(cn,c,st,o)
  c = c or ''
  st = st or ''
  o = o or ''
  local subject = '/C=' .. c .. '/ST=' .. st .. '/O=' .. o .. '/CN=' .. cn
  local pki = pki_info()
  local inp = io.open(pki.key.file, "rb")
  if inp == nil then return -1, "could not open private key" end
  local keydata = inp:read("*all")
  inp:close()
  local key = mtev.newrsa(keydata)
  if key == nil then return -1, "private key invalid" end
  local subj = {}
  for k, v in string.gmatch(subject, "(%w+)=([^/]+)") do
    subj[k] = v
  end
  local req = key:gencsr({ subject=subj })

  local fd = mtev.open(pki.csr.file,
                       bit.bor(O_CREAT,O_TRUNC,O_WRONLY), tonumber(0644,8))
  if fd < 0 then
    return fd, "Could not store broker CSR"
  end
  mtev.write(fd, req:pem())
  mtev.close(fd)
  mtev.chmod(pki.csr.file, tonumber(0600, 8))
  return 0
end

function extract_subject()
  local pki = pki_info()
  if pki.csr.data == nil then return nil end
  local req = mtev.newreq(pki.csr.data)
  if req == nil then return nil, data end
  local cn = req.subject:match("CN=([^/\n]+)")
  return cn, pki.csr.data
end

--
--- Tasks
--

function do_fetch_certificate(myself)
  local cn = myself._cid
  _P(" -- attempting to fetch certificate for %s", cn)
  local pki = pki_info()
  repeat
    _, myself = get_broker(cn)
    if myself._cert ~= nil then
      local fd = mtev.open(pki.cert.file, bit.bor(O_WRONLY,O_TRUNC,O_CREAT), tonumber(0644,8))
      if fd < 0 then _F(" - error\nCould not open %s for writing!\n", pki.cert.file) end
      local len, error = mtev.write(fd, myself._cert)
      mtev.close(fd)
      if len ~= myself._cert:len() then
        _F(" - error.\nError writing to %s: %s\n", pki.cert.file, error or "unkown error")
      end
    else
      _P(" - unavailable.\n")
      mtev.sleep(5)
    end
    pki = pki_info()
  until pki.cert.exists
  _P(" - ok.\n")

  function update_pki_bits(url,file)
    if file == nil then
      _P(" - skipped\n")
      return
    end
    local rv, error = fetch_url_to_file(url, file, tonumber(0644,8), extract_json_contents)
    if not rv then
      local body = mtev.parsejson(error)
      if body ~= nil then body = body:document() end
      if type(body) == 'table' then
        error = body.explanation or body.message or body.status or error
      end
      _F(" - error\nFailed to pull Circonus PKI data\n - from %s\n - to %s\n - error: %s\n",
         url, file, error or "unknown error")
    end
  end

  _P(" -- updating certificate authority")
  update_pki_bits(circonus_api_url() .. "/pki/ca.crt", pki.ca.file)
  _P(" - ok\n")
  _P(" -- updating certificate revocation lists")
  update_pki_bits(circonus_api_url() .. "/pki/ca.crl", pki.crl.file)
  _P(" - ok\n")
end

function do_task_list(_print)
  local avail
  local count = 0
  local code, obj = get_brokers()
  local existing_cn = extract_subject()
  if _print == nil then _print = function() return end end
  local fmt = "| %-40s | %-31s |\n"
  _print(fmt, "Group -> CN", "Status")
  _print("------------------------------------------------------------------------------\n")
  for _,group in pairs(obj) do
    local use_group = tablelength(group._details) > 1
    for _,broker in pairs(group._details) do
      if use_group then _print(fmt, group._name, "") end
      if avail == nil and broker.status == 'unprovisioned' then
        avail = broker.cn
      end
      local mine_str = ""
      if existing_cn ~= nil and existing_cn == broker.cn then
        mine_str = " <- current node"
      end
      _print(fmt, "  -> " .. broker.cn, broker.status .. mine_str)
      count = count + 1
    end
    _print("------------------------------------------------------------------------------\n")
  end
  if count < 1 then
    _print("No brokers found\n")
  end
  return avail
end

function do_task_provision()
  local pki = pki_info()
  local existing_cn = extract_subject()
  local account = get_account()
  get_brokers() -- sets the cached copies

  --
  -- If a cn was specified on the command line and it
  -- isn't in the list of broker cns, we can stop now.
  --
  if cn ~= nil then
    if find_broker(cn) == nil then
      _F("\"%s\" was specified as the cn, but that cn isn't in the list of brokers.\n\n" ..
         "Use 'provtool list' to see brokers.\n" , cn)
    end
    if existing_cn ~= nil and existing_cn ~= cn then
      _F("Specified cn (%s) does not match the one found in the csr (%s)\n" ..
           "Please remove the csr file or change the -cn flag."
           , cn, existing_cn)
    end
  end

  --
  -- First truth: we need a key
  --
  if not pki.key.exists then
    _P(" -- generating RSA key...\n")
    local rv, err = generate_key(pki.key.file)
    if rv ~= 0 then _E("Error generating key: %s\n", err) end
  end

  --
  -- Next it gets more complicated.  This might not be our first rodeo.
  -- Perhaps we've been provisioned already or we started the process and
  -- failed to finish it... that is detected here.
  --
  local myself
  if existing_cn ~= nil then
    _, myself = get_broker(existing_cn)
    if myself._status == 'unprovisioned' or pki.csr.data ~= myself.csr then
      -- We generated a CSR to provision ourselves, but they never got it
      _P(" ** incomplete provisioning, starting over...\n")
      existing_cn = nil
    end
  end

  --
  -- We've found ourselves to be sufficiently provisioned to not "start from
  -- scratch, so we'll use the existing CN and try to make some progress.
  -- "sufficiently provisioned" means that we have a CSR and the Circonus API
  -- also has that same CSR, so they know our intention.
  --
  if existing_cn ~= nil then
    _E("This broker is already provisioned as %s\n", existing_cn)

    --
    -- It might be that we've just requested to update metadata such as
    -- our IP address, name, tags or location
    --
    set_name = set_name or myself.noit_name
    ip_address = ip_address or myself.ipaddress
    cluster_id = cluster_id or myself.cluster_id
    -- Let's see if our metadata has changed, is so we'll PUT new info
    if myself.noit_name == set_name and
       myself.ipaddress == ip_address and
       myself.longitude == set_long and
       myself.latitude == set_lat and
       myself.ext_host == set_ext_host and
       myself.ext_port == set_ext_port and
       myself.prefer_reverse_connection == prefer_reverse and
       myself.cluster_id == cluster_id
    then
      _P(" -- up to date")
    else
      if ip_address == nil and (myself.prefer_reverse_connection ~= 1 or prefer_reverse ~= 1) then
        _F("We could not detemine your public IP address, please use -ip <ip>\n")
      end
      _P(" -- updating information\n")
      local code, obj, body = provision_broker(existing_cn, {
        csr = pki.csr.data,
        external_host = set_ext_host,
        external_port = set_ext_port,
        ipaddress = ip_address,
        latitude = set_lat,
        longitude = set_long,
        make_public = make_public,
        noit_name = set_name,
        port = 43191,
        prefer_reverse_connection = prefer_reverse,
        rebuild = false,
        cluster_id = cluster_id,
      })
      _, myself = get_broker(existing_cn)
    end
    do_fetch_certificate(myself)
    os.exit(0)
  end

  if cn == nil then
    cn = do_task_list() -- this just returns the first unprovisioned
  end
  if tablelength(brokers) < 1 or cn == nil then
    _F("There are no broker slots available on this account.\n" ..
       "Please visit your brokers page to add one.\n")
  end

  -- Now we generate a CSR and submit it.
  if ip_address == nil and prefer_reverse ~= 1 then
    _F("We could not detemine your public IP address, please use -ip <ip>\n")
  end
  _P(" -- generating CSR...\n")
  local rv, err = generate_csr(cn,account.country_code,'',account_name)
  if rv ~= 0 then
    _F("Error creating certificate signing request:\n%s\n", err)
  end
  local existing_cn, csr_contents = extract_subject()
  existing_cn = cn
  code, myself = get_broker(existing_cn)
  if set_name == nil then set_name = myself.name end

  local code, obj, body = provision_broker(existing_cn, {
    noit_name = set_name,
    port = 43191,
    latitude = set_lat,
    longitude = set_long,
    external_host = set_ext_host,
    external_port = set_ext_port,
    rebuild = false,
    ipaddress = ip_address,
    prefer_reverse_connection = prefer_reverse,
    csr = csr_contents,
    make_public = make_public,
    cluster_id = cluster_id,
  });
  if code ~= 200 then
    _F("Fatal error attempt to provision broker...\n" .. (body or "<empty>"))
  end

  return do_fetch_certificate(myself)
end

function do_task_rebuild()
  local existing_cn = extract_subject()
  if cn == nil then cn = existing_cn end
  if cn == nil then
    _F("rebuild requires a cn to be specified or this broker to be provisioned\n")
  end
  local code, obj, body = provision_broker(cn, { rebuild = true })
  return 2
end

function do_task_fetch_certs()
  local existing_cn = extract_subject()
  if cn == nil then cn = existing_cn end
  if cn == nil then
    _F("fetch cert requires a cn to be specified or this broker to be provisioned\n")
  end
  if find_broker(cn) == nil then
    _F("You don't have access to a broker with cn %s\n", cn)
  end
  local code, myself = get_broker(cn)
  if not (code == 200 and myself) then
    _F("Failed fetching broker information for cn %s.\n", cn)
  end
  do_fetch_certificate(myself)
end

function do_work()
  if ip_address == nil then
    _, ip_address = get_ip()
  end

  if task_list then do_task_list(_P) os.exit(0)
  elseif task_provision then os.exit(do_task_provision())
  elseif task_rebuild then os.exit(do_task_rebuild())
  elseif task_fetch_certs then os.exit(do_task_fetch_certs())
  end

  _F("Something went very wrong.\n")
  return 2
end

function main()
  parse_cli()
  API_TOKEN = circonus_api_token()
  if API_TOKEN == nil then
    _F("Missing CIRCONUS_API_TOKEN!\nPlease set it via:\n\n%s config set api-token <uuid>\n", prog)
  end
  os.exit(do_work())
end
