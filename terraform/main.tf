provider "google" {
  project = var.project_id # Replace with your GCP project ID
  region  = var.region     # Replace with your desired region
}

resource "google_compute_network" "private_network" {
  name = "private-network"
}

resource "google_compute_subnetwork" "private_subnetwork" {
  name          = "private-subnetwork"
  ip_cidr_range = "192.168.100.0/24"
  network       = google_compute_network.private_network.id
  region        = var.region
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
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
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

  network_interface {
    network      = google_compute_network.private_network.id
    subnetwork   = google_compute_subnetwork.private_subnetwork.id
    network_ip   = google_compute_address.bastion_internal_ip.address
    access_config {} # Enables public IP
  }

  metadata = {
    ssh-keys = "ubuntu:${tls_private_key.ssh_key.public_key_openssh}"
  }

  tags = ["bastion-host"]

}

resource "google_compute_instance" "private_vm" {
  count        = 2
  name         = "private-vm-${count.index + 1}"
  machine_type = "e2-micro"
  zone         = var.zone

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
    ssh-keys = "ubuntu:${tls_private_key.ssh_key.public_key_openssh}"
  }

  tags = ["private-vm"]

  metadata_startup_script = <<-EOT
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
    bucket = "on-premise-nodes" # Replace with your bucket name
    prefix = "terraform/state-" + var.region # Optional path prefix for the state file
  }
}


resource "google_secret_manager_secret" "ssh_key_public" {
  secret_id = "bastion-ssh-key-public"
  replication {
    automatic = true
  }
}
resource "google_secret_manager_secret_version" "ssh_key_public_version" {
  secret      = google_secret_manager_secret.ssh_key_public.id
  secret_data = tls_private_key.ssh_key.public_key_openssh
}
resource "google_secret_manager_secret" "ssh_key_private" {
  secret_id = "bastion-ssh-private-key"
  replication {
    automatic = true
  }
}
resource "google_secret_manager_secret_version" "ssh_key_private_version" {
  secret      = google_secret_manager_secret.ssh_key_private.id
  secret_data = tls_private_key.ssh_key.private_key_pem
}

resource "null_resource" "final_step" {
  provisioner "local-exec" {
    command = "./scripts/bastion-host.sh"
  }

  depends_on = [google_compute_instance.bastion_host]
}