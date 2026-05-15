#!/usr/bin/env bash
# Steam launch wrapper for PlanetSide 2 + Recursion Stat Tracker.
#
# Strategy: launch PS2 normally; in parallel, wait for PS2's wineserver
# to come up, then launch RTST.exe inside the *same* Proton container
# (same wine version, same prefix, same Steam Linux Runtime). They share
# a wineserver, which is required for RTST's D3D overlay to hook PS2.
#
# Set as PS2 launch option:
#   /home/wild/bin/ps2-with-rtst.sh %command%

LOG=/tmp/rtst-launch.log
ENTRY="$HOME/.local/share/Steam/steamapps/common/SteamLinuxRuntime_4/_v2-entry-point"
PROTON="/usr/share/steam/compatibilitytools.d/proton-cachyos-slr/proton"
RTST_WIN='C:\Program Files (x86)\Recursion\RecursionTracker\RTST.exe'

(
    # Wait for PS2's launcher / game to be running so wineserver exists.
    for _ in $(seq 1 120); do
        if pgrep -fi 'LaunchPad\.exe|PlanetSide2\.exe' >/dev/null; then
            break
        fi
        sleep 1
    done
    # Give wine a moment to fully initialise the prefix.
    sleep 6

    # Skip if RTST already running (e.g. relaunch within same session).
    if pgrep -fi 'RTST\.exe' >/dev/null; then
        echo "RTST already running, skipping" >&2
        exit 0
    fi

    export STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata/218230"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam"

    exec "$ENTRY" --verb=run -- "$PROTON" run "$RTST_WIN"
) >>"$LOG" 2>&1 &
disown

exec "$@"
