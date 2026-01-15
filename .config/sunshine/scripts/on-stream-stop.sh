#!/bin/bash
# Sunshine stream stop script
# Re-enables physical monitors and disables virtual display

export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-0

LOG_FILE="$HOME/.config/sunshine/scripts/stream.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [STOP] $1" >> "$LOG_FILE"
}

log "Stream stopped - restoring physical displays"

# Enable physical monitors (keep DP-3 enabled so Sunshine can reconnect after idle)
kscreen-doctor output.HDMI-A-2.enable output.DP-2.enable output.DP-4.enable 2>> "$LOG_FILE"

# Set modes and positions (DP-3 stays at far left: 0,340)
sleep 0.3
kscreen-doctor output.DP-3.position.0,340 \
               output.DP-4.mode.1920x1080@60 output.DP-4.position.2560,700 \
               output.DP-2.mode.2560x1440@240 output.DP-2.position.4480,192 \
               output.HDMI-A-2.mode.2560x1440@120 output.HDMI-A-2.position.7040,0 2>> "$LOG_FILE"

log "Restored physical displays"
