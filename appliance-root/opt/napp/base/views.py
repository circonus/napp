from django.contrib.auth.decorators import login_required
from django.contrib.auth.models import User
from django.contrib.auth import login, authenticate
from django.template import Context, loader
from django.http import HttpResponse, HttpResponseRedirect
from napp.base.Appliance import Settings, UserCreateForm, ProvisionForm
from napp.base.Circonus import API
from django.shortcuts import render_to_response
from django.utils import simplejson as json

def index(request):
    s = Settings()
    if s.has_accounts == False:
        return HttpResponseRedirect('/initial')
    elif request.user.is_authenticated == False:
        return HttpResponseRedirect('/login')
    return HttpResponseRedirect('/dash')

def initial(request):
    def errorHandle(error):
        form = UserCreateForm()
        return render_to_response('base/initial.html', {
                'error' : error,
                'form' : form,
        })
    if request.method == 'POST':
        form = UserCreateForm(request.POST)
        if form.is_valid():
            username = request.POST['username']
            password = request.POST['password']
            password_again = request.POST['password_again']
            if password != password_again:
                return errorHandle(u'Passwords do not match')

            user = User.objects.create_user(username, 'none@nomx.circonus.com', password)
            user.save()
            user = authenticate(username=username, password=password)
            login(request, user)
            return HttpResponseRedirect('/dash')
    else:
        form = UserCreateForm()
    return render_to_response('base/initial.html', {
        'form': form,
    })

@login_required
def genkey(request):
    s = Settings()
    if s.has_keys:
        return HttpResponseRedirect('/dash')
    if s.make_keys():
        return HttpResponseRedirect('/dash')

@login_required
def provision(request):
    s = Settings()
    if s.has_cert:
        return HttpResponseRedirect('/dash')

    if s.has_csr and not s.has_cert:
        if s.fetch_cert():
            return HttpResponseRedirect('/dash')
        return render_to_response('base/wait_provisioning.html')

    if request.method == 'POST':
        form = ProvisionForm(request.POST)
    else:
        form = ProvisionForm()

    if form.is_valid():
        subj = '/C=' + request.POST['country_code'] + '/ST=' + request.POST['state_prov'] + '/O=' + request.POST['account_name'] + '/CN=' + request.POST['cn']
        error = 'unknown failure'
        try:
            if s.make_csr(subj, request.POST):
                return HttpResponseRedirect('/dash')
        except Exception, inst:
            error = '%s' % inst
        return render_to_response('base/error.html', {
            'error': error
        })
    return render_to_response('base/provision.html', {
        'form': form,
    })

@login_required
def dash(request):
    s = Settings()
    if not s.has_keys:
        return HttpResponseRedirect('/gen-key')
    if not s.has_csr or not s.has_cert:
        return HttpResponseRedirect('/provision')
    t = loader.get_template('base/dash.html')
    c = Context({
        'user' : request.user,
    })
    return HttpResponse(t.render(c))

@login_required
def list_accounts(request):
    s = API()
    try:
        L = s.list_accounts(request.POST['email'],
                            request.POST['password'])
        status = L[0]
        content = L[1]
    except:
        status = 500
        content = '{error: "unknown error"}'
    r = HttpResponse(content, content_type='text/javascript',
                     status = status)
    return r

@login_required
def list_private_agents(request):
    s = API()
    try:
        L = s.list_private_agents(request.POST['email'],
                                  request.POST['password'],
                                  request.POST['account'])
        status = L[0]
        content = L[1]
    except:
        status = 500
        content = '{error: "unknown error"}'
    r = HttpResponse(content, content_type='text/javascript',
                     status = status)
    return r

@login_required
def perform_updates(request):
    s = Settings()
    s.perform_updates()
    return HttpResponseRedirect('/dash')

@login_required
def json_check_for_updates(request):
    s = Settings()
    pkgs = s.check_for_updates()
    return HttpResponse(json.dumps(pkgs), content_type='text/javascript')

@login_required
def json_update_logs(request):
    s = Settings()
    logs = s.update_logs()
    return HttpResponse(json.dumps(logs), content_type='text/javascript')

@login_required
def json_update_log_contents(request):
    s = Settings()
    contents = s.update_log_contents(request.GET['log'])
    return HttpResponse(contents, content_type='text/plain')
