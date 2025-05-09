provider "google" {
  project     = var.project_id # Replace with your GCP project ID
  region      = var.region           # Replace with your desired region
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
}

terraform {
  backend "gcs" {
    bucket  = "on-premise-nodes" # Replace with your bucket name
    prefix  = "terraform/state"   # Optional path prefix for the state file
  }
}