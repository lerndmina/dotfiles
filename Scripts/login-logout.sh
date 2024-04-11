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
    *"boolean true"*) bash $HOME/Scripts/stop-replay.sh ;;
    *"boolean false"*) bash $HOME/Scripts/start-replay.sh ;;
    esac
  done
