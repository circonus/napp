#!/bin/sh

CURL=/opt/omni/bin/curl
test -x $CURL || CURL=/opt/local/bin/curl
test -x $CURL || CURL=curl
for i in /opt/omni/bin /opt/local/bin
do
	if [ -x "$i/curl" ]; then
		CURL="$i/curl"
		break
	fi
done
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
			fi
			if [ -n "$ver" ]; then
				echo "$pkg $ver circonus"
			else
				echo "$pkg (remove) circonus"
			fi
		fi
	done
}

handle_packages `$CURL -s $BASE/ea.pkgs`

if [ "$UPDATES_AVAILABLE" = "0" ]; then
	echo "No updates."
fi
