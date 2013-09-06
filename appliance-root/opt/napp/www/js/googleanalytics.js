jQuery(function ($)
{
    var $form          = $("#analytics_form"),
        $client_id     = $("#id_clientid"),
        $client_secret = $("#id_clientsecret"),
        $api_key       = $("#id_apikey");

    $form.bind("submit", submit);

    function submit(e)
    {
        var err = "";
        $client_id.val($.trim($client_id.val()));
        $client_secret.val($.trim($client_secret.val()));
        $api_key.val($.trim($api_key.val()));
        if ($client_id.val().match(/\s|'/)) {
          err = err.concat("Client ID cannot contain whitespace\n");
        }
        if ($client_secret.val().match(/\s|'/)) {
          err = err.concat("Client Secret cannot contain whitespace\n");
        }
        if ($api_key.val().match(/\s|'/)) {
          err = err.concat("API Key cannot contain whitespace\n");
        }
        if (err !== "") {
          alert ("Form submission failed for the following reasons:\n" + err);
          return false;
        }
        return true;
    }
});
