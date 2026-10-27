#!/bin/bash

SCRIPT_START_TIME=$(date +%s.%N)

source "$HOME/Scripts/setup.sh"
source "$HOME/Scripts/zipline.sh"

MODE="screenshot"
AUDIO_ENABLED=false
while [ $# -gt 0 ]; do
  case "$1" in
    --record|-r|record)
      MODE="record"
      ;;
    --audio|-a|audio)
      AUDIO_ENABLED=true
      ;;
  esac
  shift
done

CAPTURE_FILE=""
SCREENSHOT_FROM_CLIPBOARD=false
LAST_UPLOAD_STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/screenshot-last-upload"
LAST_UPLOADED_HASH=""
LAST_UPLOADED_URL=""
CAPTURE_HASH=""
SKIPPED_DUPLICATE_UPLOAD=false

cleanup() {
  if [ -n "$TEMP_CHUNK_DIR" ] && [ -d "$TEMP_CHUNK_DIR" ]; then
    rm -rf "$TEMP_CHUNK_DIR"
  fi

  if ! $UNABLE; then
    rm -f "$LOCKFILE"
  fi

  SCRIPT_END_TIME=$(date +%s.%N)
  SCRIPT_RUNTIME=$(echo "$SCRIPT_END_TIME - $SCRIPT_START_TIME" | bc)
  SCRIPT_RUNTIME_MS=$(echo "$SCRIPT_RUNTIME * 1000" | bc | cut -d'.' -f1)
  echo "Total script runtime: ${SCRIPT_RUNTIME_MS}ms"
}

trap cleanup EXIT

if $UNABLE; then
  paplay /usr/share/sounds/sound-icons/hash 2>/dev/null || echo "Error: Could not play sound"
  echo "The script is already running or has been locked, exiting..."
  exit 1
fi

hash_file() {
  sha1sum "$1" | cut -d' ' -f1
}

load_last_upload_state() {
  [ -f "$LAST_UPLOAD_STATE_FILE" ] || return 0

  {
    IFS= read -r LAST_UPLOADED_HASH || true
    IFS= read -r LAST_UPLOADED_URL || true
  } < "$LAST_UPLOAD_STATE_FILE"
}

save_last_upload_state() {
  [ -n "$CAPTURE_HASH" ] || return 0
  [ -n "$UPLOADED_URL" ] || return 0

  printf '%s\n%s\n' "$CAPTURE_HASH" "$UPLOADED_URL" > "$LAST_UPLOAD_STATE_FILE"
}

should_skip_duplicate_clipboard_upload() {
  [ "$MODE" = "screenshot" ] || return 1
  $SCREENSHOT_FROM_CLIPBOARD || return 1
  [ -n "$CAPTURE_HASH" ] || return 1
  [ -n "$LAST_UPLOADED_HASH" ] || return 1
  [ -n "$LAST_UPLOADED_URL" ] || return 1
  [ "$CAPTURE_HASH" = "$LAST_UPLOADED_HASH" ]
}

take_screenshot() {
  case "$SCREENSHOT_TOOL" in
    flameshot)
      if [ "$XDG_SESSION_TYPE" = "wayland" ] || [ -n "$WAYLAND_DISPLAY" ]; then
        echo "Wayland detected, running flameshot with XCB platform"
        QT_QPA_PLATFORM=xcb flameshot gui -p "$CAPTURE_FILE"
      else
        flameshot gui -p "$CAPTURE_FILE"
      fi
      ;;
    grim)
      local geometry
      geometry=$(slurp) || return 1
      grim -g "$geometry" "$CAPTURE_FILE"
      ;;
    spectacle)
      spectacle -r -n -b -i -o "$CAPTURE_FILE"
      if [ ! -s "$CAPTURE_FILE" ]; then
        echo "No output file from spectacle, checking clipboard for image..."
        if wl-paste --list-types 2>/dev/null | grep -q "image/png"; then
          wl-paste --type image/png > "$CAPTURE_FILE"
          SCREENSHOT_FROM_CLIPBOARD=true
        fi
      fi
      ;;
    *)
      echo "Error: Unknown screenshot tool '$SCREENSHOT_TOOL' (set in Scripts/setup.sh)"
      return 1
      ;;
  esac
}

# Audio sources mixed onto a single track, used only when --audio is passed.
# gsr merges devices joined by '|'. "default_output" = system audio,
# "default_input" = default mic (the DeepFilter denoised source on this machine).
RECORD_AUDIO="default_output|default_input"

take_recording() {
  # Spectacle's KPipeWire recorder rejects odd-width regions ("no more input
  # formats") and silently produces nothing, so recording uses gpu-screen-recorder
  # with an explicit, even-rounded region instead.
  local tool
  for tool in gpu-screen-recorder slurp notify-send; do
    command -v "$tool" >/dev/null 2>&1 || {
      echo "Error: '$tool' is required for recording but was not found"
      return 1
    }
  done

  # Interactive region select, then round W/H DOWN to even (encoders need even dims)
  local geo w h x y
  geo=$(slurp -f '%w %h %x %y') || {
    echo "Region selection cancelled"
    return 1
  }
  read -r w h x y <<<"$geo"
  w=$((w - w % 2))
  h=$((h - h % 2))
  if [ "$w" -lt 2 ] || [ "$h" -lt 2 ]; then
    echo "Error: selected region is too small"
    return 1
  fi
  local region="${w}x${h}+${x}+${y}"
  echo "Recording region ${region} (rounded to even). Click the tray icon to stop."

  # Audio is opt-in via --audio; otherwise record silently. When enabled, mix
  # system audio + mic onto one Opus track.
  local audio_args=()
  if $AUDIO_ENABLED; then
    audio_args=(-ac opus -a "$RECORD_AUDIO")
    echo "Audio capture enabled (system + mic)."
  else
    echo "Audio capture disabled (pass --audio to enable)."
  fi

  # Start the recorder: webm (AV1 video, GPU-encoded — no second ffmpeg pass
  # needed), cursor on.
  gpu-screen-recorder \
    -w "$region" \
    -c webm -k av1 \
    -f 60 -cursor yes -cr limited \
    -bm vbr -q very_high \
    "${audio_args[@]}" \
    -encoder gpu \
    -o "$CAPTURE_FILE" &
  local rec_pid=$!

  # --- Recording indicator + stop control ---
  # Tray dot: a red SNI icon (the only tray kind Plasma 6 renders) drawn by a
  # small PySide6 helper. Clicking the dot or its "Stop" menu item sends SIGINT
  # to gsr, which finalizes the file. Optional — if PySide6 is missing we just
  # rely on the notification below. The helper exits on its own if gsr dies.
  local tray_pid=""
  if python3 -c 'import PySide6.QtWidgets' >/dev/null 2>&1; then
    python3 "$HOME/Scripts/record-tray.py" "$rec_pid" "$region" >/dev/null 2>&1 &
    tray_pid=$!
  fi

  # Notification indicator (persistent, bypasses Do Not Disturb). Captures the
  # notification id so we can close it once recording stops.
  local notif_id=""
  notif_id=$(notify-send -p -i media-record -u critical -t 0 \
    -h "string:x-canonical-private-synchronous:gsr-recording" \
    "● Recording in progress" \
    "Click the red tray dot ⏺ to stop & upload (region ${region})." 2>/dev/null)

  # Wait until the recorder finishes — stopped via the tray dot, or it exits on
  # its own. (If the tray helper is unavailable, stop gsr from a terminal with
  # Ctrl-C / `kill -INT`.)
  wait "$rec_pid"
  local rc=$?

  # Tear down the indicators.
  [ -n "$tray_pid" ] && kill "$tray_pid" 2>/dev/null
  # Fedora ships qdbus6 as qdbus-qt6.
  local qdbus
  qdbus=$(command -v qdbus6 || command -v qdbus-qt6)
  [ -n "$notif_id" ] && [ -n "$qdbus" ] && "$qdbus" org.freedesktop.Notifications /org/freedesktop/Notifications \
    org.freedesktop.Notifications.CloseNotification "$notif_id" >/dev/null 2>&1

  if [ ! -s "$CAPTURE_FILE" ]; then
    echo "Error: recorder exited (code $rc) without producing a file"
    return 1
  fi
}

STARTUP_END_TIME=$(date +%s.%N)
STARTUP_TIME=$(echo "$STARTUP_END_TIME - $SCRIPT_START_TIME" | bc)
STARTUP_TIME_MS=$(echo "$STARTUP_TIME * 1000" | bc | cut -d'.' -f1)
echo "Startup completed in ${STARTUP_TIME_MS}ms"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
if [ "$MODE" = "record" ]; then
  CAPTURE_FILE="/tmp/recording_${TIMESTAMP}.webm"
else
  CAPTURE_FILE="/tmp/screenshot_${TIMESTAMP}.png"
fi

if [ "$MODE" = "record" ]; then
  take_recording
  CAPTURE_LABEL="Recording"
else
  take_screenshot
  CAPTURE_LABEL="Screenshot"
fi

if [ ! -s "$CAPTURE_FILE" ]; then
  echo "Error: ${CAPTURE_LABEL} was not created or is empty"
  exit 1
fi

if [ "$MODE" = "screenshot" ]; then
  CAPTURE_HASH=$(hash_file "$CAPTURE_FILE") || {
    echo "Error: Could not hash ${CAPTURE_LABEL,,}"
    exit 1
  }
  load_last_upload_state
fi

if [ "$MODE" = "screenshot" ] && ! $SCREENSHOT_FROM_CLIPBOARD; then
  wl-copy < "$CAPTURE_FILE"
  if [ $? -ne 0 ]; then
    echo "Warning: Could not copy screenshot to clipboard"
  fi
fi

if should_skip_duplicate_clipboard_upload; then
  UPLOADED_URL="$LAST_UPLOADED_URL"
  SKIPPED_DUPLICATE_UPLOAD=true
  echo "Skipped upload: clipboard screenshot matches previous upload"
else
  UPLOAD_START_TIME=$(date +%s.%N)
  echo "Uploading ${CAPTURE_LABEL,,}..."

  build_upload_headers
  fetch_zipline_config
  zipline_upload "$CAPTURE_FILE" || exit 1

  UPLOAD_END_TIME=$(date +%s.%N)
  UPLOAD_TIME=$(echo "$UPLOAD_END_TIME - $UPLOAD_START_TIME" | bc)
  UPLOAD_TIME_MS=$(echo "$UPLOAD_TIME * 1000" | bc | cut -d'.' -f1)
  echo "Upload completed in ${UPLOAD_TIME_MS}ms"
fi

url="$UPLOADED_URL"

if [ -z "$url" ] || [ "$url" = "null" ]; then
  echo "Error: Could not extract URL from response"
  echo "Response: $CURL_RESPONSE"
  exit 1
fi

if [ "$MODE" = "screenshot" ] && ! $SKIPPED_DUPLICATE_UPLOAD; then
  save_last_upload_state
fi

if ! copy_text_to_clipboard "$url"; then
  echo "Warning: Could not copy URL to clipboard"
  echo "URL: $url"
fi

if command -v notify-send >/dev/null 2>&1; then
  if $SKIPPED_DUPLICATE_UPLOAD; then
    notify-send "${CAPTURE_LABEL} Reused" "Previous URL copied to clipboard: $url"
  else
    notify-send "${CAPTURE_LABEL} Uploaded" "URL copied to clipboard: $url"
  fi
fi

rm -f "$CAPTURE_FILE"

bash "$HOME/Scripts/final.sh"
