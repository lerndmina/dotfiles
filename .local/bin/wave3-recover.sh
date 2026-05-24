#!/bin/bash
# Auto-recover Elgato Wave 3 after its hardware mute button breaks the PCM stream.
#
# Detection: watch the PipeWire journal for the ENODEV error that fires when the
# Wave 3's USB audio alt-setting flips to 0 (hardware mute). Restarting WirePlumber
# re-probes the device and restores it; PipeWire (audio output) is left untouched.
#
# CRITICAL LOOP HAZARD: restarting WirePlumber itself re-probes the still-muted
# Wave 3 and re-emits the SAME ENODEV error. Without guards this becomes an
# infinite restart storm that takes down the whole audio stack (May 2026 incident).
# Three things keep it safe:
#   1. `-n 0` on journalctl -f  -> never replay old log lines on (re)start.
#   2. DEBOUNCE window          -> swallow the ENODEV echo from our own re-probe.
#   3. circuit breaker          -> back off if restarts pile up despite the above.
# The unit must also NOT be PartOf=wireplumber.service (see the .service file).

DEBOUNCE=15            # seconds to ignore further triggers after a restart
BREAKER_WINDOW=60      # if more than BREAKER_MAX restarts happen within this many
BREAKER_MAX=3          #   seconds, something is wrong: back off instead of looping
BREAKER_BACKOFF=60

SOURCE_NAME="alsa_input.usb-Elgato_Systems_Elgato_Wave_3_BS01K1A02804-00.mono-fallback"

LAST_RESTART=0
recent=()              # timestamps of recent restarts, for the circuit breaker

# -n 0: emit zero historical lines, only follow NEW errors. This is what stops the
# script from re-triggering on stale ENODEV lines every time it (re)starts.
journalctl --user -u pipewire -f -n 0 --no-pager -o cat 2>/dev/null \
  | grep --line-buffered -E "hw:4.*: No such device" \
  | while read -r _; do
    now=$(date +%s)

    # Debounce: swallow the ENODEV echo produced by our own wireplumber re-probe.
    (( now - LAST_RESTART < DEBOUNCE )) && continue

    # Circuit breaker: keep only restarts inside the window, then count them.
    pruned=()
    for t in "${recent[@]}"; do (( now - t < BREAKER_WINDOW )) && pruned+=("$t"); done
    recent=("${pruned[@]}")
    if (( ${#recent[@]} >= BREAKER_MAX )); then
        echo "wave3-recover: ${#recent[@]} restarts in ${BREAKER_WINDOW}s, backing off ${BREAKER_BACKOFF}s" >&2
        sleep "$BREAKER_BACKOFF"
        recent=()
        LAST_RESTART=$(date +%s)
        continue
    fi

    LAST_RESTART=$now
    recent+=("$now")

    mute_state=$(pactl get-source-mute "$SOURCE_NAME" 2>/dev/null | awk '{print $2}')

    sleep 2
    systemctl --user restart wireplumber
    sleep 1

    if [[ "$mute_state" == "yes" ]]; then
        pactl set-source-mute "$SOURCE_NAME" 1 2>/dev/null
    fi
done
