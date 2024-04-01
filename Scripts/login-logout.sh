#!/bin/bash
LOCKFILE=/tmp/login-logout.lock

if [ -f $LOCKFILE ]; then
  echo "Script already running"
  exit 0
fi

trap "rm -f $LOCKFILE" EXIT

touch $LOCKFILE

# Start the script

dbus-monitor --session "type='signal',interface='org.gnome.ScreenSaver'" |
  while read x; do
    case "$x" in
    *"boolean true"*) bash /home/wild/Scripts/stop-replay.sh ;;
    *"boolean false"*) bash /home/wild/Scripts/start-replay.sh ;;
    esac
  done
