#!/usr/bin/env bash

set -euo pipefail

packages=(
  nvidia-utils
  lib32-nvidia-utils
  nvidia-settings
  opencl-nvidia
  lib32-opencl-nvidia
  libxnvctrl
  linux-cachyos
  linux-cachyos-headers
  linux-cachyos-nvidia-open
  linux-cachyos-lts
  linux-cachyos-lts-headers
  linux-cachyos-lts-nvidia-open
)

backup="/etc/pacman.conf.bak.$(date +%Y%m%d-%H%M%S)"
tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

echo "Backing up /etc/pacman.conf to $backup"
sudo cp /etc/pacman.conf "$backup"

python3 - "$tmp_file" "${packages[@]}" <<'PY'
from pathlib import Path
import sys

tmp_path = Path(sys.argv[1])
packages = set(sys.argv[2:])
pacman_conf = Path("/etc/pacman.conf")

lines = pacman_conf.read_text().splitlines(keepends=True)
updated = []

for line in lines:
    stripped = line.lstrip()

    if stripped.startswith("IgnorePkg"):
        prefix = line[: len(line) - len(stripped)]
        value = stripped.split("=", 1)[1].strip() if "=" in stripped else ""
        kept = [token for token in value.split() if token not in packages]
        if kept:
            updated.append(f"{prefix}IgnorePkg = {' '.join(kept)}\n")
        else:
            updated.append(f"{prefix}#IgnorePkg   =\n")
        continue

    updated.append(line)

tmp_path.write_text("".join(updated))
PY

echo "Removing NVIDIA hold packages from /etc/pacman.conf"
sudo install -m 644 "$tmp_file" /etc/pacman.conf

echo "Upgrading NVIDIA stack back to repo versions"
sudo pacman -Syu --needed "${packages[@]}"

echo
echo "Done. Reboot before gaming so the updated kernel module is loaded."
