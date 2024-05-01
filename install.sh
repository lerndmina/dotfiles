#!/bin/bash

# Check if user has sudo access
sudo -l &>/dev/null
if [ $? -ne 0 ]; then
  echo "You do not have sudo access."
  exit 1
fi

function cloneAndStow() {
  cd $HOME

  # Install oh-my-zsh
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  # install powerlevel10k
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

  # Remove .zshrc
  rm $HOME/.zshrc

  # Clone the git repository
  git clone https://github.com/lerndmina/dotfiles.git

  # Navigate into the cloned repository
  cd $HOME/dotfiles

  # Run stow
  stow --adopt .
  git restore .

  exit
}

# Ask if you want to install your public key
read -p "Do you want to install your public key? (y/n) " -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
  # Check if .ssh directory exists, if not, create it
  if [ ! -d "$HOME/.ssh" ]; then
    mkdir $HOME/.ssh
    chmod 700 $HOME/.ssh
  fi

  # Check if authorized_keys file exists, if not, create it
  if [ ! -f "$HOME/.ssh/authorized_keys" ]; then
    touch $HOME/.ssh/authorized_keys
    chmod 600 $HOME/.ssh/authorized_keys
  fi
  # Request the public key
  read -p "Enter your public key: " public_key
  # Add the public key to the authorized_keys file
  echo "$public_key" >>$HOME/.ssh/authorized_keys
  # Restart ssh service
  sudo systemctl restart ssh
else
  echo "Skipping public key installation"
fi

# Initialize an empty array to hold packages to install
packages_to_install=()

# Check if git is installed
if ! command -v git &>/dev/null; then
  echo "git could not be found, adding to install list"
  packages_to_install+=("git")
fi

# Check if zsh is installed
if ! command -v zsh &>/dev/null; then
  echo "zsh could not be found, adding to install list"
  packages_to_install+=("zsh")
fi

# Check if fastfetch is installed
if ! command -v fastfetch &>/dev/null; then
  sudo add-apt-repository ppa:zhangsongcui3371/fastfetch
  echo "fastfetch could not be found, adding to install list"
  packages_to_install+=("fastfetch")
fi

# Check if stow is installed
if ! command -v stow &>/dev/null; then
  echo "stow could not be found, adding to install list"
  packages_to_install+=("stow")
fi

# If there are no packages to install clone then stow
if [ ${#packages_to_install[@]} -eq 0 ]; then
  echo "All required packages are installed"
  cloneAndStow
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
  echo "Unsupported distribution install the following packages manually"
  echo "${packages_to_install[@]}"
  exit
fi

cloneAndStow
