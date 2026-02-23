#!/bin/bash
# Start timing the entire script
SCRIPT_START_TIME=$(date +%s.%N)

source $HOME/Scripts/setup.sh

cleanup() {
  if ! $UNABLE; then
    rm -f $LOCKFILE
  fi

  # Calculate and display total script runtime
  SCRIPT_END_TIME=$(date +%s.%N)
  SCRIPT_RUNTIME=$(echo "$SCRIPT_END_TIME - $SCRIPT_START_TIME" | bc)
  SCRIPT_RUNTIME_MS=$(echo "$SCRIPT_RUNTIME * 1000" | bc | cut -d'.' -f1)
  echo "Total script runtime: ${SCRIPT_RUNTIME_MS}ms"
}

# Trap the EXIT signal and run the cleanup function
trap cleanup EXIT

if $UNABLE; then
  paplay /usr/share/sounds/sound-icons/hash 2>/dev/null || echo "Error: Could not play sound"
  echo "The script is already running or has been locked, exiting..."
  exit 1
fi

# Record startup completion time
STARTUP_END_TIME=$(date +%s.%N)
STARTUP_TIME=$(echo "$STARTUP_END_TIME - $SCRIPT_START_TIME" | bc)
STARTUP_TIME_MS=$(echo "$STARTUP_TIME * 1000" | bc | cut -d'.' -f1)
echo "Startup completed in ${STARTUP_TIME_MS}ms"

# Create a temporary file for the screenshot with a timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCREENSHOT_FILE="/tmp/screenshot_${TIMESTAMP}.png"

SCREENSHOT_FROM_CLIPBOARD=false

take_screenshot() {
  case "$SCREENSHOT_TOOL" in
    flameshot)
      if [ "$XDG_SESSION_TYPE" = "wayland" ] || [ -n "$WAYLAND_DISPLAY" ]; then
        echo "Wayland detected, running flameshot with XCB platform"
        QT_QPA_PLATFORM=xcb flameshot gui -p "$SCREENSHOT_FILE"
      else
        flameshot gui -p "$SCREENSHOT_FILE"
      fi
      ;;
    grim)
      local geometry
      geometry=$(slurp) || return 1  # return 1 if user cancels selection
      grim -g "$geometry" "$SCREENSHOT_FILE"
      ;;
    spectacle)
      spectacle -r -n -b -o "$SCREENSHOT_FILE"
      # Spectacle may be configured to copy to clipboard rather than save a file.
      # If so, read the image back out of the clipboard.
      if [ ! -s "$SCREENSHOT_FILE" ]; then
        echo "No output file from spectacle, checking clipboard for image..."
        if wl-paste --list-types 2>/dev/null | grep -q "image/png"; then
          wl-paste --type image/png > "$SCREENSHOT_FILE"
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

take_screenshot
if [ ! -s "$SCREENSHOT_FILE" ]; then
  echo "Error: Screenshot was not taken or is empty"
  exit 1
fi

# Copy screenshot to clipboard (skip if spectacle already put it there)
if ! $SCREENSHOT_FROM_CLIPBOARD; then
  wl-copy < "$SCREENSHOT_FILE"
  if [ $? -ne 0 ]; then
    echo "Warning: Could not copy screenshot to clipboard"
  fi
fi

# Start timing the upload
UPLOAD_START_TIME=$(date +%s.%N)
echo "Uploading screenshot..."

# Build upload headers from config (set by setup.sh)
UPLOAD_HEADERS=(-H "x-zipline-format: ${UPLOAD_FORMAT:-random}")
[ -n "$UPLOAD_DOMAIN" ]      && UPLOAD_HEADERS+=(-H "x-zipline-domain: $UPLOAD_DOMAIN")
[ -n "$UPLOAD_FOLDER_ID" ]   && UPLOAD_HEADERS+=(-H "x-zipline-folder: $UPLOAD_FOLDER_ID")
[ -n "$UPLOAD_COMPRESSION" ] && UPLOAD_HEADERS+=(-H "x-zipline-image-compression-percent: $UPLOAD_COMPRESSION")

# Upload the screenshot and extract the URL
response=$(curl -s \
  -H "authorization: $api_key" \
  "${UPLOAD_HEADERS[@]}" \
  "$BASE_URL/api/upload" \
  -F "file=@$SCREENSHOT_FILE")

# Calculate upload time
UPLOAD_END_TIME=$(date +%s.%N)
UPLOAD_TIME=$(echo "$UPLOAD_END_TIME - $UPLOAD_START_TIME" | bc)
UPLOAD_TIME_MS=$(echo "$UPLOAD_TIME * 1000" | bc | cut -d'.' -f1)
echo "Upload completed in ${UPLOAD_TIME_MS}ms"

# Check if the response is valid JSON
if ! echo "$response" | jq . >/dev/null 2>&1; then
  echo "Error: Invalid response from server"
  echo "Response: $response"
  exit 1
fi

# Extract the URL and copy to clipboard
url=$(echo "$response" | jq -r '.files[0].url')
if [ "$url" = "null" ] || [ -z "$url" ]; then
  echo "Error: Could not extract URL from response"
  echo "Response: $response"
  exit 1
fi

# Copy the URL to clipboard
echo -n "$url" | xsel -ib
if [ $? -ne 0 ]; then
  echo "Warning: Could not copy URL to clipboard"
  echo "URL: $url"
fi

# Show a notification with the URL
if command -v notify-send &>/dev/null; then
  notify-send "Screenshot Uploaded" "URL copied to clipboard: $url"
fi

# Clean up the temporary file
rm -f "$SCREENSHOT_FILE"

# Play a success sound
bash $HOME/Scripts/final.sh
