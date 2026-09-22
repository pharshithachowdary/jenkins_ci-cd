#!/usr/bin/env bash
# provision_ec2.sh
#
# One-time setup for a fresh EC2 instance (Amazon Linux 2023 / Ubuntu 22.04)
# so it can act as the Jenkins deploy target. Run manually once per instance,
# or via user-data at launch.
set -euo pipefail

echo "==> Installing Docker"
if command -v dnf >/dev/null 2>&1; then
    sudo dnf update -y
    sudo dnf install -y docker
elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y docker.io
fi

sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker "${USER}"

echo "==> Installing AWS CLI (for ECR auth)"
if ! command -v aws >/dev/null 2>&1; then
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install
    rm -rf awscliv2.zip aws
fi

echo "==> Opening firewall for app port 8000 (adjust security group instead in production)"
echo "NOTE: Prefer managing inbound rules via the EC2 Security Group, not local iptables."

echo "==> Done. Log out/in for docker group membership to take effect."
echo "Next: add this instance's user@host as the 'ec2-deploy-host' credential in Jenkins,"
echo "and its SSH private key as the 'ec2-ssh-key' credential."
