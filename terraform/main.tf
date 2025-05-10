provider "google" {
  project     = var.project_id # Replace with your GCP project ID
  region      = var.region     # Replace with your desired region
}

resource "google_compute_network" "private_network" {
  name = "private-network"
}

resource "google_compute_subnetwork" "private_subnetwork" {
  name          = "private-subnetwork"
  ip_cidr_range = "192.168.100.0/24"
  network       = google_compute_network.private_network.id
  region        = "us-central1"
}

resource "google_compute_instance" "bastion_host" {
  name         = "bastion-host"
  machine_type = "e2-micro"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

  network_interface {
    network    = google_compute_network.private_network.id
    subnetwork = google_compute_subnetwork.private_subnetwork.id
    access_config {} # Enables public IP
  }

  metadata = {
    ssh-keys = "ubuntu:${file("ssh/bastion-key.pub")}"
  }

  tags = ["bastion-host"]

  status = var.vm_status # 👈 status is dynamic
  # This will be set to "RUNNING" or "TERMINATED" based on the variable
  # passed to the module.
  # You can use this to control the state of the VM instances.
  # For example, you can set it to "TERMINATED" to stop the VM instances
  # and "RUNNING" to start them.

  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update
    apt-get install -y isc-dhcp-server squid openssh-client

    # Configure DHCP server
    cat <<EOF > /etc/dhcp/dhcpd.conf
    default-lease-time 600;
    max-lease-time 7200;

    subnet 192.168.100.0 netmask 255.255.255.0 {
      range 192.168.100.100 192.168.100.200;
      option routers 192.168.100.1;
      option domain-name-servers 8.8.8.8, 8.8.4.4;
      option domain-name "docker.local";
    }
    EOF

    systemctl restart isc-dhcp-server

    # Configure Squid proxy
    cat <<EOF > /etc/squid/squid.conf
    http_port 3128
    acl localnet src 192.168.100.0/24
    http_access allow localnet
    http_access deny all
    EOF

    systemctl restart squid

    # Copy SSH key for accessing private VMs
    mkdir -p /home/ubuntu/.ssh
    cp /etc/ssh/ssh_host_rsa_key.pub /home/ubuntu/.ssh/authorized_keys
    chown -R ubuntu:ubuntu /home/ubuntu/.ssh
    chmod 600 /home/ubuntu/.ssh/authorized_keys
  EOT
}

resource "google_compute_instance" "private_vm" {
  count        = 2
  name         = "private-vm-${count.index + 1}"
  machine_type = "e2-micro"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

  network_interface {
    network    = google_compute_network.private_network.id
    subnetwork = google_compute_subnetwork.private_subnetwork.id
  }

  metadata = {
    ssh-keys = "ubuntu:${file("ssh/bastion-key.pub")}"
  }

  tags = ["private-vm"]

  status = var.vm_status # 👈 status is dynamic
  # This will be set to "RUNNING" or "TERMINATED" based on the variable
  # passed to the module.
  # You can use this to control the state of the VM instances.
  # For example, you can set it to "TERMINATED" to stop the VM instances
  # and "RUNNING" to start them.
  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update
    apt-get install -y dhclient openssh-server

    # Configure DHCP client
    dhclient eth0

    # Configure Squid proxy
    echo "export http_proxy=http://192.168.100.1:3128" >> /etc/environment
    echo "export https_proxy=http://192.168.100.1:3128" >> /etc/environment
    source /etc/environment

    # Enable SSH server
    systemctl enable ssh
    systemctl start ssh
  EOT
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.private_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"] # Allows SSH from any IP. Restrict this for better security.
  target_tags   = ["bastion-host"]
}

resource "google_compute_firewall" "allow_internal_ssh" {
  name    = "allow-internal-ssh"
  network = google_compute_network.private_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["192.168.100.0/24"] # Restrict to internal network
  target_tags   = ["private-vm"]
}

terraform {
  backend "gcs" {
    bucket  = "on-premise-nodes" # Replace with your bucket name
    prefix  = "terraform/state"   # Optional path prefix for the state file
  }
}