#!/bin/bash
source $HOME/Scripts/setup.sh

cleanup() {
  echo "DEBUG: cleanup function has been called"
  if ! $UNABLE; then
    rm $LOCKFILE
  fi
}

# Trap the EXIT signal and run the cleanup function
trap cleanup EXIT

if $UNABLE; then
  paplay /usr/share/sounds/sound-icons/hash
  echo "The script is already running or has been locked, exiting..."
  exit 1
fi

flameshot gui -r >/tmp/ss.png #  --accept-on-select
if [ ! -s /tmp/ss.png ]; then
  echo "Screenshot was not taken, exiting..."
  exit 1
fi

curl -H "authorization: $api_key" $BASE_URL/api/upload -F file=@/tmp/ss.png -H "Content-Type: multipart/form-data" -H "Format: random" -H "Embed: true" | jq -r '.files[0]' | tr -d '\n' | xsel -ib
bash $HOME/Scripts/final.sh
