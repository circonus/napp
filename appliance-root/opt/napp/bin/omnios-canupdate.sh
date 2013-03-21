#!/bin/bash

NEW_VER=""

if [ -r /opt/napp/etc/napp.override ]; then
	. /opt/napp/etc/napp.override
fi

NEW_VER=$(/usr/bin/pkg update -nv napp-incorporation 2>/dev/null | ggrep -A1 napp-incorporation | tail -1 | awk '{ print $3 }')

if [ -z "$NEW_VER" ]; then
	echo "No updates."
	exit 1
fi

echo "napp-incorporation $NEW_VER circonus"
exit 0
