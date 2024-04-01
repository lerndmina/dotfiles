#!/bin/bash
TO_INSTALL=""

UNABLE=false

LOCKFILE="/tmp/screenshot.lock"

# Check if the script is already running or has been locked
if [ -f $LOCKFILE ]; then
  UNABLE=true
else
  touch $LOCKFILE
fi

# Check if flameshot is installed
if ! command -v flameshot &>/dev/null; then
  echo "flameshot could not be found, installing..."
  TO_INSTALL="$TO_INSTALL flameshot"
fi

# Check if curl is installed
if ! command -v curl &>/dev/null; then
  echo "curl could not be found, installing..."
  TO_INSTALL="$TO_INSTALL curl"
fi

# Check if jq is installed
if ! command -v jq &>/dev/null; then
  echo "jq could not be found, installing..."
  TO_INSTALL="$TO_INSTALL jq"
fi

# Check if xsel is installed
if ! command -v xsel &>/dev/null; then
  echo "xsel could not be found, installing..."
  TO_INSTALL="$TO_INSTALL xsel"
fi

# Check if paplay is installed
if ! command -v paplay &>/dev/null; then
  echo "paplay could not be found, installing..."
  TO_INSTALL="$TO_INSTALL pulseaudio-utils"
fi

# Check if zenity is installed
if ! command -v zenity &>/dev/null; then
  echo "zenity could not be found, installing..."
  TO_INSTALL="$TO_INSTALL zenity"
fi

# Install missing packages
if [ ! -z "$TO_INSTALL" ]; then
  sudo apt install -y $TO_INSTALL
fi

APIKEY_FILE="/home/wild/Scripts/api_key"
BASE_URL="https://shrt.zip"

while true; do
  # Check if .api_key exists in the current directory and is not empty
  if [ ! -s $APIKEY_FILE ]; then
    api_key=$(zenity --entry --text "Enter your API key:")
    echo "$api_key" >$APIKEY_FILE
    zenity --info --text "API key saved to $APIKEY_FILE"
  else
    echo "DEBUG API key found in $APIKEY_FILE"
    api_key=$(cat $APIKEY_FILE)
  fi

  # Check if API key is valid
  response=$(curl -s -o /dev/null -w "%{http_code}" -H "authorization: $api_key" "$BASE_URL/api/user/recent?take=1")
  if [ "$response" -eq 200 ]; then
    break
  else
    zenity --error --text "Invalid API key, please try again."
    rm $APIKEY_FILE
  fi
done
