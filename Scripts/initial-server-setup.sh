#!/bin/bash

# Check if the system is running Ubuntu
if grep -q 'Ubuntu' /etc/os-release; then
  # Update the package list
  sudo apt-get update

  # Install the necessary packages
  sudo apt-get install -y fail2ban

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
fi

# Disable password authentication for the root account
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

# Make ssh keyfile only
sudo sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/g' /etc/ssh/sshd_config
sudo sed -i 's/PubkeyAuthentication no/#PubkeyAuthentication no/g' /etc/ssh/sshd_config

# Disable root login
sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' /etc/ssh/sshd_config
sudo sed -i 's/PermitRootLogin yes/#PermitRootLogin yes/g' /etc/ssh/sshd_config

# Restart the SSH service to apply the changes
sudo systemctl restart sshd

echo "Initial server setup completed."
