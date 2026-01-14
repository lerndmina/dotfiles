#!/bin/bash
# Sunshine stream stop script
# Re-enables physical monitors and disables virtual display

LOG_FILE="$HOME/.config/sunshine/scripts/stream.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [STOP] $1" >> "$LOG_FILE"
}

log "Stream stopped - restoring physical displays"

# Disable virtual and enable physical monitors in one atomic operation
kscreen-doctor output.DP-3.disable output.HDMI-A-2.enable output.DP-2.enable output.DP-4.enable 2>> "$LOG_FILE"

# Set modes and positions
sleep 0.3
kscreen-doctor output.DP-4.mode.1920x1080@60 output.DP-4.position.0,700 \
               output.DP-2.mode.2560x1440@240 output.DP-2.position.1920,192 \
               output.HDMI-A-2.mode.2560x1440@120 output.HDMI-A-2.position.4480,0 2>> "$LOG_FILE"

log "Restored physical displays"
