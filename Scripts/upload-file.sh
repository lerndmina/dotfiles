#!/bin/bash
# Upload files to Zipline (Dolphin's "Upload to Zipline" action). All URLs are
# copied to the clipboard, one per line.

source "$HOME/Scripts/setup.sh"
# setup.sh takes the screenshot lock; a file upload shouldn't block screenshots.
$UNABLE || rm -f "$LOCKFILE"
source "$HOME/Scripts/zipline.sh"

trap '[ -n "$TEMP_CHUNK_DIR" ] && rm -rf "$TEMP_CHUNK_DIR"' EXIT

if [ $# -eq 0 ]; then
  echo "Usage: $(basename "$0") FILE..."
  exit 1
fi

notif_id=$(notify-send -p -i cloud-upload "Uploading to Zipline" \
  "$([ $# -eq 1 ] && basename "$1" || echo "$# files")" 2>/dev/null)

build_upload_headers
fetch_zipline_config

urls=()
failed=()
for file in "$@"; do
  if [ ! -f "$file" ]; then
    echo "Skipping $file: not a regular file"
    failed+=("$(basename "$file")")
    continue
  fi
  echo "Uploading $file..."
  if zipline_upload "$file"; then
    echo "Uploaded: $UPLOADED_URL"
    urls+=("$UPLOADED_URL")
  else
    failed+=("$(basename "$file")")
  fi
done

replace=()
[ -n "$notif_id" ] && replace=(-r "$notif_id")

if [ ${#urls[@]} -gt 0 ]; then
  url_list=$(printf '%s\n' "${urls[@]}")
  if ! copy_text_to_clipboard "${url_list%$'\n'}"; then
    echo "Warning: Could not copy URLs to clipboard"
  fi
fi

if [ ${#failed[@]} -gt 0 ]; then
  notify-send "${replace[@]}" -u critical -i dialog-error "Zipline upload failed" \
    "Failed: ${failed[*]}$([ ${#urls[@]} -gt 0 ] && printf '\nCopied %d URL(s) for the rest.' ${#urls[@]})"
  exit 1
fi

if [ ${#urls[@]} -eq 1 ]; then
  notify-send "${replace[@]}" -i cloud-upload "File Uploaded" "URL copied to clipboard: ${urls[0]}"
else
  notify-send "${replace[@]}" -i cloud-upload "${#urls[@]} Files Uploaded" "URLs copied to clipboard:"$'\n'"$url_list"
fi

bash "$HOME/Scripts/final.sh"
