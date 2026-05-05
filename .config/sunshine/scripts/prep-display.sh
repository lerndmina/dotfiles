#!/bin/bash
# Prep display script - runs BEFORE Sunshine encoder init
# Ensures DP-3 (virtual display) is enabled and active for KMS capture

export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-0
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"

LOG_FILE="$HOME/.config/sunshine/scripts/stream.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [PREP] $1" >> "$LOG_FILE"
}

log "Waking displays and ensuring DP-3 is enabled for capture"

# Log current DRM state
log "DRM state before wake:"
for d in /sys/class/drm/card1-*/; do
    name=$(basename "$d")
    st=$(cat "$d/status" 2>/dev/null)
    en=$(cat "$d/enabled" 2>/dev/null)
    log "  $name: status=$st enabled=$en"
done

# Wake all displays from DPMS sleep
kscreen-doctor dpms.on 2>> "$LOG_FILE"
sleep 0.3

# Force enable DP-3 specifically
kscreen-doctor output.DP-3.enable output.DP-3.mode.2560x1440@120 2>> "$LOG_FILE"
sleep 0.3

# Also enable a physical monitor to ensure KMS has an active CRTC
# This helps wake the GPU from power saving
kscreen-doctor output.HDMI-A-2.enable 2>> "$LOG_FILE"
sleep 0.3

# Log DRM state after wake
log "DRM state after wake:"
for d in /sys/class/drm/card1-*/; do
    name=$(basename "$d")
    st=$(cat "$d/status" 2>/dev/null)
    en=$(cat "$d/enabled" 2>/dev/null)
    log "  $name: status=$st enabled=$en"
done

# Keep trying to wake DP-3 for up to 3 seconds
for i in {1..6}; do
    if [[ "$(cat /sys/class/drm/card1-DP-3/enabled 2>/dev/null)" == "enabled" ]]; then
        log "DP-3 is now enabled at DRM level"
        break
    fi
    log "Attempt $i: DP-3 still disabled, retrying..."
    kscreen-doctor output.DP-3.enable 2>> "$LOG_FILE"
    sleep 0.5
done

log "Display prep complete"
