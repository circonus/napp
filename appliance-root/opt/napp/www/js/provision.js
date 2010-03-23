jQuery(function ($)
{
    var $form    = $("#login_form"),
        $login   = $('#login'),
        $email   = $("#login_email"),
        $pass    = $("#login_password"),
        $submit  = $form.find("[type=submit]").hide(),
        $step1   = $("#step_1"),
        $step2   = $("#step_2"),
        $account = $step2.find("[name=account]");
        $step3   = $("#step_3"),
        accounts = {};

    $form.bind("submit", step1);
    $login.bind("click", step1);

    function step1(e)
    {
        e.preventDefault(); // stop submission
        $step2.hide();
        $step3.hide();

        // make XHR call
        $.ajax({
            url: "/api/json/list_accounts",
            type: "POST",
            data: { 
                email: $email.val(), 
                password: $pass.val() 
            },
            dataType: "json",
            success: function (data, status, request)
            {
                // create / draw select box
                $account
                    .empty()
                    .unbind('change')
                    .bind('change', step2);

                // put an empty account as the first choice
                var accts = [{account: '', account_name: ''}].concat(data);

                $.each(accts, function (i, acct)
                {
                    var name = acct.account_name ? acct.account_name : 'Choose an account',
                        desc = acct.account ? " ("+ acct.account +")" : "",
                        text = name + desc,
                        $opt = $("<option>").attr({
                            value: acct.account,
                            text: text
                        });

                    // store by id to access later
                    if (acct.account_name) accounts[acct.account] = acct;

                    $account.append($opt); 
                });

                $step2.show();

            },
            error: function (request, status, error)
            {
                alert('Could not log you in');
            }
        });
    }

    function step2(e)
    {
        e.preventDefault();
        $list = $('#avail-agents').hide();
        var account = $account.val();
        if (! account) return;

        // get radios
        $.ajax({ 
            url: "/api/json/list_private_agents",
            type: "POST",
            dataType: "json",
            data: {
                email: $email.val(), 
                password: $pass.val(), 
                account: $account.val()
            },
            success: function (data, status, request)
            {
                var $no_agents_test = $('#no-available-agents').hide(),
                    $no_agents_msg  = 
                        // if we have it, use it
                        ($no_agents_test.length && $no_agents_test)
                        // else create, add and hide
                        || $('<p id="no-available-agents">Sorry, there are no available Enterprise Agents for this account.  Please select another account or <a href="#">add a new Enterprise Agent</a> to this account.</p>').hide();

                $list.empty().after($no_agents_msg);
                $.each(data, function (i, agent)
                {
                    var input_id = "agent_" + agent.agent_name.replace(/\W+/g, "_"),
                        $item = $("<li>").addClass(agent.status),
                        $label = $("<label>")
                            .attr({"for": input_id})
                            .html('<em>'+agent.agent_name +'</em> ('+ agent.cn +') <span><em>'+ agent.status +'</em></span>' ),
                        $radio = $("<input>")
                            .attr({
                                type: "radio",
                                name: "cn",
                                id: input_id,
                                value: agent.cn,
                                disabled: (agent.status !== "unprovisioned")
                            });

                    $list.append(
                        $item
                            .append($radio)
                            .append($label)
                    )
                    .show();
                });

                $list.bind('change', function (e)
                { 
                    $form
                        .unbind('submit')
                        .bind('submit', step3);

                    $submit.show(); 
                });

                $step3.show();

                if (! data.length){ $no_agents_msg.show(); }

            },
            error: function (request, status, error)
            {
                alert("There was an error retrieving the agents");
            }
        });
     
    }
    
    function step3(e)
    {
        var id = $account.val(),
            hidden_vals = ["country_code", "state_prov", "account_name"];

        $.each(hidden_vals, function (i, hide)
        {
            var $hidden = $("<input>")
                    .attr({
                        type: "hidden",
                        name: hide,
                        value: accounts[id][hide] 
                            ? accounts[id][hide] 
                            : '??'
                    });
    
            $form.append($hidden);
        });

    }

});

