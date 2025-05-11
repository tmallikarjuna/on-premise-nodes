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

resource "google_compute_address" "bastion_internal_ip" {
  name         = "bastion-internal-ip"
  address_type = "INTERNAL"
  subnetwork   = google_compute_subnetwork.private_subnetwork.id
  address      = "192.168.100.2"
  region       = var.region
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
    network_ip   = google_compute_address.bastion_internal_ip.address
    access_config {} # Enables public IP
  }

  metadata = {
    ssh-keys = "ubuntu:${file("ssh/bastion-key.pub")}"
  }

  tags = ["bastion-host"]
  
  metadata_startup_script = <<-EOT
    ${file("path/to/your-setup-script.sh")}
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

  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update
    apt-get install -y dhclient openssh-server

    # Configure DHCP client
    dhclient eth0

    # Configure Squid proxy
    echo "export http_proxy=http://192.168.100.2:3128" >> /etc/environment
    echo "export https_proxy=http://192.168.100.2:3128" >> /etc/environment
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

resource "google_compute_firewall" "allow_dhcp" {
  name    = "allow-dhcp"
  network = google_compute_network.private_network.name

  allow {
    protocol = "udp"
    ports    = ["67", "68"]
  }

  source_tags = ["bastion-host"]   # DHCP server (bastion host)
  target_tags = ["private-vm"]     # DHCP clients (private VMs)
  direction   = "INGRESS"

  priority     = 1000
  source_ranges = ["192.168.100.0/24"] # Your subnet range
}

resource "google_compute_firewall" "allow_proxy_to_bastion" {
  name    = "allow-proxy-to-bastion"
  network = google_compute_network.private_network.name

  allow {
    protocol = "tcp"
    ports    = ["3128"]
  }

  source_tags = ["private-vm"]       # VMs using the proxy
  target_tags = ["bastion-host"]     # Squid proxy host
  direction   = "INGRESS"
}

terraform {
  backend "gcs" {
    bucket  = "on-premise-nodes" # Replace with your bucket name
    prefix  = "terraform/state"   # Optional path prefix for the state file
  }
}