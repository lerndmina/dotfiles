#!/bin/bash
# Load setup.sh, which contains api_key and base_url
source $HOME/Scripts/setup.sh

# Get clipboard content
clipboard_content=$(xclip -selection clipboard -o)

# Check if clipboard content is a URL and does not contain shrt.zip
if [[ $clipboard_content =~ ^http(s)?://[^/]+ ]] && [[ ! $clipboard_content =~ shrt\.zip ]]; then
  echo "Clipboard contains a URL that does not have the domain shrt.zip"
  # Use the URL from the clipboard
  url=$clipboard_content
else
  echo "Clipboard does not contain a URL or the URL contains the domain shrt.zip"
  # Now ask the user for a URL
  url=$(zenity --entry --text "Enter the url you wish to shorten:")
  # Check if the user entered a URL
  if [ -z "$url" ]; then
    echo "User did not enter a URL"
    exit 1
  fi
  # Check if the URL is valid
  if [[ ! $url =~ ^http(s)?://[^/]+ ]]; then
    zenity --error --text "Url is not valid. Not shortening..."
    exit 1
  fi
fi

curl -H "authorization: $api_key" $BASE_URL/api/shorten -H "Content-Type: application/json" -d "{\"url\": \"$url\"}" | jq -r '.url' | tr -d '\n' | xsel -ib
bash $HOME/Scripts/final.sh
