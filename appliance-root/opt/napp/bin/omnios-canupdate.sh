#!/bin/bash

UPDATES_AVAILABLE=0

if [ -r /opt/napp/etc/napp.override ]; then
	. /opt/napp/etc/napp.override
fi

/usr/bin/pkg update -nv napp-incorporation && UPDATES_AVAILABLE=1

if [ "$UPDATES_AVAILABLE" = "0" ]; then
	echo "No updates."
	exit 1
fi

exit 0
