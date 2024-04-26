#!/bin/bash
LOCKFILE="/tmp/screenshot.lock"

if [ -f $LOCKFILE ]; then
  rm $LOCKFILE
  paplay /usr/share/sounds/Oxygen-K3B-Finish-Success.ogg
else
  touch $LOCKFILE
  paplay /usr/share/sounds/Oxygen-K3B-Finish-Error.ogg
fi
