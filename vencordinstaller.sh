#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname)" == "Darwin" ]; then
  DISCORD_APP="/Applications/Discord.app"
  DISCORD_BIN="$DISCORD_APP/Contents/MacOS/Discord"
  DISCORD_SUPPORT="$HOME/Library/Application Support/discord"
  SETTINGS="$DISCORD_SUPPORT/settings.json"
  VENCORD_URL="https://github.com/Vencord/Installer/releases/latest/download/VencordInstallerCli-darwin"

  # OpenAsar is off by default and is REMOVED if present. It looks for modules in
  # discord/<version>/modules, but Discord's current updater installs them under
  # discord/app-<version>/modules, so it fails with "Cannot find module
  # discord_desktop_core" and relaunches forever whenever the bundle version differs
  # from the module store. INSTALL_OPENASAR=1 to opt in anyway.
  INSTALL_OPENASAR="${INSTALL_OPENASAR:-0}"
  # Brew upgrades are off by default. The cask tracks Discord's download page, which
  # runs ahead of the stable update channel (e.g. brew 0.0.413 vs channel 0.0.411), so
  # every upgrade puts the bundle on a version the module store cannot match. Let
  # Discord's own updater own the version; Vencord's patcher survives those.
  # BREW_UPGRADE=1 to opt in.
  BREW_UPGRADE="${BREW_UPGRADE:-0}"
  # LAUNCH=0 to patch without relaunching Discord afterwards.
  LAUNCH="${LAUNCH:-1}"

  log() { printf '\n==> %s\n' "$*"; }
  discord_procs() { pgrep -f "Discord.app/Contents/MacOS/Discord" | wc -l | tr -d ' '; }
  bundle_version() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$DISCORD_APP/Contents/Info.plist" 2>/dev/null || true
  }

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

  # ---------------------------------------------------------------------------
  # 1. Stop Discord, including a boot loop.
  # A version-skewed install ping-pongs between /Applications/Discord.app and the
  # app-<version> host in Application Support, each one relaunching the other before
  # it dies, so a single quit or kill never sticks. Keep killing until it stays down.
  # ---------------------------------------------------------------------------
  if [ "$(discord_procs)" != "0" ]; then
    log "Quitting Discord"
    osascript -e 'quit app "Discord"' >/dev/null 2>&1 || true
    for _ in $(seq 1 10); do
      [ "$(discord_procs)" = "0" ] && break
      sleep 1
    done
    if [ "$(discord_procs)" != "0" ]; then
      echo "Discord did not quit cleanly, forcing (normal when it is boot looping)"
      for _ in $(seq 1 20); do
        pkill -9 -f "Discord.app/Contents/MacOS/Discord" 2>/dev/null || true
        sleep 0.5
      done
    fi
    for _ in $(seq 1 5); do
      if [ "$(discord_procs)" != "0" ]; then
        pkill -9 -f "Discord.app/Contents/MacOS/Discord" 2>/dev/null || true
      fi
      sleep 1
    done
    if [ "$(discord_procs)" != "0" ]; then
      echo "Could not stop Discord, exiting..."
      exit 1
    fi
    echo "Discord stopped"
  fi

  # ---------------------------------------------------------------------------
  # 2. Optional brew upgrade (see BREW_UPGRADE above for why this is off).
  # ---------------------------------------------------------------------------
  if [ "$BREW_UPGRADE" = "1" ] && command -v brew >/dev/null 2>&1 && brew list --cask discord >/dev/null 2>&1; then
    log "Upgrading Discord via Homebrew"
    brew upgrade --cask --greedy discord || true
  fi

  # ---------------------------------------------------------------------------
  # 3. Make sure host updates are enabled.
  # Discord's host and its runtime modules live in
  # ~/Library/Application Support/discord/app-<version>/, not in the .app bundle.
  # SKIP_HOST_UPDATE=true blocks the only mechanism that can (re)build that store,
  # and the server can flag required_update, so it is always forced back to false.
  # ---------------------------------------------------------------------------
  log "Ensuring SKIP_HOST_UPDATE=false"
  mkdir -p "$DISCORD_SUPPORT"
  if [ -s "$SETTINGS" ]; then
    tmp_settings=$(mktemp)
    if jq '.SKIP_HOST_UPDATE = false' "$SETTINGS" >"$tmp_settings" 2>/dev/null; then
      mv "$tmp_settings" "$SETTINGS"
    else
      rm -f "$tmp_settings"
      echo "  warning: could not parse settings.json, leaving it alone"
    fi
  else
    printf '{\n  "SKIP_HOST_UPDATE": false\n}\n' >"$SETTINGS"
  fi

  # ---------------------------------------------------------------------------
  # 4. Repair version skew.
  # installer.db records which app-<version> host the launcher should hand off to.
  # If the bundle is NEWER than every host in the store (what a brew upgrade does),
  # the launcher hands off to the older host, which sees a newer bundle and hands
  # straight back: a boot loop. A fresh installer.db makes the updater register the
  # bundle itself as the host and build a matching app-<version> store.
  # The store being newer than the bundle is fine and is left alone.
  # NEVER delete app-* directories here: they are the live install, not staging.
  # ---------------------------------------------------------------------------
  bundle_ver=$(bundle_version)
  newest_store=""
  for d in "$DISCORD_SUPPORT"/app-*; do
    [ -d "$d" ] || continue
    v=${d##*/app-}
    if [ -z "$newest_store" ] || [ "${v##*.}" -gt "${newest_store##*.}" ]; then
      newest_store=$v
    fi
  done
  if [ -n "$bundle_ver" ] && [ -f "$DISCORD_SUPPORT/installer.db" ]; then
    if [ -z "$newest_store" ] || [ "${bundle_ver##*.}" -gt "${newest_store##*.}" ]; then
      log "Bundle $bundle_ver is newer than module store ${newest_store:-<none>}: resetting installer.db"
      cp "$DISCORD_SUPPORT/installer.db" "$DISCORD_SUPPORT/installer.db.bak"
      rm -f "$DISCORD_SUPPORT/installer.db"
      echo "  backup at $DISCORD_SUPPORT/installer.db.bak; Discord will rebuild the store on launch"
    else
      echo "Module store ${newest_store} matches or is newer than bundle ${bundle_ver}, nothing to do"
    fi
  fi

  # ---------------------------------------------------------------------------
  # 5. Patch.
  # ---------------------------------------------------------------------------
  workdir=$(mktemp -d)
  trap 'rm -rf "$workdir"' EXIT

  log "Downloading Vencord installer"
  INSTALLER_BIN="$workdir/VencordInstallerCli"
  curl -sS -L --fail -o "$INSTALLER_BIN" "$VENCORD_URL"
  # Gatekeeper blocks the freshly downloaded binary without this
  xattr -d com.apple.quarantine "$INSTALLER_BIN" 2>/dev/null || true
  chmod +x "$INSTALLER_BIN"

  run_installer() {
    "$INSTALLER_BIN" "$@" -location "$DISCORD_APP"
  }
  has_openasar() {
    strings "$DISCORD_APP/Contents/Resources/_app.asar" 2>/dev/null | grep -qi openasar
  }

  log "Patching $DISCORD_APP with Vencord"
  run_installer -install

  if [ "$INSTALL_OPENASAR" = "1" ]; then
    if has_openasar; then
      echo "OpenAsar already installed"
    else
      log "Installing OpenAsar (INSTALL_OPENASAR=1)"
      run_installer -install-openasar || echo "  warning: OpenAsar install failed, Vencord is still patched"
    fi
  elif has_openasar; then
    log "Removing OpenAsar (see INSTALL_OPENASAR above)"
    run_installer -uninstall-openasar
  fi

  # ---------------------------------------------------------------------------
  # 6. Relaunch and verify it stays up.
  # Launched directly so the bootstrap output (Vencord, host handoff, module
  # errors) is captured; `open -a` would discard it. One handoff is the normal path
  # when the store host is newer than the bundle; repeated handoffs are a loop.
  # ---------------------------------------------------------------------------
  if [ "$LAUNCH" = "1" ]; then
    launch_log="$DISCORD_SUPPORT/vencordinstaller-launch.log"
    log "Launching Discord (bootstrap log: $launch_log)"
    nohup "$DISCORD_BIN" >"$launch_log" 2>&1 &
    disown
    for _ in $(seq 1 30); do sleep 1; done
    procs=$(discord_procs)
    handoffs=$(grep -c "Quitting for update" "$launch_log" 2>/dev/null || true)
    handoffs=${handoffs:-0}
    if [ "$procs" = "0" ]; then
      echo ""
      echo "FAILED: Discord is not running 30s after launch. Last lines of $launch_log:"
      tail -15 "$launch_log"
      exit 1
    elif [ "$handoffs" -gt 2 ]; then
      echo ""
      echo "FAILED: Discord is boot looping ($handoffs host handoffs in 30s). Last lines of $launch_log:"
      tail -15 "$launch_log"
      exit 1
    elif grep -q "Cannot find module" "$launch_log" 2>/dev/null; then
      echo ""
      echo "FAILED: module load error. Last lines of $launch_log:"
      grep -n "Cannot find module" "$launch_log" | head -3
      exit 1
    fi
    echo ""
    echo "OK: Discord is running with Vencord (bundle $(bundle_version), host handoffs: $handoffs)"
  else
    echo ""
    echo "Done (LAUNCH=0, not relaunching Discord)"
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
  curl -sS https://github.com/Vencord/Installer/releases/latest/download/VencordInstallerCli-linux \
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
  if [ "${INSTALL_OPENASAR:-0}" = "1" ]; then
    run_installer -install-openasar
  fi
fi
