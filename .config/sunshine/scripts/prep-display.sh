#!/bin/bash
# Prep display script - runs BEFORE Sunshine encoder init
# Ensures DP-3 (virtual display) is enabled and available for capture

export XDG_RUNTIME_DIR=/run/user/1000
export WAYLAND_DISPLAY=wayland-0

LOG_FILE="$HOME/.config/sunshine/scripts/stream.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') [PREP] Ensuring DP-3 is enabled" >> "$LOG_FILE"

# Enable DP-3 if not already enabled
kscreen-doctor output.DP-3.enable output.DP-3.mode.2560x1440@120 2>> "$LOG_FILE"

# Brief pause to let KMS update
sleep 0.5

echo "$(date '+%Y-%m-%d %H:%M:%S') [PREP] Display prep complete" >> "$LOG_FILE"
