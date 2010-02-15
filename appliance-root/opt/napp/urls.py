from django.conf.urls.defaults import *

# Uncomment the next two lines to enable the admin:
# from django.contrib import admin
# admin.autodiscover()

urlpatterns = patterns('',
    (r'^$', 'napp.base.views.index'),
    (r'^dash$', 'napp.base.views.dash'),
    (r'^login$', 'django.contrib.auth.views.login', {'template_name': 'base/login.html'}),
    (r'^logout$', 'django.contrib.auth.views.logout', {'next_page': '/login'}),
    (r'^initial$', 'napp.base.views.initial'),
    (r'^provision$', 'napp.base.views.provision'),
    (r'^perform-updates$', 'napp.base.views.perform_updates'),
    (r'^gen-key$', 'napp.base.views.genkey'),
    (r'^api/json/list_accounts$', 'napp.base.views.list_accounts'),
    (r'^api/json/list_private_agents$', 'napp.base.views.list_private_agents'),
    (r'^api/json/check_for_updates$', 'napp.base.views.json_check_for_updates'),

    # Uncomment the admin/doc line below and add 'django.contrib.admindocs' 
    # to INSTALLED_APPS to enable admin documentation:
    # (r'^admin/doc/', include('django.contrib.admindocs.urls')),

    # Uncomment the next line to enable the admin:
    # (r'^admin/', include(admin.site.urls)),
)
