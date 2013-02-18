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
                Please check to make sure all of the following security settings are correct.
      </p>
      <br style="clear:both"/>
        <h2 id="provision-head" class="form-head">Configure Security</h2>
      <br style="clear:both"/>
        <form id="login_form" method="POST">
          <fieldset id="pki" class="first_step">
            <legend><em>1.</em> Security Information</legend>
            <div id="circonus-pki">
              <label for="circonus_url">Circonus Base URL</label>
              <input id="circonus_url" type="text" name="circonus_url" value="]=])
    http:write(circonus_url())
    http:write([=[" />
              <button id="fetch" type="button">Configure</button>
            </div>
          </fieldset>
          <div id="pki-progress">
            <ul>
              <li id="pki-key-ready" class="pending">Private Key</li>
              <li id="pki-ca-ready"  class="pending">Certificate Authority</li>
              <li id="pki-crl-ready"  class="pending">Certificate Revocation List</li>
            </ul>
          </div>
        </form>
      </div>
      <div id="provision-step">
        <a href="/provision]=])
if inside() then
  http:write("#inside")
end
http:write([=[">Provision this Broker</a>
      </div>
      <div id="dash-step">
        <a href="/dash">Go the Broker's Dashboard</a>
      </div>
    </div>
    </div>
    <script src="/js/jquery.min.js" type="text/javascript"></script>
    <script src="/js/pki.js" type="text/javascript"></script>
  </body>
</html>
]=])
