#!/bin/bash
TO_INSTALL=""
REBOOT_NEEDED=false
UNABLE=false
LOCKFILE="/tmp/screenshot.lock"

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
check_package flameshot flameshot
check_package curl curl
check_package jq jq
check_package xsel xsel
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
