http:header('Content-Type', 'application/json')
local json = require("json")

local needs_pki = needs_pki()
local needs_provisioning, details = needs_provisioning()

http:write(json.encode({
  pki = not needs_pki,
  provisioned = not needs_provisioning,
  details=details
}))
