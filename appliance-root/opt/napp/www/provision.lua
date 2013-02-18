local req = http:request()
local post = req:form()
local error
-- You can't get here if you already have a csr

if not needs_provisioning() then redirect(http, "/") end

http:write([=[<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <link href="/c/s.css" rel="stylesheet" media="screen" type="text/css" />
    <link rel="shortcut icon" type="image/ico" href="/favicon.ico" />
  </head>
  <body class="enterprise">
    <div id="masthead">
      <div id="header">
        <span class="app-logo"><a href="http://circonus.com/" title="Circonus Home">Circonus | Organization-wide Monitoring</a></span>
      </div>
    </div>
    <div class="page">
    <div id="page-content" class="clear">
      <div class="content-col">
      <img class="logo" src="/i/content/circonus-enterprise-icon.png" />
      <p class="intro">
		This Enterprise Broker has not yet been provisioned.  During this three step process you will be asked to log into your Circonus account, and identify and associate this broker with your account.
      </p>]=])
if error ~= nil then
  error = http:htmlentities(error, true)
  error = error:gsub("\n","<br/>")
  http:write([=[<br style="clear:both"/>
                <div id="error"><p>]=])
  http:write(error)
  http:write([=[</p></div>]=])
end
http:write([=[
      <br style="clear:both"/>
        <h2 id="provision-head" class="form-head">Provision Broker</h2>
      <br style="clear:both"/>
        <form id="login_form" method="POST">
          <fieldset id="step_1">
            <legend><em>1.</em> Enter Circonus Credentials</legend>
            <div id="circonus-creds">
            <div class="inside">
              <label for="api_url">Circonus Base URL</label>
              <input id="api_url" type="text" name="api_url" value="]=])
    http:write(circonus_url())
    http:write([=[" />
            </div>
              <label for="login_email">Email</label>
              <input id="login_email" type="text" name="email" />
              <label for="login_password">Password</label>
              <input id="login_password" type="password" name="password" />
              <button id="login" type="button">Login</button>
            </div>
          </fieldset>
          <fieldset id="step_2">
            <legend><em>2.</em> Select Account</legend>
            <select name="account">
            </select>
          </fieldset>
          <fieldset id="step_3" class="last_step">
          <legend><em>3.</em> Select Broker to Provision</legend>
            <ul id="avail-agents">
            </ul>
            <p class="submit-block">
              <button type="submit" value="Provision Broker &raquo;">Provision Broker &raquo;</button>
            </p>
          </fieldset>
        </form>
      </div>
    </div>
    </div>
        <script src="/js/jquery.min.js" type="text/javascript"></script>
        <script src="/js/provision.js" type="text/javascript"></script>
  </body>
</html>
]=])
