#!/bin/bash

# Wait for apt lock to be released
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  echo "Waiting for apt lock to be released..."
  sleep 5
done

# Update the package list and install necessary packages
sudo apt-get update
sudo apt-get install -y isc-dhcp-server squid openssh-client

# Configure DHCP server
sudo bash -c 'cat <<EOF > /etc/dhcp/dhcpd.conf
default-lease-time 600;
max-lease-time 7200;

subnet 192.168.100.0 netmask 255.255.255.0 {
  range 192.168.100.100 192.168.100.200;
  option routers 192.168.100.1;
  option domain-name-servers 8.8.8.8, 8.8.4.4;
  option domain-name "docker.local";
}
EOF'

# Restart the DHCP service
sudo systemctl enable isc-dhcp-server
sudo systemctl restart isc-dhcp-server

# Configure Squid proxy
sudo bash -c 'cat <<EOF > /etc/squid/squid.conf
http_port 3128
acl localnet src 192.168.100.0/24
http_access allow localnet
http_access deny all
EOF'

# Restart Squid service
sudo systemctl enable squid
sudo systemctl restart squid

# Configure SSH key for accessing private VMs
sudo mkdir -p /home/ubuntu/.ssh
sudo cp /etc/ssh/ssh_host_rsa_key.pub /home/ubuntu/.ssh/authorized_keys
sudo chown -R ubuntu:ubuntu /home/ubuntu/.ssh
sudo chmod 600 /home/ubuntu/.ssh/authorized_keys