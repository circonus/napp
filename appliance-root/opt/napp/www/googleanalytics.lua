local req = http:request()
local client_id = noit.conf_get_string('/noit/modules//lua/module[@name="googleanalytics:m7"]//config/client_id')
local client_secret = noit.conf_get_string('/noit/modules//lua/module[@name="googleanalytics:m7"]//config/client_secret')
local api_key = noit.conf_get_string('/noit/modules//lua/module[@name="googleanalytics:m7"]//config/api_key')

if client_id == nil then client_id = '' end
if client_secret == nil then client_secret = '' end
if api_key == nil then api_key = '' end

if req:method() == "POST" then
  local form = req:form()

  if type(form['client_id']) ~= 'boolean' and form['client_id'] ~= nil and form['client_id'] ~= '' then
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m1"]/include/config/client_id',
                                      form['client_id'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m2"]/include/config/client_id',
                                      form['client_id'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m3"]/include/config/client_id',
                                      form['client_id'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m4"]/include/config/client_id',
                                      form['client_id'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m5"]/include/config/client_id',
                                      form['client_id'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m6"]/include/config/client_id',
                                      form['client_id'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m7"]/include/config/client_id',
                                      form['client_id'])
  end
  if type(form['client_secret']) ~= 'boolean' and form['client_secret'] ~= nil and form['client_secret'] ~= '' then
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m1"]/include/config/client_secret',
                                      form['client_secret'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m2"]/include/config/client_secret',
                                      form['client_secret'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m3"]/include/config/client_secret',
                                      form['client_secret'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m4"]/include/config/client_secret',
                                      form['client_secret'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m5"]/include/config/client_secret',
                                      form['client_secret'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m6"]/include/config/client_secret',
                                      form['client_secret'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m7"]/include/config/client_secret',
                                      form['client_secret'])
  end
  if type(form['api_key']) ~= 'boolean' and form['api_key'] ~= nil and form['api_key'] ~= '' then
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m1"]/include/config/api_key',
                                      form['api_key'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m2"]/include/config/api_key',
                                      form['api_key'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m3"]/include/config/api_key',
                                      form['api_key'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m4"]/include/config/api_key',
                                      form['api_key'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m5"]/include/config/api_key',
                                      form['api_key'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m6"]/include/config/api_key',
                                      form['api_key'])
    noit.conf_replace_string('/noit/modules/include/lua/module[@name="googleanalytics:m7"]/include/config/api_key',
                                      form['api_key'])
  end
  error("Google Analytics values updated. Please restart your broker.")
end

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
        <div id="googleanalytics">
          <div class="content-col">
          <img class="logo" src="/i/content/circonus-enterprise-icon.png" />
          <p class="intro">
                    Please enter the Client ID, Client Secret, and API Key associated with your Google API account below. This will allow your agent to communicate via your Google API account for Google Analytics checks.
          </p>
          <br style="clear:both"/>
            <form id="analytics_form" method="POST">
              <p><label for="id_clientid">Client ID:</label> <input id="id_clientid" type="text" name="client_id" maxlength="500" value="]=])
http:write(client_id)
http:write([=["/>
              </p>
              <p><label for="id_clientsecret">Client Secret:</label> <input id="id_clientsecret" type="text" name="client_secret" maxlength="500" value="]=])
http:write(client_secret)
http:write([=["/>
              </p>
              <p><label for="id_apikey">API Key:</label> <input id="id_apikey" type="text" name="api_key" maxlength="500" value="]=])
http:write(api_key)
http:write([=["/>
              </p>
              <input type="submit" value="Submit &raquo;" />
            </form>
          </div>
        </div>
      </div>
    </div>
    <script src="/js/jquery.min.js" type="text/javascript"></script>
    <script src="/js/googleanalytics.js" type="text/javascript"></script>
  </body>
</html>
]=])
