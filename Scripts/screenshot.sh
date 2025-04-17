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

# Check if we're running under Wayland and force X11 backend if needed
if [ "$XDG_SESSION_TYPE" = "wayland" ] || [ -n "$WAYLAND_DISPLAY" ]; then
  echo "Wayland detected, forcing XCB platform for Flameshot"
  export QT_QPA_PLATFORM=xcb
fi

# Create a temporary file for the screenshot with a timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCREENSHOT_FILE="/tmp/screenshot_${TIMESTAMP}.png"

# Launch flameshot with correct options
flameshot gui -r >"$SCREENSHOT_FILE"
if [ ! -s "$SCREENSHOT_FILE" ]; then
  echo "Error: Screenshot was not taken or is empty"
  exit 1
fi

# Start timing the upload
UPLOAD_START_TIME=$(date +%s.%N)
echo "Uploading screenshot..."

# Upload the screenshot and extract the URL
response=$(curl -s -H "authorization: $api_key" $BASE_URL/api/upload -F "file=@$SCREENSHOT_FILE" -H "Content-Type: multipart/form-data" -H "Format: random" -H "Embed: true")

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
