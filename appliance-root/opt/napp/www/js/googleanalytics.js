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
        return true;
    }
});
