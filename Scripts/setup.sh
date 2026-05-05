#!/bin/bash
TO_INSTALL=""
REBOOT_NEEDED=false
UNABLE=false
LOCKFILE="/tmp/screenshot.lock"

# Screenshot tool to use. Options: flameshot, spectacle, grim
# Note: grim requires wlr-screencopy (wlroots compositors only, not KDE/KWin)
SCREENSHOT_TOOL="spectacle"

# Check if the script is already running or has been locked
if [ -f $LOCKFILE ]; then
  UNABLE=true
else
  touch $LOCKFILE
fi

# Detect OS type (Bazzite/SteamOS vs regular distro)
IS_BAZZITE=false
if [ -f /etc/os-release ]; then
  . /etc/os-release
  if [[ "$NAME" == *"Bazzite"* ]] || [[ "$NAME" == *"SteamOS"* ]]; then
    IS_BAZZITE=true
    echo "Detected Bazzite/SteamOS environment"
  fi
fi

# Check for required tools
check_package() {
  local cmd=$1
  local pkg=$2
  if ! command -v $cmd &>/dev/null; then
    echo "$cmd could not be found, will install $pkg..."
    TO_INSTALL="$TO_INSTALL $pkg"
  fi
}

# Check for required packages
case "$SCREENSHOT_TOOL" in
  flameshot)  check_package flameshot flameshot ;;
  grim)       check_package grim grim; check_package slurp slurp ;;
  spectacle)  check_package spectacle spectacle ;;
esac
check_package curl curl
check_package jq jq
check_package xsel xsel
check_package wl-copy wl-clipboard
check_package python3 python3
check_package paplay pulseaudio-utils
check_package zenity zenity

# Install missing packages based on detected OS
if [ ! -z "$TO_INSTALL" ]; then
  if $IS_BAZZITE; then
    echo "Installing packages with rpm-ostree on Bazzite/SteamOS..."
    sudo rpm-ostree install $TO_INSTALL
    REBOOT_NEEDED=true
  else
    echo "Installing packages with apt..."
    sudo apt install -y $TO_INSTALL
  fi

  if $REBOOT_NEEDED; then
    zenity --info --title="Reboot Required" --text="Packages have been installed, but you need to reboot your system for the changes to take effect.\n\nPlease reboot when convenient."
  fi
fi

APIKEY_FILE="$HOME/Scripts/api_key"
UPLOAD_CONFIG_FILE="$HOME/Scripts/upload_config"
BASE_URL="https://shrt.zip"

while true; do
  # Check if .api_key exists in the current directory and is not empty
  if [ ! -s $APIKEY_FILE ]; then
    api_key=$(zenity --entry --text "Enter your API key:")
    # Check if user entered anything
    if [ -z "$api_key" ]; then
      rm $LOCKFILE
      exit 1
    fi
    echo "$api_key" >$APIKEY_FILE
    zenity --info --text "API key saved to $APIKEY_FILE"
  else
    api_key=$(cat $APIKEY_FILE)
  fi

  # Check if API key is valid
  response=$(curl -s -o /dev/null -w "%{http_code}" -H "authorization: $api_key" "$BASE_URL/api/user")
  if [ "$response" -eq 200 ]; then
    break
  else
    zenity --error --text "Invalid API key, please try again."
    rm $APIKEY_FILE
  fi
done

setup_upload_config() {
  # 1/4 — Filename format
  format=$(zenity --list \
    --title="Upload Setup (1/4) — Filename Format" \
    --text="How should uploaded files be named?" \
    --radiolist \
    --column="" --column="Format" --column="Example" \
    TRUE  "random" "Dh39ck.png" \
    FALSE "date"   "2021-01-01.png" \
    FALSE "uuid"   "b79c332b-306e-47ff-b564.png" \
    FALSE "gfycat" "adventurous-adorable-gorilla.png" \
    --width=460 --height=400 2>/dev/null) || format="random"
  # zenity --list prints all selected columns; strip anything after the first field
  format=$(echo "$format" | awk '{print $1}')

  # 2/4 — Domain override
  domain=$(zenity --entry \
    --title="Upload Setup (2/4) — Domain Override" \
    --text="Override the domain used in returned URLs (optional).\n\nLeave blank to use your Zipline server's default domain.\nComma-separate multiple values for random selection per upload.\n\nExample: i.example.com" \
    2>/dev/null) || domain=""

  # 3/4 — Folder ID
  folder_id=$(zenity --entry \
    --title="Upload Setup (3/4) — Folder" \
    --text="Folder ID to file screenshots into (optional).\n\nLeave blank to upload without a folder.\nFind folder IDs in your Zipline dashboard under Folders." \
    2>/dev/null) || folder_id=""

  # 4/4 — Image compression
  while true; do
    compression=$(zenity --entry \
      --title="Upload Setup (4/4) — Image Compression" \
      --text="Compress uploaded images (optional).\n\nLeave blank to disable. Enter a percentage from 1–100." \
      2>/dev/null) || { compression=""; break; }
    if [ -z "$compression" ] || { [[ "$compression" =~ ^[0-9]+$ ]] && [ "$compression" -ge 1 ] && [ "$compression" -le 100 ]; }; then
      break
    fi
    zenity --error --title="Invalid Input" \
      --text="Please enter a whole number between 1 and 100, or leave blank to disable compression."
  done

  cat > "$UPLOAD_CONFIG_FILE" <<EOF
UPLOAD_FORMAT="${format:-random}"
UPLOAD_DOMAIN="$domain"
UPLOAD_FOLDER_ID="$folder_id"
UPLOAD_COMPRESSION="$compression"
EOF

  zenity --info \
    --title="Upload Setup Complete" \
    --text="Settings saved to $UPLOAD_CONFIG_FILE\n\nFormat:      ${format:-random}\nDomain:      ${domain:-(default)}\nFolder ID:   ${folder_id:-(none)}\nCompression: ${compression:-(disabled)}\n\nDelete this file to re-run setup." \
    2>/dev/null
}

if [ ! -s "$UPLOAD_CONFIG_FILE" ]; then
  setup_upload_config
fi

source "$UPLOAD_CONFIG_FILE"
