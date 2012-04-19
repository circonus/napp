#!/bin/sh

NO_UPDATES=0
if [ "$1" = "-n" ]; then
	NO_UPDATES=1
fi
CURL=/opt/omni/bin/curl
test -x $CURL || CURL=/opt/local/bin/curl
test -x $CURL || CURL=curl
BASE=http://updates.circonus.com/joyent/smartos
UPDATES_AVAILABLE=0
if [ -r /opt/napp/etc/napp.override ]; then
	. /opt/napp/etc/napp.override
fi

record_svc_state() {
	STATE=`/usr/bin/svcs -H -o state $1`
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
		echo "initializing web interface"
		cp -p /opt/napp/etc/django-stuff/napp_stub.sqlite.factory \
			/opt/napp/etc/django-stuff/napp_stub.sqlite
	fi
}

noit_init() {
	if [ ! -r /opt/noit/prod/etc/noit.conf ]; then
		echo "initializing noit"
		cp -p /opt/noit/prod/etc/noit.conf.factory \
			/opt/noit/prod/etc/noit.conf
	fi
}

handle_packages() {
	while [ -n "$*" ];
	do
		pkg=$1
		ver=$2
		file=$3
		shift 3
		cver=`pkg_info $pkg-\* 2>&1 | sed -e "s/$pkg-/:/" | awk -F: '/Information/ {print $2;}'`
		if [ "$ver" != "$cver" ]; then
			UPDATES_AVAILABLE=1
			if [ -n "$cver" ]; then
				echo "removing $pkg ($cver -> $ver)"
                                if [ "$NO_UPDATES" = "0" ]; then
					yes | /opt/local/sbin/pkg_delete -f $pkg-$cver
				fi
			fi
			if [ -n "$ver" ]; then
				echo "$pkg $ver circonus"
                                if [ "$NO_UPDATES" = "0" ]; then
					yes | /opt/local/sbin/pkg_add -f $BASE/$pkg.tgz
				fi
			else
				echo "$pkg (remove) circonus"
			fi
		fi
	done
}

if [ "$NO_UPDATES" = "0" ]; then
	record_svc_state jezebel
	record_svc_state unbound
	record_svc_state noitd
	record_svc_state napp
fi

handle_packages `$CURL -s $BASE/ea.pkgs`

if [ "$NO_UPDATES" = "0" ]; then
	web_init
	noit_init
fi

if [ "$UPDATES_AVAILABLE" = "0" ]; then
	echo "No updates."
elif [ "$NO_UPDATES" = "0" ]; then
	restore_svc_state jezebel
	restore_svc_state unbound
	restore_svc_state noitd
	restore_svc_state napp
fi
