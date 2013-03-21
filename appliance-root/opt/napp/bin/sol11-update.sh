#!/bin/sh

CURL=/opt/omni/bin/curl
test -x $CURL || CURL=/opt/local/bin/curl
test -x $CURL || CURL=curl
BASE=http://updates.circonus.com/joyent/5.11
UPDATES_AVAILABLE=0
if [ -r /opt/napp/etc/napp.override ]; then
	. /opt/napp/etc/napp.override
fi

bail() {
	echo "$@"
	exit 1
}

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

noit_init() {
	if [ ! -r /opt/noit/prod/etc/noit.conf ]; then
		echo "initializing noit"
		cp -p /opt/noit/prod/etc/noit.conf.factory \
			/opt/noit/prod/etc/noit.conf
	fi
}

handle_packages() {
	echo "Downloading package list."
	while [ -n "$*" ];
	do
		pkg=$1
		ver=$2
		file=$3
		shift 3
		cver=`pkginfo -l $pkg 2>&1 | awk '{if($1 == "VERSION:") { print $2;}}'`
		dldir=/var/tmp/circonus
		if [ "$ver" != "$cver" ]; then
			UPDATES_AVAILABLE=1
			if [ ! -d $dldir ]; then
				echo "preparing download directory"
				mkdir $dldir || \
					bail "failed to create download directory: $dldir"
			fi
			echo "downloading $BASE/$file"
			$CURL -s -o $dldir/$file $BASE/$file || \
				bail "Download failed.  Tried $BASE/$file"
			if [ -n "$cver" ]; then
				echo "removing $pkg"
				yes | /usr/sbin/pkgrm $pkg
			fi
			if [ -n "$ver" ]; then
				echo "adding $pkg from $file"
				yes | /usr/sbin/pkgadd -d $dldir/$file all
			fi
		fi
	done
	echo ""
	echo "Feel free to delete files in $dldir if you wish."
	echo ""
}

record_svc_state jezebel
record_svc_state unbound
record_svc_state noitd

pkglist=`$CURL -s $BASE/ea.pkgs`
if [ `echo $pkglist | awk '{ print substr($0,0,4)}'` != "OMNI" ]; then
	bail "Package list doesn't look right.  Fetched $BASE/ea.pkgs"
fi

handle_packages $pkglist

noit_init

if [ "$UPDATES_AVAILABLE" = "0" ]; then
	echo "No updates."
else
	restore_svc_state jezebel
	restore_svc_state unbound
	restore_svc_state noitd
fi
