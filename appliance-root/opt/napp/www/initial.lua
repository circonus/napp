local req = http:request()
if req:method() == "POST" then
  local form = req:form()
  if form['password'] == form['password_again'] then
    if noit.conf("noit/circonus") == nil then
      if not noit.conf("/noit/circonus", nil) then
        error("cannot create /noit/circonus")
      end
    end
    if noit.conf("/noit/circonus/appliance") == nil then
      if not noit.conf("/noit/circonus/appliance", nil) then
        error("cannot create /noit/circonus/appliance")
      end
    end
    local user_set = noit.conf_get_string("/noit/circonus/appliance/username",
                                          form['username'])
    local pass_set = noit.conf_get_string("/noit/circonus/appliance/password",
                                          form['password'])
    noit.conf_get_boolean("/noit/circonus/appliance/inside", not not form['inside'])
    if user_set and pass_set then 
      redirect(http, "/login")
    end
    http:write("COULD NOT SET PASSWORD")
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
                <h2 class="form-head">Set Initial Password</h2>
                <form class="sign-in" action="" method="post">
                    <p><label for="id_username">Username:</label> <input id="id_username" type="text" name="username" maxlength="30" /></p>
<p><label for="id_password">Password:</label> <input id="id_password" type="password" name="password" maxlength="30" /></p>
<p><label for="id_password_again">Password again:</label> <input id="id_password_again" type="password" name="password_again" maxlength="30" /></p>
<p><labal for="id_inside">Circonus Inside Install:</label> <input id="id_inside" type="checkbox" name="inside" /></p>
                     
                    <input type="submit" value="Submit &raquo;" />
                </form>
            </div>	
            <img class="logo" src="/i/content/circonus-enterprise-icon.png" />
            <p class="intro">
            Welcome to your new Circonus Enterprise Broker.  In order to get started you will need to set a username and password for access to this appliance going forward.  This is not your Circonus online password, but simply a username and password that will protect your device from unauthorized administrative access.  You will need this password to access the appliance for configuration and maintenance.
            </p>
        </div>
        </div>
    </body>
</html>
]=])
