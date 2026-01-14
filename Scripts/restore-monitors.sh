#!/bin/bash
# Emergency monitor restore script
# Bound to Win+0 for quick recovery

LOG_FILE="$HOME/.config/sunshine/scripts/emergency-restore.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') Emergency restore triggered" >> "$LOG_FILE"

# Disable virtual, enable all physical monitors
kscreen-doctor output.DP-3.disable output.HDMI-A-2.enable output.DP-2.enable output.DP-4.enable 2>> "$LOG_FILE"

sleep 0.3

# Set correct modes and positions
kscreen-doctor output.DP-4.mode.1920x1080@60 output.DP-4.position.0,700 \
               output.DP-2.mode.2560x1440@240 output.DP-2.position.1920,192 \
               output.HDMI-A-2.mode.2560x1440@120 output.HDMI-A-2.position.4480,0 2>> "$LOG_FILE"

echo "$(date '+%Y-%m-%d %H:%M:%S') Restore complete" >> "$LOG_FILE"
