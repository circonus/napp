--
-- Broker Provisioning Tool
--
module("prov", package.seeall)

-- ENVIRONMENT VARIABLES
--
--  REQUIRED:
--  CIRCONUS_AUTH_TOKEN
--
--  OPTIONAL:
--  CIRCONUS_API_URL (for inside)
--  CLUSTER_NAME (name of cluster to join)
--  BROKER_IP (IP that Circonus can connect to, if unset reverse connections will be used)
--  BROKER_NAME (a alias for this host)
--  BROKER_LATITUDE
--  BROKER_LONGITUDE
--  CLUSTER_IP (IP for peer cluster nodes to connect to)
--  EXTERNAL_HOST (the IP address agents/clients should connect to)
--  EXTERNAL_PORT (should be 43191 unless oddly mapped)
--  CONTACT_GROUP (the contact group id)

local CIRCONUS_API_TOKEN_CONF_PATH = "//circonus/appliance//credentials/circonus_api_token"
local CIRCONUS_API_URL_CONF_PATH = "//circonus/appliance//credentials/circonus_api_url"
local CIRCONUS_LEGACY_URL_CONF_PATH = "//circonus/appliance//credentials/circonus_url"
local HttpClient = require 'mtev.HttpClient'
local json = require 'json'

local debug = 0
local _J = function(t) return mtev.tojson(t):tostring() end
function _P(...) mtev.log("error", ...) end
function _E(...) mtev.log("error", ...) end
local _F = function(...) mtev.log("error", "Fatal Error:\n\n") mtev.log("error", ...) end
function _D(level, ...) if debug >= level then mtev.log("debug/cli", ...) end end

function validate_uuid(uuid)
  local x = "%x"
  local t = { x:rep(8), x:rep(4), x:rep(4), x:rep(4), x:rep(12) }
  local pattern = '^' .. table.concat(t, '%-') .. '$'
  local result = string.match(uuid, pattern)

  if result == nil then
    return false, "Not a well-formed UUID: " .. uuid
  else
    return true, result
  end
end

local prov = {}
prov.__index = prov
function prov:new(attr)
  local obj = { }
  obj._detail = {}
  obj._detail.set_prefer_reverse_connection = 0
  obj._detail.set_ipaddress = os.getenv("BROKER_IP")
  if obj._detail.set_ipaddress == nil then
    obj._detail.set_prefer_reverse_connection = 1
  end
  obj._detail.set_cluster_name = os.getenv("CLUSTER_NAME")
  local uts = mtev.uname() or {}
  obj._detail.set_noit_name = os.getenv("BROKER_NAME") or uts.nodename
  obj._detail.set_cluster_ip = os.getenv("CLUSTER_IP") or mtev.getip_ipv4()
  obj._detail.set_external_host = os.getenv("EXTERNAL_HOST") or mtev.getip_ipv4()
  obj._detail.set_external_port = os.getenv("EXTERNAL_PORT")
  obj._detail.set_latitude = os.getenv("BROKER_LATITUTE")
  obj._detail.set_longitude = os.getenv("BROKER_LONGITUTE")
  obj._detail.set_contact_group_id = os.getenv("CONTACT_GROUP")
  obj._detail.set_make_public = os.getenv("MAKE_PUBLIC")
  for k,v in pairs(attr or {}) do
    obj[k] = v
  end
  setmetatable(obj, prov)
  local tokenv = os.getenv("CIRCONUS_AUTH_TOKEN")
  if tokenv ~= nil then
    mtev.conf(CIRCONUS_API_TOKEN_CONF_PATH, tokenv)
  end
  local tok = mtev.conf_get_string(CIRCONUS_API_TOKEN_CONF_PATH)
  local apienv = os.getenv("CIRCONUS_API_URL")
  if apienv ~= nil then
    mtev.conf(CIRCONUS_API_URL_CONF_PATH, apienv)
  end
  local api = mtev.conf_get_string(CIRCONUS_API_URL_CONF_PATH) or "https://api.circonus.com"
  obj.token = tok
  obj.url = api
  obj.legacy = mtev.conf_get_string(CIRCONUS_LEGACY_URL_CONF_PATH) or "https://login.circonus.com"
  if obj._P == nil then obj._P = function(obj, ...) return _P(...) end end
  if obj._E == nil then obj._E = function(obj, ...) return _E(...) end end
  if obj._F == nil then obj._F = function(obj, ...) _F(...) return obj:exit(2) end end
  if obj._D == nil then obj._D = function(obj, ...) return _D(...) end end
  return obj
end

function prov:usable()
  if string.match(self.url,'^https?://') then
    _P("Using API at %s\n", self.url)
  else
    -- nil out the URL so broker.lua will exit out
    self.url = nil
    return false
  end
  if self.token == nil or self.url == nil then
    return false
  end
  local valid_token, message = validate_uuid(self.token)
  if not valid_token then
    _P("%s\n", message)
    return false
  end
  return true
end

function prov:detail(...)
  local cnt = select('#', ...)
  local key, val = ...
  if cnt == 0 then return self._detail end
  if cnt > 1 then self._detail[key] = val end
  return self._detail[key]
end

function prov:exit(rv)
  if self._exit then self._exit(rv) end
  return rv
end

function prov:provisioned()
  local pki = self:pki_info()
  if pki.cert.exists then return true end
  if not pki.csr.exists then return false end
  local code, broker = self:get_broker(self:cn())
  if code ~= 200 then error("API error") end
  if broker.csr == pki.csr.data then
    return true
  end
  return false
end

function prov:cn()
  if self.existing_cn == nil then
    self.existing_cn = self:extract_subject()
  end
  return self.existing_cn
end

function prov:extract_subject()
  local pki = self:pki_info()
  if pki.csr.data == nil then return nil end
  local req = mtev.newreq(pki.csr.data)
  if req == nil then return nil, data end
  local cn = req.subject:match("CN=([^/\n]+)")
  return cn, pki.csr.data
end

function prov:list()
  local avail
  local count = 0
  local code, obj = self:get_brokers()
  local existing_cn = self:cn()
  if _print == nil then _print = function() return end end
  for _,group in pairs(obj) do
    local once = true
    for _,broker in pairs(group._details) do
      broker.cluster = group
      if once then
        once = false
      end
      if avail == nil and broker.status == 'unprovisioned' then
        avail = broker.cn
      end
      count = count + 1
    end
  end
  return avail, obj
end
local prog = "provtool"

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
  _P("\n")
  _P("# Listing brokers\n\n")
  _P("  %s list\n", prog)
  _P("\n")
  _P("# (Re)Provision this broker\n\n")
  _P("  %s provision ...\n", prog)
  _P("  %s reprovision -cn <cn> ...\n", prog)
  _P("\t-cn <cn>\tspecify a broker CN, default first unprovisioned\n")
  _P("\t-ip <IP>\tset the broker IP address to which Circonus will connect\n")
  _P("\t-long <longitude>\tset the broker's longitude\n")
  _P("\t-lat <latitude>\tset the broker's latitude\n")
  _P("\t-name <name>\tan optional name for the broker\n")
  _P("\t-ext_host <name>\tpublic facing name for broker\n")
  _P("\t-ext_port <port>\tpublic facing port for broker\n")
  _P("\t-cluster_ip <IP>\tcluster facing IP for broker\n")
  _P("\t-nat\t\ttell Circonus that this broker will dial in (default)\n")
  _P("\t-nonat\t\ttell Circonus that this broker will be contacted by circonus (preferred)\n")
  _P("\t-cluster_id\t\tAdd this broker to an existing cluster_id\n")
  _P("\t-cluster_name\t\tChange the cluster's name (or join existing cluster, if -cluster_id omitted)\n")
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

local function extract_json_contents(text)
  local doc = mtev.parsejson(text)
  if doc == nil then return nil end
  local obj = doc:document()
  if obj == nil then return nil end
  return obj.contents
end

local function write_contents_if_changed(file, body, mode)
  if mode == nil then
     mode = tonumber(0644, 8)
  end
  local inp = io.open(file, "rb")
  if inp ~= nil then
    local data = inp:read("*all")
    inp:close()
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

function prov:_API(endpoint)
  return self.url .. endpoint
end


--
-- Circonus API
--
function prov:HTTP(method, url, payload, silent, _pp)
  mtev.log("debug/broker", "performing %s %s\n", method, url)
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

  if string.sub(url, 1, string.len(self.url)) == self.url then
    if self.token ~= nil then
      headers["X-Circonus-Auth-Token"] = self.token
      headers["X-Circonus-App-Name"] = "broker-provision"
    end
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

  self:_D(1, "%s -> %s %s\n", r.a, method, url)
  self:_D(2, "> %s\n", payload)

  headers.Host = host
  headers.Accept = 'application/json'
  local rv = client:do_request(method, uri, headers, payload, "1.1")
  client:get_response(1024000)

  _D(2, "< %s\n\n", output)

  if string.sub(url, 1, string.len(self.url)) == self.url then
    if client.code == 403 then
      _F("Permission denied! (bad CIRCONUS_AUTH_TOKEN?)\n")
      os.exit(2)
    elseif client.code == 401 then
      local response = json.decode(output)
      if response.message:match("^invalid api application") then
        mtev.log("error", "Looks like your token is pending validation.\n")
        local tok_url = in_headers['x-circonus-token-approval-url']
                    or 'the token management page'
        self:_F("Please visit %s to approve its use.\n", tok_url)
      elseif response.message:match("^invalid authentication token$") then
        mtev.log("error", "The supplied token is invalid.\n")
        self:_F("Please check that you have configured the correct token in CIRCONUS_AUTH_TOKEN.\n")
      else
        self:_F("Unauthorized request: %s\n", response.message)
      end
      os.exit(2)
    elseif client.code ~= 200 then
      self:_E("An unknown error (%s) has occurred accessing: %s\n", client.code, url)
      self:_E("Please report this issue to support@circonus.com\n")
      self:_E("%s\n", output)
    end
  end

  return client.code, _pp(output), output
end

function prov:get_ip()
  local code, obj = self:HTTP("GET", self:_API("/v2/canhazip"), nil, true)
  if obj ~= nil then return code, obj.ipv4 end
  return code, nil
end

function prov:get_account()
  local code, obj = self:HTTP("GET", self:_API("/v2/account/current"))
  if not obj then
    _F("Could not retrieve account information. Is api-url set correctly?\n")
    os.exit(2)
  end
  return obj
end

function prov:get_brokers(type)
  local code, obj, body
  local account = self:get_account()
  -- superadmin token gets to see all brokers
  if (account._cid == "/account/1") then
    code, obj, body = self:HTTP("GET", self:_API("/v2/broker"))
  else
    if type == nil then type = "enterprise" end
    code, obj, body = self:HTTP("GET", self:_API("/v2/broker?f__type=" .. type))
  end
  self.brokers = obj
  return code, obj, body
end

function prov:find_broker(cn, flush)
  if self.brokers == nil then self:get_brokers() end
  for _,group in pairs(self.brokers) do
    for _,broker in pairs(group._details) do
      if broker.cn == cn then return broker end
    end
  end
  return nil
end

function prov:legacy_get_broker(cn)
  -- old things won't die
  local url = mtev.conf_get("//circonus/appliance//credentials/circonus_url") or self.legacy
  self:_P("Using legacy API at %s\n", url)
  url = url .. "/api/json/agent?cn=" .. mtev.extras.url_encode(cn)
  local code, obj, raw = self:HTTP("GET", url)
  if code ~= 200 or obj == nil then
    self:_E("error fetching (legacy) broker info (%d):\n%s\n", code, string.sub(raw or "[no content]",1,1000))
  else
    -- legacy has this without an _
    if obj.stratcons ~= nil then obj._stratcons, obj.stratcons = obj.stratcons, nil end
    if obj.cert ~= nil then obj._cert, obj.cert = obj.cert, nil end
  end
  return code, obj, raw
end

function prov:get_broker(cn)
  if self:cn() ~= nil and self.token == nil then
    -- we have been provisioned (have a CSR) but not auth token
    -- this was likely setup by hand and we should do our best to not explode
    return self:legacy_get_broker(cn)
  end
  return self:HTTP("GET", self:_API("/v2/provision_broker/" .. mtev.extras.url_encode(cn)))
end

function prov:provision_broker(cn, data)
  local payload = mtev.tojson(data):tostring()
  return self:HTTP("PUT", self:_API("/v2/provision_broker/" .. mtev.extras.url_encode(cn)), payload)
end

function prov:fetch_url(url)
  return self:HTTP("GET", url, nil, true, function(o) return o end)
end

function prov:fetch_url_to_file(url, file, mode, transform)
  local code, body = self:fetch_url(url)
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
local function slurp_file(file)
  if file == nil then return nil end
  local inp = io.open(file, "rb")
  if inp == nil then return nil, nil end
  local data = inp:read("*all")
  inp:close()
  if data == nil then return nil, nil end
  return data
end

function prov:pki_info()
  if self.pki_locations == nil then
    local sslconfig_xpath = function(bit)
      return '//listeners//listener[@type="control_dispatch"]/ancestor-or-self::node()/sslconfig/' .. bit
    end
    self.pki_locations = {}
    self.pki_locations.keyfile = mtev.conf(sslconfig_xpath('key_file'))
    self.pki_locations.csrfile = self.pki_locations.keyfile:gsub("%.key$", ".csr")
    self.pki_locations.certfile = mtev.conf(sslconfig_xpath('certificate_file'))
    self.pki_locations.crl = mtev.conf(sslconfig_xpath('crl'))
    self.pki_locations.ca_chain = mtev.conf(sslconfig_xpath('ca_chain'))
  end
  local o = self.pki_locations
  local details = {}
  local needs = false

  -- key but no contents
  details.key = { file=o.keyfile, exists=not not mtev.stat(o.keyfile) }

  -- all the other bits have the whole file slurped
  details.crl = { file=o.crl, exists=not not mtev.stat(o.crl) }
  details.crl.data = slurp_file(details.crl.file)
  details.csr = { file=o.csrfile, exists=not not mtev.stat(o.csrfile) }
  details.csr.data = slurp_file(details.csr.file)
  details.cert = { file=o.certfile, exists=not not mtev.stat(o.certfile) }
  details.cert.data = slurp_file(details.cert.file)
  details.ca = { file=o.ca_chain, exists=not not mtev.stat(o.ca_chain) }
  details.ca.data = slurp_file(details.ca.file)
  return details
end

function prov:generate_key()
  local rsa = mtev.newrsa()
  if rsa == nil then
    return -1, "keygen failed"
  end
  local fd = mtev.open(self.pki_locations.keyfile,
                       bit.bor(O_CREAT,O_TRUNC,O_WRONLY), tonumber(0600,8))
  if fd < 0 then
    return fd, "Could not store broker private key: " .. keyfile
  end
  mtev.write(fd, rsa:pem())
  mtev.close(fd)
  mtev.chmod(self.pki_locations.keyfile, tonumber(0600, 8))
  return 0
end

function prov:generate_csr(cn,c,st,o)
  c = c or ''
  st = st or ''
  o = o or ''
  local subject = '/C=' .. c .. '/ST=' .. st .. '/O=' .. o .. '/CN=' .. cn
  local pki = self:pki_info()
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
  local req = key:gencsr({ subject=subj,
                           addext={subjectAltName={"DNS:"..cn}}})

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

function prov:fetch_certificate(myself)
  local cn = myself and myself._cid or self:cn()
  local pki = self:pki_info()
  local timeout = 0 

  local preamble = " -- attempting to fetch certificate for " .. cn
  repeat
    if timeout > 0 then
mtev.log("error", "Sleeping: %f\n", timeout)
      mtev.sleep(timeout)
      timeout = timeout * 2
    else
      timeout = 0.5
    end
    if timeout > 10 then timeout = 10 end
    _, myself = self:get_broker(cn)
    if myself ~= nil and myself._cert ~= nil then
      local success, error = write_contents_if_changed(pki.cert.file, myself._cert)
      if not success then self:_F("%s - error\nError writing to %s: %s!\n", preamble, pki.cert.file, error or "unknown error") os.exit(2) end
    elseif myself ~= nil and myself.csr == nil then
      self:_P("%s - error no CSR posted, something is wrong.\n", preamble)
    else
      self:_P("%s - unavailable.\n", preamble)
    end
    pki = self:pki_info()
  until pki.cert.exists
  self:_P("%s - ok.\n", preamble)

  local update_pki_bits = function(url,name,file,transform)
    local preamble = " -- updating " .. name
    if file == nil then
      self:_D(1, "%s - %s skipped\n", preamble, name)
      return true
    end
    local rv, error = self:fetch_url_to_file(url, file, tonumber(0644,8), transform)
    if not rv then
      local body = mtev.parsejson(error)
      if body ~= nil then body = body:document() end
      if type(body) == 'table' then
        error = body.explanation or body.message or body.status or error
      end
      self:_F("%s - error\nFailed to pull Circonus PKI data\n - from %s\n - to %s\n - error: %s\n",
         preamble, url, file, error or "unknown error")
    end
    return rv, error
  end

  local rv1, rv2
  if self.token ~= nil then
    rv1 = update_pki_bits(self.url .. "/pki/ca.crt", "CA", pki.ca.file, extract_json_contents)
    rv2 = update_pki_bits(self.url .. "/pki/ca.crl", "CRL", pki.crl.file, extract_json_contents)
  else
    rv1 = update_pki_bits(self.legacy .. "/pki/ca.crt", "CA", pki.ca.file)
    rv2 = update_pki_bits(self.legacy .. "/pki/ca.crl", "CRL", pki.crl.file)
  end
  return rv and rv2
end

--
--- Tasks
--

function do_task_list(p, _print)
  local count = 0
  local avail, obj = p:list()
  local existing_cn = p:cn()
  if _print == nil then _print = function() return end end
  local fmt1 = "| %-60s | %-21s |\n"
  local fmt2 = "| %-40s (%-17s) | %-21s |\n"
  _print(fmt1, "Group -> CN", "Status")
  local div = "+--------------------------------------------------------------+-----------------------+\n"
  _print(div)
  for _,group in pairs(obj) do
    local once = true
    for _,broker in pairs(group._details) do
      if once then
        _print(fmt1, group._name, string.sub(group._cid, 9))
        once = false
      end
      local mine_str = ""
      if existing_cn ~= nil and existing_cn == broker.cn then
        mine_str = " <- me"
      end
      if broker.name ~= nil and broker.name ~= broker.cn:match("[^%.]+") then
        _print(fmt2, "  -> " .. broker.cn, broker.name, broker.status .. mine_str)
      else
        _print(fmt1, "  -> " .. broker.cn, broker.status .. mine_str)
      end
      count = count + 1
    end
    _print(div)
  end
  if count < 1 then
    _print("No brokers found\n")
  end
end

function prov:provision(initial)
  if initial == nil then initial = true end
  local attrs = self:detail()
  local pki = self:pki_info()
  local existing_cn = self:extract_subject()
  local account = self:get_account()
  self:get_brokers() -- sets the cached copies

  --
  -- If a cn was specified on the command line and it
  -- isn't in the list of broker cns, we can stop now.
  --
  if attrs.cn ~= nil then
    if self:find_broker(attrs.cn) == nil then
      return self:_F("\"%s\" was specified as the cn, but that cn isn't in the list of brokers.\n\n" ..
         "Use 'provtool list' to see brokers.\n" , attrs.cn)
    end
    if existing_cn ~= nil and existing_cn ~= attrs.cn then
      return self:_F("Specified cn (%s) does not match the one found in the csr (%s)\n" ..
           "Please remove the csr file or change the -cn flag.",
           attrs.cn, existing_cn)
    end
  end

  if attrs.cn == nil and not initial then
    return self:_F("Must specifiy an CN for reprovisioning\n")
  end

  --
  -- First truth: we need a key
  --
  if not pki.key.exists then
    self:_P(" -- generating RSA key...\n")
    local rv, err = self:generate_key()
    if rv ~= 0 then return self:_F("Error generating key: %s\n", err) end
  end

  --
  -- Next it gets more complicated.  This might not be our first rodeo.
  -- Perhaps we've been provisioned already or we started the process and
  -- failed to finish it... that is detected here.
  --
  local myself
  if existing_cn ~= nil then
    local code
    code, myself = self:get_broker(existing_cn)
    if code ~= 200 then
      self:_F(" ** Perhaps you have the wrong auth token\n")
    end
    if myself._status == 'unprovisioned' or (initial and pki.csr.data ~= myself.csr) then
      -- We generated a CSR to provision ourselves, but they never got it
      self:_P(" ** incomplete provisioning, starting over...\n")
      self:_F(" You must remove the CSR file to continue:\n  rm -f /opt/noit/prod/etc/ssl/appliance.csr\n")
      os.exit(2)
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
    self:_E("This broker is already provisioned as %s\n", existing_cn)

    --
    -- It might be that we've just requested to update metadata such as
    -- our IP address, name, tags or location
    --
    attrs.set_noit_name = attrs.set_noit_name or myself.noit_name
    attrs.set_cluster_name = attrs.set_cluster_name or myself.cluster_name
    attrs.set_ipaddress = attrs.set_ipaddress or myself.ipaddress
    attrs.cluster_id = attrs.set_cluster_id or myself.cluster_id
    -- Let's see if our metadata has changed, is so we'll PUT new info
    local check_diff = function (attr)
      if attrs["set_" .. attr] == nil then return false end
      if tostring(myself[attr]) ~= tostring(attrs["set_" .. attr]) then
        self:_P("%s has changed %s -> %s\n", attr, myself[attr], attrs["set_" .. attr])
        return true
      end
      return false
    end
    local different = false
    for _, attr in ipairs({'noit_name', 'cluster_namme', 'ipdaddress',
      'latitude', 'longitude', 'contact_group_id', 'external_host', 'external_port',
      'cluster_id', 'cluster_ip', 'cluster_name', 'prefer_reverse_connection'}) do
      different = check_diff(attr)
      if different then break end
    end
    if not different then
      self:_P(" -- broker metadata up-to-date")
    else
      if attrs.set_ipaddress == nil and (myself.prefer_reverse_connection ~= 1 or attrs.set_prefer_reverse_connection ~= 1) then
        self:_F("We could not detemine your public IP address, please use -ip <ip>\n")
      end
      self:_P(" -- updating information\n")
      local code, obj, body = self:provision_broker(existing_cn, {
        csr = pki.csr.data,
        external_host = attrs.set_external_host,
        external_port = attrs.set_external_port,
        cluster_ip = attrs.set_cluster_ip,
        ipaddress = attrs.set_ipaddress,
        latitude = attrs.set_latitude,
        longitude = attrs.set_longitude,
        contact_group_id = attrs.set_contact_group_id,
        make_public = attrs.set_make_public,
        noit_name = attrs.set_noit_name,
        cluster_name = attrs.set_cluster_name,
        port = 43191,
        prefer_reverse_connection = attrs.set_prefer_reverse_connection,
        rebuild = false,
        cluster_id = attrs.set_cluster_id
      })
      _, myself = self:get_broker(existing_cn)
    end
    self:fetch_certificate(myself)
    return self:exit(0)
  end

  if attrs.cn == nil then
    attrs.cn = self:list() -- this just returns the first unprovisioned
  end
  if tablelength(self.brokers) < 1 or attrs.cn == nil then
    return self:_F("There are no broker slots available on this account.\n" ..
       "Please visit your brokers page to add one.\n")
  end

  -- Now we generate a CSR and submit it.
  if attrs.set_ipaddress == nil and attrs.set_prefer_reverse_connection ~= 1 then
    return self:_F("We could not detemine your public IP address, please use -ip <ip>\n")
  end
  self:_P(" -- generating CSR...\n")
  local rv, err = self:generate_csr(attrs.cn,account.country_code,'',account_name)
  if rv ~= 0 then
    return self:_F("Error creating certificate signing request:\n%s\n", err)
  end
  local existing_cn, csr_contents = self:extract_subject()
  existing_cn = attrs.cn
  code, myself = self:get_broker(existing_cn)
  if attrs.set_noit_name == nil then attrs.set_noit_name = myself.noit_name end

  local code, obj, body = self:provision_broker(existing_cn, {
    noit_name = attrs.set_noit_name,
    cluster_name = attrs.set_cluster_name,
    port = 43191,
    latitude = attrs.set_latitude,
    longitude = attrs.set_longitude,
    contact_group_id = attrs.set_contact_group_id,
    external_host = attrs.set_external_host,
    external_port = attrs.set_external_port,
    cluster_ip = attrs.set_cluster_ip,
    rebuild = false,
    ipaddress = attrs.set_ipaddress,
    prefer_reverse_connection = attrs.set_prefer_reverse_connection,
    csr = csr_contents,
    make_public = attrs.set_make_public,
    cluster_id = attrs.set_cluster_id,
    assert_status = attrs.assert_status
  })
  if code ~= 200 then
    return self:_F("Fatal error attempt to provision broker...\n" .. (body or "<empty>"))
  end

  return self:fetch_certificate(myself)
end

function prov:rebuild(cn)
  if cn == nil then cn = self:cn() end
  if cn == nil then
    return self:_F("rebuild requires a cn to be specified or this broker to be provisioned\n")
  end
  local code, obj, body = self:provision_broker(cn, { rebuild = true })
  if code ~= 200 then
    return self:_F("Fatal error attempting to rebuild: %s\n", body)
  end
  return 0
end

function prov:fetch_certs(cn)
  if cn == nil then cn = self:cn() end
  if cn == nil then
    self:_F("fetch cert requires a cn to be specified or this broker to be provisioned\n")
  end
  if self:find_broker(cn) == nil then
    self:_F("You don't have access to a broker with cn %s\n", cn)
  end
  local code, myself = self:get_broker(cn)
  if not (code == 200 and myself) then
    self:_F("Failed fetching broker information for cn %s.\n", cn)
  end
  if self:fetch_certificate(myself) then
    self:_P("Updated PKI info\n")
  else
    self:_P("Failed to update PKI info\n")
  end
end

--
-- Cli parser
--
debug = 0
local opts = {
  -- use -d (repeated) for debuging output,
  d = function(n) debug = debug + 1 end
}

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
  validate = validate_uuid,
  description = "the Circonus API token for provisioning"
}

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

function nextargs_iter(arr)
  local i = 1
  return function()
    i = i + 1
    return arr[i-1]
  end
end

function parse_cli(p, params)
  local obj = {}
  if params == nil then params = arg end
  local next = nextargs_iter(params)
  local prog = next()

  obj.command = next()
  if obj.command == 'config' then
    obj.subcommand = next()
    if obj.subcommand == 'get' then
      return os.exit(do_config_get(next()))
    elseif obj.subcommand == 'set' then
      return os.exit(do_config_set(next(), next()))
    end
    _E("invalid config subcommand: %s\n", subcommand)
    usage()
    return os.exit(2)
  elseif obj.command == 'list' then 
    obj.subcommand = next()
    -- nothing
  elseif obj.command == 'provision' or obj.command == 'reprovision' then
    if obj.command == "provision" then p:detail('assert_status', 'unprovisioned') end
    opts.cn = function(n) p:detail('cn', n()) end
    opts.cluster_id = function(n) p:detail('set_cluster_id', n()) end
    opts.cluster_ip = function(n) p:detail('set_cluster_ip', n()) end
    opts.cluster_name = function(n) p:detail('set_cluster_name', n()) end
    opts.contact_group = function(n) p:detail('set_contact_group_id', n()) end
    opts.ext_host = function(n) p:detail('set_external_host', n()) end
    opts.ext_port = function(n) p:detail('set_external_port', n()) end
    opts.ip = function(n) p:detail('set_ipaddress', n()) end
    opts.name = function(n) p:detail('set_noit_name', n()) end
    opts.lat = function(n) p:detail('set_latitude', n()) end
    opts.long = function(n) p:detail('set_longitude', n()) end
    opts.nat = function(n) p:detail('set_prefer_reverse_connection', 1) end
    opts.nonat = function(n) p:detail('set_prefer_reverse_connection', 0) end
    opts.public = function(n) p:detail('set_make_public', 1) end
  elseif obj.command == 'rebuild' then
    opts.cn = function(n) p:detail('cn', n()) end
  elseif obj.command == 'cert' then
    opts.cn = function(n) p:detail('cn', n()) end
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
  return obj
end

function main()
  local p = prov:new({
    --_P = function(...) mtev.log("stdout", ...) end,
    _exit = os.exit,
  })
  local todo = parse_cli(p)
  if p.token == nil then
    _F("Missing Circonus API token!\nPlease set it via:\n\n%s config set api-token <uuid>\nor CIRCONUS_AUTH_TOKEN environmemnt variable\n", prog)
  end
  if todo.command == "list" then do_task_list(p, _P) return os.exit(0)
  elseif todo.command == "provision" then return os.exit(p:provision(true))
  elseif todo.command == "reprovision" then return os.exit(p:provision(false))
  elseif todo.command == "rebuild" then return os.exit(p:rebuild())
  elseif todo.command == "cert" then return os.exit(p:fetch_certs())
  else
    _F("Something went very wrong.\n")
  end
  os.exit(2)
end

return prov
