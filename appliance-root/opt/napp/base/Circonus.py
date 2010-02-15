from M2Crypto.httpslib import HTTPSConnection
from httplib import HTTPConnection, HTTPSConnection as httpsclient
import httplib
import urllib
from urlparse import urlparse
from django.utils import simplejson

class Noit:
    def __init__(self, host='s.circonus.com'):
        # We have to use the httpsclient here as it supports client certs
        self.conn = httpsclient(host, port=43191,
                                cert_file='/opt/napp/etc/ssl/appliance.crt',
                                key_file='/opt/napp/etc/ssl/appliance.key')
        self.conn.connect()
    def get_config(self):
        self.conn.request("GET", '/noits/config', None)
        r = self.conn.getresponse()
        return (r.status, r.read())

class API:
    def __init__(self, base='https://circonus.com/api/json'):
        self.base = base
        o = urlparse(base)
        host = o[1].split(':')
        self.url = o[2]
        if o[0] == 'http':
            port = 80
            if len(host) > 1:
                port = host[1]
            self.conn = HTTPConnection(host[0], port=port)
        elif o[0] == 'https':
            port = 443
            if len(host) > 1:
                port = host[1]
            self.conn = HTTPSConnection(host[0], port=port)
        self.conn.connect()

    def get_agent_info(self,cn):
        params = urllib.urlencode({'cn': cn})
        url = "%s/agent?%s" % (self.url, params)
        self.conn.request("GET", url, None)
        r = self.conn.getresponse()
        return (r.status, r.read())

    def list_accounts(self,email,password):
        headers = { 'Content-type': 'application/x-www-form-urlencoded',
                    'Accept': 'text/plain' }
        params = urllib.urlencode({'email': email, 'password': password})
        url = "%s/list_accounts" % self.url
        self.conn.request("POST", url, params, headers)
        r = self.conn.getresponse()
        return (r.status, r.read())

    def list_private_agents(self,email,password,account,cn=None):
        headers = { 'Content-type': 'application/x-www-form-urlencoded',
                    'Accept': 'text/plain' }
        nparams = { 'email': email, 'password': password, 'account': account }
        if cn is not None:
            nparams['cn'] = cn
        params = urllib.urlencode(nparams)
        url = "%s/list_private_agents" % self.url
        self.conn.request("POST", url, params, headers)
        r = self.conn.getresponse()
        return (r.status, r.read())

    def submit_agent_csr(self,email,password,account,csr):
        headers = { 'Content-type': 'application/x-www-form-urlencoded',
                    'Accept': 'text/plain' }
        params = urllib.urlencode({'email': email, 'password': password,
                                   'account': account, 'csr': csr})
        url = "%s/submit_agent_csr" % self.url
        self.conn.request("POST", url, params, headers)
        r = self.conn.getresponse()
        return (r.status, r.read())
