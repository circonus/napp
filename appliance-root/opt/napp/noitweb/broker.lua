module(..., package.seeall)

local sessions = {}
local cached_agent_info = {}

local _J = function(t) return mtev.tojson(t):tostring() end
local HttpClient = require('mtev.HttpClient')
local json = require('json')
local noit = require('noit')
local mtev = require('mtev')
local prov = require('prov')
local broker
local cached_broker_info

function do_periodically(f, _period, before)
  local period = 0
  if before then period = _period end
  return function()
    while true do
      mtev.sleep(period)
      local rv, err = pcall(f)
      if not rv then mtev.log("error", "lua --> " .. err .. "\n") end
      period = _period
    end
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
local reverse_sslconfig
function update_reverse_sockets(info)
  local wanted = {}
  local pki_info = broker:pki_info()
  if reverse_sslconfig == nil then
    reverse_sslconfig = {
      certificate_file = pki_info.cert.file,
      key_file = pki_info.key.file,
      ca_chain = pki_info.ca.file
    }
    if pki_info.crl and pki_info.crl.exists then
      sslconfig.crl = pki_info.crl.file
    end
  end
  local subject = broker:cn()

  -- if the prefer_reverse_connection flag isn't set, we have no stratcons
  if info.prefer_reverse_connection ~= 1 then
    mtev.log("debug/broker", "prefer_reverse_connection is off\n")
    info._stratcons = {}
  end
  for i, key in pairs(info._stratcons) do
    -- resolve the host, if needed
    if not noit.valid_ip(key.host) then
      local ltarget = noit.hosts_cache_lookup and noit.hosts_cache_lookup(key.host)
      if ltarget ~= nil then key.host = ltarget end
    end
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
                         reverse_sslconfig,
                         { cn = details.cn,
                           endpoint = subject,
                           xbind = "*"
                         })
      reverse_sockets[id] = details
    end
    local conninfo = mtev.reverse_details(details.host, details.port)
    if cached_broker_info ~= nil and (conninfo == nil or not conninfo.connected) then
      mtev.log("debug/broker", "reverse disconnected, dropping broker info cache\n")
      cached_broker_info = nil
    end
  end
end

function reverse_socket_maintain()
  mtev.log("debug/broker", "Checking reverse socket configuration\n")
  while true do
    local subj = broker:cn()
    if subj == nil then
      mtev.log("debug/broker", "No subject set (yet)\n")
    else
      if cached_broker_info == nil then
        local code, obj = broker:get_broker(subj)
        if code == 200 and obj ~= nil then
          cached_broker_info = obj
        end
      end
      if cached_broker_info ~= nil then
        update_reverse_sockets(cached_broker_info)
      end
    end
    mtev.sleep(1)
  end
end

local want_caql = mtev.conf_get_boolean('//caql/@enabled')

function start_upkeep()
  local thread, tid = mtev.thread_self()

  mtev.sleep(0) -- yield once to the eventer.

  if want_caql and os.getenv("LOAD_CAQL") == "yes" then
    local caqlmain = require('mainloop')
    mtev.coroutine_spawn(caqlmain.start)
  end

  -- protect against concurrent use
  if tid ~= 0 then return end

  broker = prov:new()
  local cn = broker:cn()
  if broker:usable() then
    broker:provision()
  elseif broker.url == nil then
    mtev.log("error", "**************\n")
    mtev.log("error", "CIRCONUS_API_URL must start with http:// or https:// and be a valid URL\n")
    mtev.log("error", "**************\n")
    os.exit(2)
  elseif cn == nil then
    mtev.log("error", "**************\n")
    mtev.log("error", "Missing Circonus API token!\n")
    mtev.log("error", "Please set it via:\n")
    mtev.log("error", "\tprovtool config set api-token <uuid>\n")
    mtev.log("error", "or setting CIRCONUS_AUTH_TOKEN=<uuid> in your environment\n")
    mtev.log("error", "**************\n")
    os.exit(2)
  else
    mtev.log("error", "**************\n")
    mtev.log("error", "Booting in legacy mode, you are truly on your own.\n")
    mtev.log("error", "Reinstalling via the documentation is highly recommended.\n")
    mtev.log("error", "**************\n")
  end


  -- Only do this in a single thread
  mtev.coroutine_spawn(do_periodically(filtersets_maintain, 10800, true))
  mtev.coroutine_spawn(do_periodically(reverse_socket_maintain, 60))
  mtev.coroutine_spawn(do_periodically(function() broker:fetch_certificate() end, 3600, true))
end
