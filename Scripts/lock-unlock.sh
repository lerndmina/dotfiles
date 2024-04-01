#!/bin/bash
LOCKFILE="/tmp/screenshot.lock"

if [ -f $LOCKFILE ]; then
  rm $LOCKFILE
  paplay /usr/share/sounds/gnome/default/alerts/sonar.ogg
else
  touch $LOCKFILE
  paplay /usr/share/sounds/gnome/default/alerts/glass.ogg
fi
