#!/bin/bash

# Initialize an empty array to hold packages to install
packages_to_install=()

# Check if git is installed
if ! command -v git &>/dev/null; then
  echo "git could not be found, adding to install list"
  packages_to_install+=("git")
fi

# Check if stow is installed
if ! command -v stow &>/dev/null; then
  echo "stow could not be found, adding to install list"
  packages_to_install+=("stow")
fi

# If there are no packages to install, exit
if [ ${#packages_to_install[@]} -eq 0 ]; then
  echo "All required packages are installed"
  exit
fi

# Detect the Linux distribution
OS="$(awk -F= '/^NAME/{print $2}' /etc/os-release)"

# Install packages based on the distribution
if [[ $OS == *"Ubuntu"* ]]; then
  sudo apt-get update
  sudo apt-get install -y "${packages_to_install[@]}"
elif [[ $OS == *"Fedora"* ]]; then
  sudo dnf install -y "${packages_to_install[@]}"
elif [[ $OS == *"Arch"* ]]; then
  sudo pacman -Syu "${packages_to_install[@]}"
else
  echo "Unsupported distribution"
  exit
fi

# Clone the git repository
git https://github.com/lerndmina/dotfiles.git

# Navigate into the cloned repository
cd dotfiles

# Run stow
stow .
