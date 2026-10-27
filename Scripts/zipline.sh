#!/bin/bash
# Shared Zipline upload helpers. Source after setup.sh (needs $api_key, $BASE_URL
# and the UPLOAD_* settings from upload_config).

CURL_RESPONSE=""
CURL_HTTP_CODE=""
UPLOADED_URL=""
TEMP_CHUNK_DIR=""
ZIPLINE_CONFIG_FETCHED=false
ZIPLINE_MAX_FILE_SIZE_BYTES=0
ZIPLINE_CHUNKS_ENABLED=true
ZIPLINE_CHUNK_SIZE_BYTES=$((25 * 1024 * 1024))
ZIPLINE_PARTIAL_THRESHOLD_BYTES=$((50 * 1024 * 1024))

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
  public_response=$(curl -fsS "$BASE_URL/api/server/public" 2>/dev/null) || {
    echo "Warning: Could not fetch Zipline public config, using fallback partial-upload defaults"
    return 0
  }

  if ! jq . >/dev/null 2>&1 <<<"$public_response"; then
    echo "Warning: Could not fetch Zipline public config, using fallback partial-upload defaults"
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

extract_url_from_response() {
  jq -r '.files[0].url // empty' <<<"$1"
}

upload_direct() {
  local file=$1 mime_type
  mime_type=$(mime_type_for_file "$file")

  if ! run_curl \
    -H "authorization: $api_key" \
    "${UPLOAD_HEADERS[@]}" \
    -F "file=@${file};type=${mime_type};filename=$(basename "$file")" \
    "$BASE_URL/api/upload"; then
    echo "Error: Upload request failed"
    [ -n "$CURL_RESPONSE" ] && echo "Response: $CURL_RESPONSE"
    return 1
  fi

  if [ "$CURL_HTTP_CODE" -lt 200 ] || [ "$CURL_HTTP_CODE" -ge 300 ]; then
    echo "Error: Upload failed with HTTP $CURL_HTTP_CODE"
    echo "Response: $CURL_RESPONSE"
    return 1
  fi

  if ! jq . >/dev/null 2>&1 <<<"$CURL_RESPONSE"; then
    echo "Error: Invalid response from server"
    echo "Response: $CURL_RESPONSE"
    return 1
  fi

  UPLOADED_URL=$(extract_url_from_response "$CURL_RESPONSE")
}

upload_partial() {
  local file=$1 file_size chunk_size total_chunks mime_type base_name
  file_size=$(stat -c%s "$file")
  chunk_size=$ZIPLINE_CHUNK_SIZE_BYTES
  total_chunks=$(((file_size + chunk_size - 1) / chunk_size))
  mime_type=$(mime_type_for_file "$file")
  base_name=$(basename "$file")
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
    dd if="$file" of="$chunk_file" iflag=skip_bytes,count_bytes skip="$offset" count="$((end - offset))" status=none

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
      return 1
    fi

    rm -f "$chunk_file"

    if [ "$CURL_HTTP_CODE" -lt 200 ] || [ "$CURL_HTTP_CODE" -ge 300 ]; then
      echo "Error: Partial upload failed with HTTP $CURL_HTTP_CODE"
      echo "Response: $CURL_RESPONSE"
      return 1
    fi

    if ! jq . >/dev/null 2>&1 <<<"$CURL_RESPONSE"; then
      echo "Error: Invalid response from partial upload"
      echo "Response: $CURL_RESPONSE"
      return 1
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

  rm -rf "$TEMP_CHUNK_DIR"
  TEMP_CHUNK_DIR=""

  if [ -z "$url" ]; then
    echo "Error: Could not extract URL from partial upload response"
    echo "Response: $CURL_RESPONSE"
    return 1
  fi

  UPLOADED_URL="$url"
}

# Upload one file, picking direct or chunked upload from the server's limits.
# Call build_upload_headers and fetch_zipline_config first. Sets UPLOADED_URL.
zipline_upload() {
  local file=$1 file_size
  UPLOADED_URL=""
  file_size=$(stat -c%s "$file") || return 1

  if [ "$ZIPLINE_MAX_FILE_SIZE_BYTES" -gt 0 ] && [ "$file_size" -gt "$ZIPLINE_MAX_FILE_SIZE_BYTES" ]; then
    echo "Error: $(basename "$file") exceeds the server's max file size"
    echo "File size: $file_size bytes"
    echo "Server max: $ZIPLINE_MAX_FILE_SIZE_BYTES bytes"
    return 1
  fi

  if $ZIPLINE_CHUNKS_ENABLED && [ "$file_size" -ge "$ZIPLINE_PARTIAL_THRESHOLD_BYTES" ]; then
    upload_partial "$file" || return 1
  else
    upload_direct "$file" || return 1
  fi

  if [ -z "$UPLOADED_URL" ] || [ "$UPLOADED_URL" = "null" ]; then
    echo "Error: Could not extract URL from response"
    echo "Response: $CURL_RESPONSE"
    return 1
  fi
}
