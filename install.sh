#!/bin/bash

# Check if user has sudo access
sudo -l &>/dev/null
if [ $? -ne 0 ]; then
  echo "You do not have sudo access."
  exit 1
fi

function cloneAndStow() {
  cd $HOME

  echo "Installing oh-my-zsh"
  echo ""
  echo "===================="
  echo "IMPORTANT: You will need to exit your shell with CTRL+D before the script can continue as oh-my-zsh will put you in a new shell which will not have the dotfiles installed."
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

  # Generate wakatime config from template
  if [ -z "$WAKATIME_API_KEY" ]; then
    read -p "Enter your WakaTime API key (leave empty to skip): " WAKATIME_API_KEY
  fi
  if [ -n "$WAKATIME_API_KEY" ]; then
    export WAKATIME_API_KEY
    envsubst < $HOME/.wakatime.cfg.template > $HOME/.wakatime.cfg
    echo "Generated .wakatime.cfg from template"
  else
    echo "Skipping wakatime config generation"
  fi

  # Ask if you want to run $HOME/Scripts/initial-server-setup.sh
  read -p "Do you want to run $HOME/Scripts/initial-server-setup.sh? (y/n) " -n 1 -r
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    chmod +x $HOME/Scripts/initial-server-setup.sh
    $HOME/Scripts/initial-server-setup.sh
  else
    echo "Skipping initial server setup"
  fi

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

# Detect the operating system
OS="$(uname)"

# Install packages based on the operating system
if [[ $OS == "Darwin" ]]; then
  # This is a Mac
  for package in "${packages_to_install[@]}"; do
    brew install $package
  done
elif [[ $OS == "Linux" ]]; then
  # This is Linux
  DISTRO="$(awk -F= '/^NAME/{print $2}' /etc/os-release)"
  if [[ $DISTRO == *"Ubuntu"* ]]; then
    # Only add PPA for fastfetch on Ubuntu if fastfetch is in the install list
    if [[ " ${packages_to_install[*]} " =~ " fastfetch " ]]; then
      sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch
    fi
    sudo apt-get update
    sudo apt-get install -y "${packages_to_install[@]}"
  elif [[ $DISTRO == *"Debian"* ]]; then
    sudo apt-get update
    # Try to install all packages - fastfetch may not be available in older Debian repos
    if ! sudo apt-get install -y "${packages_to_install[@]}"; then
      # If installation failed and fastfetch was in the list, try without it
      if [[ " ${packages_to_install[*]} " =~ " fastfetch " ]]; then
        echo "Some packages failed to install, retrying without fastfetch..."
        other_packages=()
        for package in "${packages_to_install[@]}"; do
          if [[ $package != "fastfetch" ]]; then
            other_packages+=("$package")
          fi
        done
        if [ ${#other_packages[@]} -gt 0 ]; then
          sudo apt-get install -y "${other_packages[@]}"
        fi
        echo ""
        echo "Note: fastfetch is not available in your Debian repositories."
        echo "You can install it manually from: https://github.com/fastfetch-cli/fastfetch/releases"
      fi
    fi
  elif [[ $DISTRO == *"Fedora"* ]]; then
    sudo dnf install -y "${packages_to_install[@]}"
  elif [[ $DISTRO == *"Arch"* ]]; then
    sudo pacman -Syu "${packages_to_install[@]}"
  else
    echo "Unsupported distribution install the following packages manually"
    echo "${packages_to_install[@]}"
    exit
  fi
else
  echo "Unsupported operating system. This script works on Mac and Linux only."
  exit
fi

cloneAndStow
