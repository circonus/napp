#!/bin/sh

CURL=/opt/omni/bin/curl
test -x $CURL || CURL=/opt/local/bin/curl
test -x $CURL || CURL=curl
BASE=http://updates.circonus.com/joyent/5.11
UPDATES_AVAILABLE=0

handle_packages() {
	while [ -n "$*" ];
	do
		pkg=$1
		ver=$2
		file=$3
		shift 3
		cver=`pkginfo -l $pkg 2>&1 | awk '{if($1 == "VERSION:") { print $2;}}'`
		if [ "$ver" != "$cver" ]; then
			UPDATES_AVAILABLE=1
			if [ -n "$cver" ]; then
				echo "removing $pkg"
				yes | /usr/sbin/pkgrm $pkg
			fi
			if [ -n "$ver" ]; then
				echo "adding $pkg from $file"
				yes | /usr/sbin/pkgadd -d $BASE/$file all
			fi
		fi
	done
}

echo "Downloading package list."
handle_packages `$CURL -s $BASE/ea.pkgs`

if [ ! -r /opt/napp/etc/django-stuff/napp_stub.sqlite ]; then
	echo "initializing web interface"
	cp -p /opt/napp/etc/django-stuff/napp_stub.sqlite.factory \
		/opt/napp/etc/django-stuff/napp_stub.sqlite
fi
if [ "$UPDATES_AVAILABLE" = "0" ]; then
	echo "No updates."
else
	/usr/sbin/svcadm restart jezebel
	/usr/sbin/svcadm restart unbound
	/usr/sbin/svcadm restart noitd
	/usr/sbin/svcadm restart napp
fi
