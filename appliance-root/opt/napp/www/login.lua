local req = http:request()
if req:method() == "POST" then
  local needed_user = noit.conf_get_string("/noit/circonus/appliance//credentials/username")
  local needed_pass = noit.conf_get_string("/noit/circonus/appliance//credentials/password")
  local f = req:form()
  if f ~= nil then
    if needed_user ~= nil and needed_pass ~= nil and
      f['username'] == needed_user and f['password'] == needed_pass then
      http:set_cookie("appsession", new_session())
      redirect(http, "/dash")
    end
  end
end

http:write([=[
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <link href="/c/s.css" rel="stylesheet" media="screen" type="text/css" />
    <link rel="shortcut icon" type="image/ico" href="/favicon.ico" />
  </head>
<body class="enterprise initial">
	<div class="page">
	<div id="page-content" class="clear">
             <div id="userlogin">
                <h2 class="form-head">Login to Appliance</h2>
                <form class="sign-in" method="post" action="/login">
						<p>
		    				<label for="id_username">Username</label>
		    				<input id="id_username" type="text" name="username" maxlength="30" />
						</p>
						<p>
	    					<label for="id_password">Password</label>
		    				<input type="password" name="password" id="id_password" />	
						</p>

					
					<input type="submit" value="login" />
					<input type="hidden" name="next" value="" />
				</form>

            </div>	
            <img class="logo" src="/i/content/circonus-enterprise-icon.png" />
            <p class="intro">
            Welcome back to the Circonus Enterprise Broker appliance. Login to the dashboard to view logs and manage your broker.  
            </p>
        </div>
	</div>
</body>
</html>
]=])
