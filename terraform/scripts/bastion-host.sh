#!/bin/bash

# Wait for apt lock to be released
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  echo "Waiting for apt lock to be released..."
  sleep 5
done

# Update the package list and install necessary packages
apt-get update
apt-get install squid openssh-client

# Configure Squid proxy
bash -c 'cat <<EOF > /etc/squid/squid.conf
http_port 3128
acl localnet src 192.168.100.0/24
http_access allow localnet
http_access deny all
EOF'

# Restart Squid service
systemctl enable squid
systemctl restart squid

# Configure SSH key for accessing private VMs
mkdir -p /home/ubuntu/.ssh
cp /etc/ssh/ssh_host_rsa_key.pub /home/ubuntu/.ssh/authorized_keys
chown -R ubuntu:ubuntu /home/ubuntu/.ssh
chmod 600 /home/ubuntu/.ssh/authorized_keys