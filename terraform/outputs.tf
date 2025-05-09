output "bastion_host_public_ip" {
  description = "Public IP of the Bastion Host"
  value       = google_compute_instance.bastion_host.network_interface[0].access_config[0].nat_ip
}

output "private_vm_ips" {
  description = "Private IPs of the VMs"
  value       = [for vm in google_compute_instance.private_vm : vm.network_interface[0].network_ip]
}