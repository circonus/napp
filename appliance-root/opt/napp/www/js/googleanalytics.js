jQuery(function ($)
{
    var $form          = $("#analytics_form"),
        $client_id     = $("#id_clientid"),
        $client_secret = $("#id_clientsecret"),
        $api_key       = $("#id_apikey");

    $form.bind("submit", submit);

    function submit(e)
    {
        $client_id.val($.trim($client_id.val()));
        $client_secret.val($.trim($client_secret.val()));
        $api_key.val($.trim($api_key.val()));
        if ($client_id.val().match(/\s|'/)) {
          alert ("Client ID cannot contain whitespace");
          return false;
        }
        if ($client_secret.val().match(/\s|'/)) {
          alert ("Client Secret cannot contain whitespace");
          return false;
        }
        if ($api_key.val().match(/\s|'/)) {
          alert ("API Key cannot contain whitespace");
          return false;
        }
        return true;
    }
});
