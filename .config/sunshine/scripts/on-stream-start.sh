#!/bin/bash
# Sunshine stream start script
# Disables physical monitors and enables virtual display

export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-0

LOG_FILE="$HOME/.config/sunshine/scripts/stream.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [START] $1" >> "$LOG_FILE"
}

log "Stream started - switching to virtual display"

# Disable physical monitors (DP-3 stays enabled at position 0,340)
kscreen-doctor output.HDMI-A-2.disable output.DP-2.disable output.DP-4.disable output.DP-3.mode.2560x1440@120 output.DP-3.position.0,340 2>> "$LOG_FILE"

log "Switched to virtual display DP-3"
