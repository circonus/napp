import os, sys
sys.path.append('/opt')
sys.path.append('/opt/django/lib/python2.4/site-packages')

os.environ['DJANGO_SETTINGS_MODULE'] = 'napp.settings'

import django.core.handlers.wsgi

application = django.core.handlers.wsgi.WSGIHandler()
