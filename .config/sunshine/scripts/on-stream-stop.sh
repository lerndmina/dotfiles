#!/bin/bash
# Sunshine stream stop script
# Re-enables physical monitors when streaming ends

export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-0

LOG_FILE="$HOME/.config/sunshine/scripts/stream.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [STOP] $1" >> "$LOG_FILE"
}

log "Stream stopped - restoring physical displays"

# Check which physical monitors are actually connected at DRM level
is_connected() {
    local connector="$1"
    local status_file="/sys/class/drm/card1-${connector}/status"
    [[ -f "$status_file" ]] && [[ "$(cat "$status_file")" == "connected" ]]
}

# Log current state
log "Current display state:"
kscreen-doctor -o 2>&1 | grep -E "^Output:|enabled|disabled|connected|disconnected" >> "$LOG_FILE"

# Build enable commands only for physically connected monitors
ENABLE_CMDS=""
POSITION_CMDS=""

if is_connected "DP-4"; then
    log "DP-4 is connected - will enable"
    ENABLE_CMDS="$ENABLE_CMDS output.DP-4.enable"
    POSITION_CMDS="$POSITION_CMDS output.DP-4.mode.1920x1080@60 output.DP-4.position.2560,700"
else
    log "DP-4 is disconnected - skipping"
fi

if is_connected "DP-2"; then
    log "DP-2 is connected - will enable"
    ENABLE_CMDS="$ENABLE_CMDS output.DP-2.enable"
    POSITION_CMDS="$POSITION_CMDS output.DP-2.mode.2560x1440@240 output.DP-2.position.4480,192 output.DP-2.priority.1"
else
    log "DP-2 is disconnected - skipping"
fi

if is_connected "HDMI-A-2"; then
    log "HDMI-A-2 is connected - will enable"
    ENABLE_CMDS="$ENABLE_CMDS output.HDMI-A-2.enable"
    POSITION_CMDS="$POSITION_CMDS output.HDMI-A-2.mode.2560x1440@120 output.HDMI-A-2.position.7040,0"
else
    log "HDMI-A-2 is disconnected - skipping"
fi

# Enable connected monitors
if [[ -n "$ENABLE_CMDS" ]]; then
    log "Enabling monitors: $ENABLE_CMDS"
    kscreen-doctor $ENABLE_CMDS 2>> "$LOG_FILE"
    sleep 0.3
fi

# Set positions for enabled monitors, keep DP-3 at far left
log "Setting positions"
kscreen-doctor output.DP-3.position.0,340 $POSITION_CMDS 2>> "$LOG_FILE"

log "Restored physical displays"
