local req = http:request()
http:status(404, "NOT FOUND")
http:write([=[<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
<html lang="en">
<head>
  <meta http-equiv="content-type" content="text/html; charset=utf-8">
  <title>Page not found at /ld&lt;</title>
  <meta name="robots" content="NONE,NOARCHIVE">
  <style type="text/css">
    html * { padding:0; margin:0; }
    body * { padding:10px 20px; }
    body * * { padding:0; }
    body { font-family: 'Trebuchet MS', 'Lucida Grande', 'Liberation Sans Narrow', 'Nimbus Sans L', sans-serif; background:#eee; }
    body>div { border-bottom:1px solid rgb(229, 229, 229); }
    h1 { font-weight:normal; margin-bottom:.4em; }
    h1 span { font-size:60%; color: rgb(66, 119, 183); font-weight:normal; }
    table { border:none; border-collapse: collapse; width:100%; }
    td, th { vertical-align:top; padding:2px 3px; }
    th { width:12em; text-align:right; color: rgb(66, 119, 183); padding-right:.5em; }
    #info { background:#f6f6f6; }
    #info ol { margin: 0.5em 4em; }
    #info ol li { font-family: monospace; }
    #summary { background: #959697; color: rgb(45, 88, 125); }
    #summary h1 span { font-size:60%; color: #333; font-weight:normal; }
    #summary th { width:12em; text-align:right; color: #333; padding-right:.5em; }
    #explanation { background:#eee; border-bottom: 0px none; }
  </style>
</head>
<body>
  <div id="summary">
    <h1>Page not found <span>(404)</span></h1>
    <table class="meta">
      <tr>
        <th>Request Method:</th>
        <td>]=])
http:write(req:method())
http:write([=[</td>
      </tr>
      <tr>
        <th>Request URL:</th>
      <td>]=])
http:write(http:htmlentities(req:uri(),true))
http:write([=[</td>
      </tr>
    </table>
  </div>
</body>
</html>
]=])
