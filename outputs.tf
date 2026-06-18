# ==============================================================================
# Outputs
# ==============================================================================

# ---- VPC ----
output "vpc_id" {
  description = "GCP VPC self link"
  value       = google_compute_network.vpc.self_link
}

output "vpc_name" {
  description = "GCP VPC name"
  value       = google_compute_network.vpc.name
}

# ---- Site 1 ----
output "site1_name" {
  description = "F5XC Site 1 name"
  value       = volterra_securemesh_site_v2.site1.name
}

output "site1_az" {
  description = "GCP AZ for Site 1"
  value       = var.gcp_az_site1
}

output "site1_outside_subnet" {
  description = "Site 1 SLO subnet name"
  value       = google_compute_subnetwork.site1_outside.name
}

output "site1_inside_subnet" {
  description = "Site 1 SLI subnet name"
  value       = google_compute_subnetwork.site1_inside.name
}

output "site1_vm_name" {
  description = "Site 1 CE VM instance name"
  value       = google_compute_instance.ce_site1.name
}

output "site1_vm_slo_ip" {
  description = "Site 1 CE VM SLO (eth0) private IP"
  value       = google_compute_instance.ce_site1.network_interface[0].network_ip
}

output "site1_vm_sli_ip" {
  description = "Site 1 CE VM SLI (eth1) private IP"
  value       = google_compute_instance.ce_site1.network_interface[1].network_ip
}

# ---- Site 2 ----
output "site2_name" {
  description = "F5XC Site 2 name"
  value       = volterra_securemesh_site_v2.site2.name
}

output "site2_az" {
  description = "GCP AZ for Site 2"
  value       = var.gcp_az_site2
}

output "site2_outside_subnet" {
  description = "Site 2 SLO subnet name"
  value       = google_compute_subnetwork.site2_outside.name
}

output "site2_inside_subnet" {
  description = "Site 2 SLI subnet name"
  value       = google_compute_subnetwork.site2_inside.name
}

output "site2_vm_name" {
  description = "Site 2 CE VM instance name"
  value       = google_compute_instance.ce_site2.name
}

output "site2_vm_slo_ip" {
  description = "Site 2 CE VM SLO (eth0) private IP"
  value       = google_compute_instance.ce_site2.network_interface[0].network_ip
}

output "site2_vm_sli_ip" {
  description = "Site 2 CE VM SLI (eth1) private IP"
  value       = google_compute_instance.ce_site2.network_interface[1].network_ip
}

# ---- Tokens (sensitive) ----
output "site1_registration_token" {
  description = "Site 1 F5XC registration token (sensitive)"
  value       = volterra_token.site1_token.id
  sensitive   = true
}

output "site2_registration_token" {
  description = "Site 2 F5XC registration token (sensitive)"
  value       = volterra_token.site2_token.id
  sensitive   = true
}

# ---- NLB ----
output "nlb_vip" {
  description = "Internal NLB VIP address (clients send workload traffic here)"
  value       = google_compute_forwarding_rule.ce_sli_nlb.ip_address
}

output "nlb_name" {
  description = "Internal NLB forwarding rule name"
  value       = google_compute_forwarding_rule.ce_sli_nlb.name
}

output "nlb_backend_service" {
  description = "NLB backend service name"
  value       = google_compute_region_backend_service.ce_sli_backend.name
}

# ---- Client VPC ----
output "client_vpc_name" {
  description = "Client VPC name"
  value       = google_compute_network.client_vpc.name
}

output "client_subnet_cidr" {
  description = "Client subnet CIDR"
  value       = google_compute_subnetwork.client_subnet.ip_cidr_range
}

# ---- App VPC ----
output "app_vpc_name" {
  description = "App VPC name"
  value       = google_compute_network.app_vpc.name
}

output "app_subnet_cidr" {
  description = "App subnet CIDR"
  value       = google_compute_subnetwork.app_subnet.ip_cidr_range
}

output "app_server_ip" {
  description = "App server private IP (origin for F5XC)"
  value       = var.app_server_ip
}
