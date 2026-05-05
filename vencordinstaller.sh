if [ "$(uname)" == "Darwin" ]; then
  # Check internet access
  if ! ping -c 1 google.com >/dev/null; then
    echo "No internet access, exiting..."
    exit 1
  fi

  VENCORD_URL="https://github.com/Vencord/Installer/releases/latest/download/VencordInstaller.MacOs.zip"
  VENCORD_INSTALLER="VencordInstaller.app"
  RANDOM_NUMBER=$(shuf -i 1-10000 -n 1)
  VENCORD_INSTALLER_PATH="/tmp/"

  # Download the zip
  curl -L -o "vencord-$RANDOM_NUMBER.zip" "$VENCORD_URL"

  # Extract the zip
  unzip -o "vencord-$RANDOM_NUMBER.zip" -d "$VENCORD_INSTALLER_PATH"

  # MacOS check if current process has full disk access
  if ! plutil -lint /Library/Preferences/com.apple.TimeMachine.plist >/dev/null; then
    echo ""
    echo ""
    echo ""
    echo "This script requires your terminal app to have Full Disk Access. Add this terminal to the Full Disk Access list in System Settings > Privacy & Security, quit the app, and re-run this script."
    echo ""
    read -p "Press any key to exit..." -n 1 -r
    exit 1
  fi

  # Execute the installer run the file "/tmp/VencordInstaller.app/Contents/MacOS/VencordInstaller"
  "$VENCORD_INSTALLER_PATH/$VENCORD_INSTALLER/Contents/MacOS/VencordInstaller"

  echo "Cleaning up..."

  # Remove the zip
  rm "vencord-$RANDOM_NUMBER.zip"

  # Remove the installer
  rm -rf "$VENCORD_INSTALLER_PATH/$VENCORD_INSTALLER"

  # Ask if you want to restart discord
  read -p "Do you want to kill discord? (y/n) " -n 1 -r
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Killing discord..."
    echo ""
    killall -9 Discord
  fi

else
  DISCORD_DIR=$(ls -d "$HOME/.config/discord/app-"* 2>/dev/null | sort -V | tail -1)
  if [ -z "$DISCORD_DIR" ]; then
    echo "Could not find Discord installation in $HOME/.config/discord/"
    exit 1
  fi

  outfile=$(mktemp)
  trap 'rm -f "$outfile"' EXIT

  echo "Downloading Installer..."
  curl -sS https://github.com/Vendicated/VencordInstaller/releases/latest/download/VencordInstallerCli-Linux \
    -o "$outfile" -L --fail
  chmod +x "$outfile"

  echo "Installing to $DISCORD_DIR"
  sudo "$outfile" -install -location "$DISCORD_DIR"
  sudo "$outfile" -install-openasar -location "$DISCORD_DIR"
fi
