#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname)" == "Darwin" ]; then
  DISCORD_APP="/Applications/Discord.app"
  DISCORD_SUPPORT="$HOME/Library/Application Support/discord"
  SETTINGS="$DISCORD_SUPPORT/settings.json"
  VENCORD_URL="https://github.com/Vencord/Installer/releases/latest/download/VencordInstaller.MacOs.zip"
  INSTALL_OPENASAR="${INSTALL_OPENASAR:-1}"

  # Full Disk Access is needed to patch /Applications; fail before downloading anything
  if ! plutil -lint /Library/Preferences/com.apple.TimeMachine.plist >/dev/null 2>&1; then
    echo ""
    echo "This script requires your terminal app to have Full Disk Access. Add this terminal to the Full Disk Access list in System Settings > Privacy & Security, quit the app, and re-run this script."
    echo ""
    read -p "Press any key to exit..." -n 1 -r
    exit 1
  fi

  if ! ping -c 1 -t 5 google.com >/dev/null 2>&1; then
    echo "No internet access, exiting..."
    exit 1
  fi

  if [ ! -d "$DISCORD_APP" ]; then
    echo "$DISCORD_APP not found, exiting..."
    exit 1
  fi

  # Discord must be closed: patching swaps app.asar out from under a running app
  if pgrep -x Discord >/dev/null; then
    echo "Quitting Discord..."
    osascript -e 'quit app "Discord"' >/dev/null 2>&1 || true
    for _ in $(seq 1 10); do
      pgrep -x Discord >/dev/null || break
      sleep 1
    done
    pgrep -x Discord >/dev/null && killall Discord 2>/dev/null || true
  fi

  # Let Homebrew own the bundle version. Discord's own host updater cannot replace a
  # patched (signature-broken) bundle, so it retries forever and rots; --greedy is
  # required because the cask is flagged auto_updates.
  if command -v brew >/dev/null 2>&1 && brew list --cask discord >/dev/null 2>&1; then
    echo "Upgrading Discord via Homebrew..."
    brew upgrade --cask --greedy discord || true
  fi

  # SKIP_HOST_UPDATE stops the bundle-swap updater. It is OPT-IN and defaults to
  # false because Discord's host and its 16 runtime modules live in
  # ~/Library/Application Support/discord/app-<version>/, not in the .app bundle.
  # If that store is missing or the server flags required_update, skipping host
  # updates leaves Discord unable to boot. Only set SKIP_HOST_UPDATE=1 if the
  # store is healthy and you accept updating solely via this script.
  SKIP_HOST_UPDATE_VALUE=false
  [ "${SKIP_HOST_UPDATE:-0}" = "1" ] && SKIP_HOST_UPDATE_VALUE=true
  echo "Setting SKIP_HOST_UPDATE=$SKIP_HOST_UPDATE_VALUE..."
  mkdir -p "$DISCORD_SUPPORT"
  if [ -s "$SETTINGS" ]; then
    tmp_settings=$(mktemp)
    if jq --argjson v "$SKIP_HOST_UPDATE_VALUE" '.SKIP_HOST_UPDATE = $v' "$SETTINGS" >"$tmp_settings" 2>/dev/null; then
      mv "$tmp_settings" "$SETTINGS"
    else
      rm -f "$tmp_settings"
      echo "  warning: could not parse settings.json, leaving it alone"
    fi
  else
    printf '{\n  "SKIP_HOST_UPDATE": %s\n}\n' "$SKIP_HOST_UPDATE_VALUE" >"$SETTINGS"
  fi

  # NOTE: do NOT delete ~/Library/Application Support/discord/app-* here. Those are
  # not stale staging dirs -- they are the live host + module store the app runs from.
  # Removing them bricks Discord until it can re-download the whole install.

  workdir=$(mktemp -d)
  trap 'rm -rf "$workdir"' EXIT

  echo "Downloading Installer..."
  curl -sS -L --fail -o "$workdir/vencord.zip" "$VENCORD_URL"
  unzip -qo "$workdir/vencord.zip" -d "$workdir"

  INSTALLER_APP="$workdir/VencordInstaller.app"
  INSTALLER_BIN="$INSTALLER_APP/Contents/MacOS/VencordInstaller"
  # Gatekeeper blocks the freshly downloaded binary without this
  xattr -dr com.apple.quarantine "$INSTALLER_APP" 2>/dev/null || true
  chmod +x "$INSTALLER_BIN"

  run_installer() {
    "$INSTALLER_BIN" "$@" -location "$DISCORD_APP"
  }

  echo "Patching $DISCORD_APP"
  if run_installer -install; then
    # Each invocation of the installer binary spawns a GUI/Dock instance even in CLI
    # mode, so only call it a second time when OpenAsar is actually missing. After a
    # brew upgrade the bundle is fresh and _app.asar is the stock Discord asar.
    if [ "$INSTALL_OPENASAR" = "1" ]; then
      if strings "$DISCORD_APP/Contents/Resources/_app.asar" 2>/dev/null | grep -qi openasar; then
        echo "OpenAsar already installed, skipping"
      else
        run_installer -install-openasar || echo "  warning: OpenAsar install failed, Vencord is still patched"
      fi
    fi
  else
    # Older installer builds only ship the GUI; fall back to it rather than bailing
    echo "CLI install failed, falling back to the GUI installer..."
    "$INSTALLER_BIN"
  fi

  echo "Cleaning up..."

  read -p "Relaunch Discord? (y/n) " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    open -a Discord
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
  # ParseDiscord requires resources/app to exist; Electron must not find it after patching
  run_installer() {
    mkdir -p "$DISCORD_DIR/resources/app"
    "$outfile" "$@" -location "$DISCORD_DIR"
    rmdir "$DISCORD_DIR/resources/app" 2>/dev/null || true
  }
  run_installer -install
  run_installer -install-openasar
fi
