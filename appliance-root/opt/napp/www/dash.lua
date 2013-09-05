local inside = noit.conf_get_boolean('/noit/circonus/appliance/inside')
if inside == nil or inside == '' then inside = false end

http:write([=[<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
    <link href="/c/s.css" rel="stylesheet" media="screen" type="text/css" />
    <link rel="shortcut icon" type="image/ico" href="/favicon.ico" />
        <style type="text/css">
            #logs_panel{ 
            	display: none; /* hidden by default */
            } 
            pre { 
            	font-family: courier;
            	background-color:#F8F8F8;
		border-color:#E7E8E8;
		border-style:solid;
		border-width:0 2px 2px;
		font-size:0.6875em;
		margin-top:0;
		padding:14px; 
            }
            
            .enterprise .content-col.narrow{
            	width: 260px;
            }
            h4.prefs-head{
            	font-family:"Trebuchet MS","Lucida Sans Unicode","Lucida Grande","Lucida Sans",Arial,sans-serif;
		font-style:normal;
		font-weight:400;
		text-transform:uppercase;
		border-bottom:2px solid #E7E8E8;
		margin-bottom:2px;
		padding-bottom:8px;
		color:#9FA3A5;
           }
			
			#updates_panel li{
				border-bottom:1px dashed #E7E8E8;
				font-size:0.8125em;
				padding:6px 0;
			}
			#updates_panel li span.package-version { float:right; }
			#config_panel li{
				border-bottom:1px dashed #E7E8E8;
				font-size:0.8125em;
				padding:6px 0;
			}
			#config_panel li span.package-version { float:right; }
			
			button#perform_updates {
				background:url("../i/present/update-btn.png") no-repeat scroll 167px 5px #E7E8E8;
				margin-top:1em;
				padding:6px 36px 6px 10px;
				width:100%;
			}
			
			button#perform_updates:focus,
			button#perform_updates:hover{
				background:url("../i/present/update-btn.png") no-repeat scroll 167px -35px #33597a;
			} 	
			
			#agent-switch.active, 
			#agent-switch:hover {
				background:url("../i/present/switch-sprite.png") no-repeat scroll left -1px transparent;
				cursor: pointer;
			}
			
			#agent-switch:hover{
				color: #ef9943;
			}
			
			#agent-switch {
				float:none;
				margin-left:15px;
				text-align:center;
				width:9em;
				font-family:Georgia,Serif;
				font-size:1em;
				font-style:italic;
				padding:.875em 0 2em 5.25em;
				color:#9FA3A5;
			}
			
			#agent-switch.active:hover, 
			#agent-switch{
				background:url("../i/present/switch-sprite.png") no-repeat scroll left -205px transparent;
				cursor: pointer;
			}
			
			#agent-switch.active{
				color:#2D587D;	
			}
			
			#agent-switch.active:hover{
				
			}
			
			.enterprise .sub-container{
				border:none;
				margin-bottom: 0;
				margin-top: -9px;
			}
			
			.enterprise .sub-container.lead{
				padding: 0;	
			}
			#appliance-logout{
				float: right;
				font-family: Georgia, serif;
				font-style: italic;
				font-size: 0.4333em;
				margin-top: 15px;
			}
			
			li.log{
				font-size:0.8125em;
				line-height:1.4;
				padding:8px 16px;
				vertical-align:middle;
				border-bottom:1px dashed #E7E8E8;
			}
			
			li.log:hover{
				background:url("../i/present/table-bkgrnd-light.png") repeat-x scroll 0 0 #E7E8E8;
			}
			
			li.log.active{
				background:url("../i/present/table-bkgrnd.png") repeat-x scroll 0 0 #E7E8E8;
				color:#FFFFFF;
				border-bottom:1px solid #E7E8E8;
			}
			
			li.log .action{
				background:url("../i/present/enterprise-arrows.png") no-repeat scroll right 8px transparent;
				width: 100%;
				display: block;
			}
			
			li.log:hover .action{
				background:url("../i/present/enterprise-arrows.png") no-repeat scroll right -21px transparent;
			}	
			li.log.active .action{
				background:url("../i/present/enterprise-arrows.png") no-repeat scroll right -86px transparent;
			}
			
			li.log.active:hover{
				background:url("../i/present/table-bkgrnd-dark.png") repeat-x scroll 0 0 #E7E8E8;
			}
			ul#updates{
				max-height:196px;
				overflow-x:hidden;
				overflow-y:auto;
			}	
        </style>    
  </head>
  <body class="enterprise">
    <div class="page">
    <div id="page-content" class="clear">
      <div class="content-col wide left">
      	<h2>Appliance Logs <a id="appliance-logout" href="/logout">(logout of the appliance)</a></h2>
        
        
        <p id="logs_panel">
        </p>
       </div> 
        <div class="content-col narrow right">]=])
if inside == true then
http:write([=[ <div id="config_panel" class="sub-container clear">
        		<h4 class="prefs-head">Inside Configuration </h4>
                        <ul id="updates">
                          <li><a href="/googleanalytics">Google Analytics</a></li>
                        </ul>
                </div>]=])
end
http:write([=[  <div id="updates_panel" class="sub-container clear">
        		<h4 class="prefs-head">Available Updates </h4>
            	<p id="updates_message">Looking for updates...</p>
        	</div>
        	
        </div>	
        </div>
     </div>
        
        <script src="/js/jquery.min.js" type="text/javascript"></script>
        <script>
jQuery(function ()
{
    var available_updates = 0,
        polling_interval = 1000 * 10,
        polling = false,
        $updates_section = $('#updates_panel'),
        $updates_message = $('#updates_message'),
        $logs_section = $('#logs_panel'),
        updates_status,
        UPDATES_DONE = "idle",
        urls = {
            available_updates: "/api/json/check_for_updates",
            update_status: "/api/json/check_for_updates",
            perform_updates: "/perform-updates",
            list_logs: "/api/json/update_logs",
            get_log: "/api/json/update_log_contents"
        }
    ;

    /* Main */
    checkForUpdates(showUpdateList);
    getLogs();

    function checkForUpdates(cb)
    {
        $.ajax({
            type: 'get',
            dataType: 'json',
            url: urls.available_updates,
            success: function (data)
            {
                if (data.packages) available_updates = data.packages.length;
                if (data.status){
                    updates_status = data.status;
                    setUpdatesMessage();
                }
                if (data.packages) if (cb) cb(data.packages);
            }
        });
    }

    function setUpdatesMessage()
    {
        if (UPDATES_DONE === updates_status){
            if (available_updates){
                $updates_message.text(" ");
            } else {
                $updates_message.text("No updates are available.");
            }
        }
        else {
            $updates_message.text("Updates in progress...");
        }
    }

    function showUpdateList(packages)
    {
        if (! packages.length) return;

        var $button = $('<button id="perform_updates">Perform updates</button>'),
            $list = $('<ul id="updates">'),
            items = [],
            item
        ;
        for (var i=-1, l=packages.length, package; ++i < l;)
        {
            package = packages[i];
            item = [
                '<li class="package">',
                    '<span class="package-version">', package.version, '</span>',
                    '<span class="package-name">', package.name, '</span>',
                '</li>'
            ].join('');

            items.push(item)
        };

        $list.append(items.join(''));
        $updates_section.append($list);
        if (UPDATES_DONE === updates_status)
            $updates_section.append($button.bind('click', performUpdates));
        $updates_section.show();
        
    }
    
    function performUpdates(e)
    {
        $.ajax({
            type: 'get',
            dataType: 'html',
            url: urls.perform_updates,
            success: function (data)
            {
                //polling = setInterval(updatesProgress, polling_interval);
                document.location.reload();
            }
        });

    }

    function updatesProgress()
    {
        $.ajax({
            type: 'get',
            dataType: 'json',
            url: urls.update_status,
            success: function (data)
            {
                if (UPDATES_DONE === data.status){
                    getLogs();
                }
            }
        });
    }

    function getLogs()
    {
        $.ajax({
            type: 'get',
            dataType: 'json',
            url: urls.list_logs,
            success: function (data)
            {
                showLogList(data);
            }
        });
    }

    function showLogList(logs)
    {
        var $list = $('<ul id="logs">'),
            items = [],
            item;

        // sort newest first
        logs.sort(function (a,b){ return (a > b) ? -1 : 1; })

        for (var i=-1, l=logs.length, log; ++i < l;)
        {
            log = logs[i];
            var id = 'show_' + extractLogNum( log );
            item = [
                '<li class="log">',
                    '<span id="', id, '" class="action">', log, '</span>',
                '</li>'
            ].join('');
            items.push(item);
        };

        $list.append(items.join(''));
        $logs_section.append($list).show();
        $list.find('li').bind('click', function (e)
	{
		var $target = $(e.target),
        el = $target.is('.action') ? $target.get(0) : $target.children('.action').get(0),
        num  = extractLogNum( el.id ),
		log  = num +'.log',
		id   = 'log_'+ num,
		$out = $('#'+id);
		
		$(this).toggleClass("active");

         e.preventDefault();
	    $out.length ? $out.toggle() : getLog(log);
        });
    }

    function getLog(log)
    {
	var id = 'log_' + extractLogNum(log);
        var $p = $('#show_' + extractLogNum(log)).parent();
        $.ajax({
            type: 'get',
            dataType: 'text',
            url: urls.get_log,
            data: {log: log},
            success: function (log_text)
            {
                $p
                    .after('<pre id="'+ id +'">'+ log_text +'</pre>');
                    
            }
        });
    }

    function extractLogNum( val )
    {
        var matches = val.match(/(\d+)/);
        if ( matches == null ) matches = [ "", "1" ];
        return parseInt( matches[1], 10 );
    }
});
        </script>
    </body>
</html>]=])
