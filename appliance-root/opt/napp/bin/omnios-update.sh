#!/bin/bash

CIRCONUS_REPO=http://pkg-internal.omniti.com/circonus-pilot/
OMNITI_REPO=http://pkg.omniti.com/omniti-ms/

if [ -r /opt/napp/etc/napp.override ]; then
	. /opt/napp/etc/napp.override
fi

bomb() {
    echo ""
    echo "======================================================"
    echo "$*"
    echo "======================================================"
    exit 1
}

configure_publishers() {
    /usr/bin/pkg publisher ms.omniti.com > /dev/null 2>&1 || \
        /usr/bin/pkg set-publisher -g $OMNITI_REPO ms.omniti.com || \
        bomb "Error: setting publisher ms.omniti.com failed"
    /usr/bin/pkg publisher circonus > /dev/null 2>&1 || \
        /usr/bin/pkg set-publisher -g $CIRCONUS_REPO circonus || \
        bomb "Error: setting publisher circonus failed"
}

record_svc_state() {
	STATE=`/usr/bin/svcs -H -o state $1 2> /dev/null`
	if [ "$STATE" != "online" ]; then
		STATE=offline
	fi
	eval "svc_state_$1=$STATE"
}

restore_svc_state() {
	NEWSTATE=`/usr/bin/svcs -H -o state $1`
	STATE=`eval echo "\\\$svc_state_$1"`
	if [ "$STATE" = "online" ]; then
		if [ "$NEWSTATE" = "online" ]; then
			echo "svcadm restart $1 ($NEWSTATE -> $STATE)"
			/usr/sbin/svcadm restart $1
		elif [ "$NEWSTATE" = "maintenance" ]; then
			echo "svcadm clear $1 ($NEWSTATE -> $STATE)"
			/usr/sbin/svcadm clear $1
		else
			echo "svcadm enable $1 ($NEWSTATE -> $STATE)"
			/usr/sbin/svcadm enable $1
		fi
	fi
}

web_init() {
	if [ ! -r /opt/napp/etc/django-stuff/napp_stub.sqlite ]; then
		echo "Initializing web interface"
		cp -p /opt/napp/etc/django-stuff/napp_stub.sqlite.factory \
			/opt/napp/etc/django-stuff/napp_stub.sqlite
	fi
}

noit_init() {
	if [ ! -r /opt/noit/prod/etc/noit.conf ]; then
		echo "Initializing noit"
		cp -p /opt/noit/prod/etc/noit.conf.factory \
			/opt/noit/prod/etc/noit.conf
	fi
}

configure_publishers
record_svc_state jezebel
record_svc_state unbound
record_svc_state noitd
record_svc_state napp

/usr/bin/pkg install napp-incorporation || bomb "Error: pkg installation failed"

web_init
noit_init

restore_svc_state jezebel
restore_svc_state unbound
restore_svc_state noitd
restore_svc_state napp
