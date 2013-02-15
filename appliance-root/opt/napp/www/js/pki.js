jQuery(function ($) {
  function set_state() {
    $.ajax({
      url: "/api/json/provisioned_state",
      type: "GET",
      dataType: "json",
      success: function (data, status, request) {
        $('#pki-key-ready').removeClass().addClass(
          data.details.key.exists ? 'exists' : 'missing'
        );
        $('#pki-ca-ready').removeClass().addClass(
          data.details.ca.exists ? 'exists' : 'missing'
        );
        if(data.details.crl.file)
          $('#pki-crl-ready').removeClass().addClass(
            data.details.crl.exists ? 'exists' : 'missing'
          );
        else
          $('#pki-crl-ready').removeClass().addClass('na');
        if(data.pki) {
          /* Allowed to go on */
          $("#fetch").text("Reconfigure");
          $('#fetch').unbind("click");
          $('#fetch').bind("click", reconfigure);
          if(!data.provisioned) $('#provision-step').show();
          else $('#dash-step').show();
        } else {
          $('#fetch').unbind("click");
          $('#fetch').bind("click", step);
        }
      },
      error: function (request, status, error) {
        alert('Error checking broker state');
      }
    });
  }
  function reconfigure() {
    fetchkey();
    fetchCA('ca');
    fetchCA('crl');
    step();
  }
  function step() {
    $.ajax({
      url: "/api/json/provisioned_state",
      type: "GET",
      dataType: "json",
      success: function (data, status, request) {
        // step 1
        if(!data.details.key.exists) return fetchkey();
        else $('#pki-key-ready').removeClass().addClass('exists');
        // step 2
        if(!data.details.ca.exists) return fetchCA('ca');
        else $('#pki-ca-ready').removeClass().addClass('exists');
        // step 3 (optional)
        if(data.details.crl.file) {
          if(!data.details.crl.exists) return fetchCA('crl');
          else $('#pki-crl-ready').removeClass().addClass('exists');
        }
        else $('#pki-crl-ready').removeClass().addClass('na');
        if(data.pki) {
          /* Allowed to go on */
          $("#fetch").text("Reconfigure");
          if(!data.provisioned) $('#provision-step').show();
          else $('#dash-step').show();
        }
      },
      error: function(request, status, error) {
        alert('Could not fetch status of PKI on the broker.');
      }
    });
  }
  function fetchkey() {
    $('#pki-key-ready').removeClass().addClass('progress');
    $.ajax({
      url: "/api/json/keygen",
      type: "GET",
      dataType: "json",
      success: function (data,status,request) {
        if(data.status == "success") return step();
        $('#pki-key-ready').removeClass().addClass('missing');
        alert('Failed to generate new private key: ' + data.error);
      },
      error: function(request, status, error) {
        $('#pki-key-ready').removeClass().addClass('missing');
        alert('Failed to generate new private key');
      }
    });
  }
  function fetchCA(type) {
    var $status = $('#pki-'+type+'-ready')
    $status.removeClass().addClass('progress');
    $.ajax({
      url: "/api/json/cafetch?type=" + type,
      type: "POST",
      data: {
        pki_url: $('#pki_url').val(),
        type: type
      },
      dataType: "json",
      success: function (data,status,request) {
        if(data.status == "success") return step();
        $status.removeClass().addClass('missing');
        alert('Failed to fetch ' + type + ': ' + data.error);
      },
      error: function(request, status, error) {
        $status.removeClass().addClass('missing');
        alert('Failed to fetch ' + type);
      }
    });
  }
  
  var urls = $('#pki');
  if(document.location.hash == "#inside") {
    urls.show();
    set_state();
  }
  else {
    set_state();
    step();
  }
});
