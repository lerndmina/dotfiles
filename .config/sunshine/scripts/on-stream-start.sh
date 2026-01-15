#!/bin/bash
# Sunshine stream start script
# Disables physical monitors and sets up virtual display for streaming

export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-0

LOG_FILE="$HOME/.config/sunshine/scripts/stream.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [START] $1" >> "$LOG_FILE"
}

log "Stream started - switching to virtual display"

# Get list of currently enabled physical monitors (exclude DP-3)
# Strips ANSI codes and finds enabled outputs
get_enabled_physical_monitors() {
    kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '
        /^Output:/ { output = $3; enabled = 0; connected = 0 }
        /^\s*enabled$/ { enabled = 1 }
        /^\s*connected$/ { connected = 1 }
        /^\s*priority/ { 
            if (enabled && connected && output != "DP-3") print output 
        }
    '
}

# Log current state
log "Current display state:"
kscreen-doctor -o 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "^Output:|^\s+enabled|^\s+disabled|^\s+connected|^\s+disconnected" >> "$LOG_FILE"

# Disable all enabled physical monitors (not DP-3)
MONITORS_TO_DISABLE=$(get_enabled_physical_monitors)
if [[ -n "$MONITORS_TO_DISABLE" ]]; then
    log "Disabling physical monitors: $(echo $MONITORS_TO_DISABLE | tr '\n' ' ')"
    DISABLE_ARGS=""
    for mon in $MONITORS_TO_DISABLE; do
        DISABLE_ARGS="$DISABLE_ARGS output.$mon.disable"
    done
    kscreen-doctor $DISABLE_ARGS 2>> "$LOG_FILE"
else
    log "No physical monitors to disable"
fi

# Ensure DP-3 is enabled, at position 0,0, and set as primary
sleep 0.3
log "Configuring DP-3 as sole display at 0,0"
kscreen-doctor output.DP-3.enable \
               output.DP-3.mode.2560x1440@120 \
               output.DP-3.position.0,0 \
               output.DP-3.priority.1 2>> "$LOG_FILE"

log "Switched to virtual display DP-3"
