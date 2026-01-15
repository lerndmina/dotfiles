#!/bin/bash
# Prep display script - runs BEFORE Sunshine encoder init
# Ensures DP-3 (virtual display) is enabled and available for capture

export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-0

LOG_FILE="$HOME/.config/sunshine/scripts/stream.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [PREP] $1" >> "$LOG_FILE"
}

log "Ensuring DP-3 is enabled for capture"

# Log current state
log "Current display state:"
kscreen-doctor -o 2>&1 | grep -E "^Output:|enabled|disabled|connected|disconnected" >> "$LOG_FILE"

# Enable DP-3 - position will be set properly by on-stream-start.sh
kscreen-doctor output.DP-3.enable output.DP-3.mode.2560x1440@120 2>> "$LOG_FILE"

# Brief pause to let KMS update
sleep 0.5

log "Display prep complete"
