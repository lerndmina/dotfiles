#!/bin/bash

# Check if the system is running Ubuntu
if grep -q 'Ubuntu' /etc/os-release; then
  # Update the package list
  sudo apt-get update


  THINGS_TO_INSTALL=()

  # Ask the user if they want to install ufw
  read -p "Do you want to install and configure ufw? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    THINGS_TO_INSTALL+=("ufw")
  fi

  # Ask the user if they want to install fail2ban
  read -p "Do you want to install and configure fail2ban? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    THINGS_TO_INSTALL+=("fail2ban")
  fi

  # Install the packages
  for package in "${THINGS_TO_INSTALL[@]}"; do
    sudo apt-get install -y $package
  done

  # Enable the ufw firewall if it was installed
  if [[ " ${THINGS_TO_INSTALL[@]} " =~ "ufw" ]]; then
    # Enable the firewall
    sudo ufw enable

    # Allow SSH connections through the firewall
    sudo ufw allow OpenSSH

    # Allow HTTPS traffic
    sudo ufw allow https

    # Reload the firewall
    sudo ufw reload
  fi

  # Enable the fail2ban service if it was installed
  if [[ " ${THINGS_TO_INSTALL[@]} " =~ "fail2ban" ]]; then
    # Install the necessary packages

    # Setup fail2ban to protect against SSH attacks
    sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

    # Configure fail2ban to ban IPs after 3 failed attempts for 10 minutes
    sudo sed -i 's/maxretry = 5/maxretry = 3/g' /etc/fail2ban/jail.local
    sudo sed -i 's/bantime  = 10m/bantime  = 10m/g' /etc/fail2ban/jail.local

    # Start and enable fail2ban
    sudo systemctl start fail2ban
    sudo systemctl enable fail2ban

    # Disable needrestart prompt
    echo "\$nrconf{kernelhints} = -1;" > /etc/needrestart/conf.d/99disable-prompt.conf

    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban
  fi
fi

# Disable password authentication for the root account
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

# Make ssh keyfile only
sudo sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/g' /etc/ssh/sshd_config
sudo sed -i 's/PubkeyAuthentication no/#PubkeyAuthentication no/g' /etc/ssh/sshd_config

# Disable root login with password allow root login with key
sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin without-password/g' /etc/ssh/sshd_config
sudo sed -i 's/PermitRootLogin yes/#PermitRootLogin yes/g' /etc/ssh/sshd_config

# Restart the SSH service to apply the changes
sudo systemctl restart sshd

echo "Initial server setup completed."
