#!/usr/bin/env bash
set -euo pipefail
# Execute manually after reviewing on a NEW Ubuntu 24.04 EC2 lab instance.
sudo apt-get update
sudo apt-get install -y docker.io curl git
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
if ! swapon --show | grep -q .; then
  sudo fallocate -l 1G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi
echo 'Docker installed. Log out and back in for group membership to take effect.'
echo 'WARNING: docker group membership provides root-equivalent privileges.'
