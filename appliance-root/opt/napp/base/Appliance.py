from django.contrib.auth.models import User
from django import forms
import re
import os.path
import time
import subprocess
from M2Crypto import RSA, EVP
from napp.base.Circonus import API
from django.utils import simplejson as json

class Settings:
    ssl_path = '/opt/napp/etc/ssl'
    """Appliance Settings Class"""

    def __init__(self):
        self.has_accounts = User.objects.all().count() > 0
	self.has_keys = os.path.isfile(self.ssl_path + '/appliance.key')
        self.has_csr = os.path.isfile(self.ssl_path + '/appliance.csr')
        self.has_cert = os.path.isfile(self.ssl_path + '/appliance.crt')

    def make_keys(self):
        if self.has_keys:
            return True
        key = RSA.gen_key(1024, 65537)
	key.save_key(self.ssl_path + '/appliance.key', None)
        time.sleep(1) # file is zero size unless we put this in (TODO: remove)
	self.has_keys = os.path.isfile(self.ssl_path + '/appliance.key')
        return self.has_keys

    def make_csr(self, subj, form):
        if self.has_csr:
            return True
        f = open(self.ssl_path + '/ssl_subj.txt', 'w')
        f.write(subj)
        f.close()
        p = subprocess.Popen(['/usr/bin/openssl',
                              'req', '-key', self.ssl_path + '/appliance.key',
                              '-days', '365', '-new',
                              '-out', self.ssl_path + '/appliance.csr~',
                              '-config', '/opt/napp/etc/napp-openssl.cnf',
                              '-subj', subj ],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             close_fds=True)
        (outdata, outerr) = p.communicate()
        if not os.path.isfile(self.ssl_path + '/appliance.csr~'):
            raise Exception(outdata)
        csrFile = open(self.ssl_path + '/appliance.csr~')
        csr = csrFile.read()
        csrFile.close()
        api = API()
        L = api.submit_agent_csr(form['email'], form['password'],
                                 form['account'], csr)
        if L[0] == 200:
            os.rename(self.ssl_path + '/appliance.csr~',
                      self.ssl_path + '/appliance.csr')
        else:
            raise Exception('Remote server: %d\n%s' % (L[0], L[1]))
        self.has_csr = os.path.isfile(self.ssl_path + '/appliance.csr')
        return self.has_csr

    def current_noitd_state(self):
        return os.path.isfile('/opt/napp/etc/noit.run')

    def start_noitd(self):
        open('/opt/napp/etc/noit.run', 'w').close()

    def stop_noitd(self):
        if os.path.isfile('/opt/napp/etc/noit.run'):
            os.unlink('/opt/napp/etc/noit.run')

    def perform_updates(self):
        p = open("/opt/napp/etc/doupdates", "w")
        p.close()

    def check_for_updates(self):
        p = subprocess.Popen(['/opt/napp/etc/check-for-updates'],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             close_fds=True)
        (outdata, outerr) = p.communicate()
        lines = outdata.splitlines()
        pkgs = []
        if p.returncode == 0:
            for l in lines:
                parts = re.split('\s+', l)
                if len(parts) == 3:
                    pkgs.append({ 'name': parts[0],
                                  'version': parts[1],
                                  'source': parts[2]})
        status = 'idle'
        if os.path.isfile('/opt/napp/etc/doupdates'):
            status = 'requested'
        elif os.path.isfile('/opt/napp/etc/doingupdates'):
            status = 'processing'
        return { 'status': status, 'packages': pkgs }

    def update_logs(self):
        return os.listdir('/opt/napp/etc/updatelogs')

    def update_log_contents(self, file):
        if re.search('/', file):
            return ''
        f = open('/opt/napp/etc/updatelogs/' + file)
        rv = f.read()
        f.close()
        return rv

    def fetch_cert(self):
        f = open(self.ssl_path + '/ssl_subj.txt', 'r')
        subj = f.read()
        f.close()
        p = re.compile(r'/CN=(?P<subject>[^/]+)')
        m = p.search(subj)
        if m:
            api = API()
            cn = m.group('subject')
            L = api.get_agent_info(cn)
            if L[0] == 200:
                obj = json.loads(L[1])
                if obj['cert'] is not None and len(obj['cert']) > 0:
                    crt = open(self.ssl_path + '/appliance.crt', 'w')
                    crt.write(obj['cert'])
                    crt.close()
                    self.has_cert = True
            else:
                raise Exception('Internet Error: ' + subj)
        else:
            raise Exception('CSR Error: ' + subj)

class UserCreateForm(forms.Form):
    username = forms.CharField(max_length=30)
    password = forms.CharField(widget=forms.PasswordInput(render_value=False), max_length=30)
    password_again = forms.CharField(widget=forms.PasswordInput(render_value=False), max_length=30)

class ProvisionForm(forms.Form):
    email = forms.CharField(max_length=30)
    password = forms.CharField(widget=forms.PasswordInput(render_value=False),
                               max_length=30)
    account = forms.CharField(max_length=60)
    account_name = forms.CharField(max_length=60)
    country_code = forms.CharField(max_length=2)
    state_prov = forms.CharField(max_length=40)
    cn = forms.CharField(max_length=80)
