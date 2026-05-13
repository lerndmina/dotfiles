#!/bin/bash

SCRIPT_START_TIME=$(date +%s.%N)

source "$HOME/Scripts/setup.sh"

MODE="screenshot"
case "${1:-}" in
  --record|-r|record)
    MODE="record"
    shift
    ;;
esac

CAPTURE_FILE=""
TEMP_CHUNK_DIR=""
SCREENSHOT_FROM_CLIPBOARD=false
CURL_RESPONSE=""
CURL_HTTP_CODE=""
UPLOADED_URL=""
LAST_UPLOAD_STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/screenshot-last-upload"
LAST_UPLOADED_HASH=""
LAST_UPLOADED_URL=""
CAPTURE_HASH=""
SKIPPED_DUPLICATE_UPLOAD=false
ZIPLINE_CONFIG_FETCHED=false
ZIPLINE_MAX_FILE_SIZE_BYTES=0
ZIPLINE_CHUNKS_ENABLED=true
ZIPLINE_CHUNK_SIZE_BYTES=$((25 * 1024 * 1024))
ZIPLINE_PARTIAL_THRESHOLD_BYTES=$((50 * 1024 * 1024))

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

size_to_bytes() {
  python3 - "$1" <<'PY'
import re
import sys

value = (sys.argv[1] or '').strip().lower()
if not value:
    print(0)
    raise SystemExit(0)

match = re.fullmatch(r'([0-9]+(?:\.[0-9]+)?)\s*([a-z]+)?', value)
if not match:
    raise SystemExit(1)

number = float(match.group(1))
unit = match.group(2) or 'b'

units = {
    'b': 1,
    'byte': 1,
    'bytes': 1,
    'k': 1024,
    'kb': 1024,
    'kib': 1024,
    'm': 1024 ** 2,
    'mb': 1024 ** 2,
    'mib': 1024 ** 2,
    'g': 1024 ** 3,
    'gb': 1024 ** 3,
    'gib': 1024 ** 3,
    't': 1024 ** 4,
    'tb': 1024 ** 4,
    'tib': 1024 ** 4,
}

if unit not in units:
    raise SystemExit(1)

print(int(number * units[unit]))
PY
}

mime_type_for_file() {
  python3 - "$1" <<'PY'
import mimetypes
import sys

mime, _ = mimetypes.guess_type(sys.argv[1])
print(mime or 'application/octet-stream')
PY
}

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

copy_text_to_clipboard() {
  if command -v xsel >/dev/null 2>&1; then
    printf '%s' "$1" | xsel -ib
    return $?
  fi

  if command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$1" | wl-copy
    return $?
  fi

  return 1
}

run_curl() {
  local response_file
  response_file=$(mktemp)
  CURL_HTTP_CODE=$(curl -sS -o "$response_file" -w "%{http_code}" "$@")
  local curl_status=$?
  CURL_RESPONSE=$(<"$response_file")
  rm -f "$response_file"
  return $curl_status
}

build_upload_headers() {
  UPLOAD_HEADERS=(-H "x-zipline-format: ${UPLOAD_FORMAT:-random}")
  [ -n "$UPLOAD_DOMAIN" ] && UPLOAD_HEADERS+=(-H "x-zipline-domain: $UPLOAD_DOMAIN")
  [ -n "$UPLOAD_FOLDER_ID" ] && UPLOAD_HEADERS+=(-H "x-zipline-folder: $UPLOAD_FOLDER_ID")
  [ -n "$UPLOAD_COMPRESSION" ] && UPLOAD_HEADERS+=(-H "x-zipline-image-compression-percent: $UPLOAD_COMPRESSION")
}

fetch_zipline_config() {
  local public_response
  public_response=$(curl -fsS "$BASE_URL/api/server/public" 2>/dev/null) || return 0

  if ! jq . >/dev/null 2>&1 <<<"$public_response"; then
    return 0
  fi

  ZIPLINE_CONFIG_FETCHED=true

  local max_file_size_raw chunk_size_raw partial_threshold_raw
  max_file_size_raw=$(jq -r '.files.maxFileSize // empty' <<<"$public_response")
  chunk_size_raw=$(jq -r '.chunks.size // empty' <<<"$public_response")
  partial_threshold_raw=$(jq -r '.chunks.max // empty' <<<"$public_response")
  ZIPLINE_CHUNKS_ENABLED=$(jq -r '.chunks.enabled // false' <<<"$public_response")

  if [ -n "$max_file_size_raw" ]; then
    ZIPLINE_MAX_FILE_SIZE_BYTES=$(size_to_bytes "$max_file_size_raw") || ZIPLINE_MAX_FILE_SIZE_BYTES=0
  fi

  if [ -n "$chunk_size_raw" ]; then
    ZIPLINE_CHUNK_SIZE_BYTES=$(size_to_bytes "$chunk_size_raw") || ZIPLINE_CHUNK_SIZE_BYTES=$((25 * 1024 * 1024))
  fi

  if [ -n "$partial_threshold_raw" ]; then
    ZIPLINE_PARTIAL_THRESHOLD_BYTES=$(size_to_bytes "$partial_threshold_raw") || ZIPLINE_PARTIAL_THRESHOLD_BYTES=$((50 * 1024 * 1024))
  fi
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

take_recording() {
  case "$SCREENSHOT_TOOL" in
    spectacle)
      echo "Starting Spectacle recording. Finish the recording from Spectacle when you're done..."
      spectacle -n -b -R r -o "$CAPTURE_FILE"
      ;;
    *)
      echo "Error: Recording mode currently requires SCREENSHOT_TOOL='spectacle'"
      return 1
      ;;
  esac
}

extract_url_from_response() {
  jq -r '.files[0].url // empty' <<<"$1"
}

upload_direct() {
  local mime_type
  mime_type=$(mime_type_for_file "$CAPTURE_FILE")

  if ! run_curl \
    -H "authorization: $api_key" \
    "${UPLOAD_HEADERS[@]}" \
    -F "file=@${CAPTURE_FILE};type=${mime_type};filename=$(basename "$CAPTURE_FILE")" \
    "$BASE_URL/api/upload"; then
    echo "Error: Upload request failed"
    [ -n "$CURL_RESPONSE" ] && echo "Response: $CURL_RESPONSE"
    exit 1
  fi

  if [ "$CURL_HTTP_CODE" -lt 200 ] || [ "$CURL_HTTP_CODE" -ge 300 ]; then
    echo "Error: Upload failed with HTTP $CURL_HTTP_CODE"
    echo "Response: $CURL_RESPONSE"
    exit 1
  fi

  if ! jq . >/dev/null 2>&1 <<<"$CURL_RESPONSE"; then
    echo "Error: Invalid response from server"
    echo "Response: $CURL_RESPONSE"
    exit 1
  fi

  UPLOADED_URL=$(extract_url_from_response "$CURL_RESPONSE")
}

upload_partial() {
  local file_size chunk_size total_chunks mime_type base_name
  file_size=$(stat -c%s "$CAPTURE_FILE")
  chunk_size=$ZIPLINE_CHUNK_SIZE_BYTES
  total_chunks=$(((file_size + chunk_size - 1) / chunk_size))
  mime_type=$(mime_type_for_file "$CAPTURE_FILE")
  base_name=$(basename "$CAPTURE_FILE")
  TEMP_CHUNK_DIR=$(mktemp -d "/tmp/zipline-partial.XXXXXX")

  local identifier=""
  local url=""
  local offset=0
  local chunk_number=1

  while [ "$offset" -lt "$file_size" ]; do
    local end=$((offset + chunk_size))
    if [ "$end" -gt "$file_size" ]; then
      end=$file_size
    fi

    local chunk_file="$TEMP_CHUNK_DIR/chunk_${chunk_number}"
    dd if="$CAPTURE_FILE" of="$chunk_file" iflag=skip_bytes,count_bytes skip="$offset" count="$((end - offset))" status=none

    echo "Uploading chunk ${chunk_number}/${total_chunks}..." >&2

    local chunk_headers=(
      -H "authorization: $api_key"
      "${UPLOAD_HEADERS[@]}"
      -H "x-zipline-p-filename: $base_name"
      -H "x-zipline-p-content-type: $mime_type"
      -H "x-zipline-p-content-length: $file_size"
      -H "x-zipline-p-lastchunk: $([ "$end" -eq "$file_size" ] && echo true || echo false)"
      -H "content-range: bytes ${offset}-${end}/${file_size}"
    )

    if [ -n "$identifier" ]; then
      chunk_headers+=(-H "x-zipline-p-identifier: $identifier")
    fi

    if ! run_curl \
      "${chunk_headers[@]}" \
      -F "file=@${chunk_file};type=${mime_type};filename=${base_name}" \
      "$BASE_URL/api/upload/partial"; then
      echo "Error: Partial upload request failed"
      [ -n "$CURL_RESPONSE" ] && echo "Response: $CURL_RESPONSE"
      exit 1
    fi

    rm -f "$chunk_file"

    if [ "$CURL_HTTP_CODE" -lt 200 ] || [ "$CURL_HTTP_CODE" -ge 300 ]; then
      echo "Error: Partial upload failed with HTTP $CURL_HTTP_CODE"
      echo "Response: $CURL_RESPONSE"
      exit 1
    fi

    if ! jq . >/dev/null 2>&1 <<<"$CURL_RESPONSE"; then
      echo "Error: Invalid response from partial upload"
      echo "Response: $CURL_RESPONSE"
      exit 1
    fi

    if [ -z "$identifier" ]; then
      identifier=$(jq -r '.partialIdentifier // empty' <<<"$CURL_RESPONSE")
    fi

    if [ "$end" -eq "$file_size" ]; then
      url=$(extract_url_from_response "$CURL_RESPONSE")
    fi

    offset=$end
    chunk_number=$((chunk_number + 1))
  done

  if [ -z "$url" ]; then
    echo "Error: Could not extract URL from partial upload response"
    echo "Response: $CURL_RESPONSE"
    exit 1
  fi

  UPLOADED_URL="$url"
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

  FILE_SIZE_BYTES=$(stat -c%s "$CAPTURE_FILE")

  if [ "$ZIPLINE_MAX_FILE_SIZE_BYTES" -gt 0 ] && [ "$FILE_SIZE_BYTES" -gt "$ZIPLINE_MAX_FILE_SIZE_BYTES" ]; then
    echo "Error: ${CAPTURE_LABEL} exceeds the server's max file size"
    echo "File size: $FILE_SIZE_BYTES bytes"
    echo "Server max: $ZIPLINE_MAX_FILE_SIZE_BYTES bytes"
    exit 1
  fi

  USE_PARTIAL=false
  if $ZIPLINE_CHUNKS_ENABLED && [ "$FILE_SIZE_BYTES" -ge "$ZIPLINE_PARTIAL_THRESHOLD_BYTES" ]; then
    USE_PARTIAL=true
  fi

  if ! $ZIPLINE_CONFIG_FETCHED; then
    echo "Warning: Could not fetch Zipline public config, using fallback partial-upload defaults"
  fi

  if $USE_PARTIAL; then
    upload_partial
  else
    upload_direct
  fi

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
