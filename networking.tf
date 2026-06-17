# ==============================================================================
# GCP Networking
# Shared VPC | 4 subnets across 2 AZs (SLO + SLI per site)
# Cloud NAT for outbound internet on SLO subnets
# Firewall rules required for F5XC CE operation
# ==============================================================================

# ------------------------------------------------------------------------------
# Shared VPC
# ------------------------------------------------------------------------------
resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "Shared VPC for F5XC CE sites"
}

# ------------------------------------------------------------------------------
# Site 1 Subnets (AZ-a) - SLO (outside) + SLI (inside)
# ------------------------------------------------------------------------------
resource "google_compute_subnetwork" "site1_outside" {
  name                     = "${var.site1_name}-slo"
  ip_cidr_range            = var.site1_outside_subnet_cidr
  region                   = var.gcp_region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
  description              = "Site 1 SLO (outside) subnet - ${var.gcp_az_site1}"
}

resource "google_compute_subnetwork" "site1_inside" {
  name                     = "${var.site1_name}-sli"
  ip_cidr_range            = var.site1_inside_subnet_cidr
  region                   = var.gcp_region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
  description              = "Site 1 SLI (inside) subnet - ${var.gcp_az_site1}"
}

# ------------------------------------------------------------------------------
# Site 2 Subnets (AZ-b) - SLO (outside) + SLI (inside)
# ------------------------------------------------------------------------------
resource "google_compute_subnetwork" "site2_outside" {
  name                     = "${var.site2_name}-slo"
  ip_cidr_range            = var.site2_outside_subnet_cidr
  region                   = var.gcp_region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
  description              = "Site 2 SLO (outside) subnet - ${var.gcp_az_site2}"
}

resource "google_compute_subnetwork" "site2_inside" {
  name                     = "${var.site2_name}-sli"
  ip_cidr_range            = var.site2_inside_subnet_cidr
  region                   = var.gcp_region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
  description              = "Site 2 SLI (inside) subnet - ${var.gcp_az_site2}"
}

# ------------------------------------------------------------------------------
# Cloud Router + Cloud NAT (for SLO internet egress when no public IP)
# F5XC CE requires outbound internet access on SLO for tunnel registration
# ------------------------------------------------------------------------------
resource "google_compute_router" "nat_router" {
  count   = var.create_cloud_nat ? 1 : 0
  name    = "${var.vpc_name}-router"
  region  = var.gcp_region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "cloud_nat" {
  count  = var.create_cloud_nat ? 1 : 0
  name   = "${var.vpc_name}-nat"
  router = google_compute_router.nat_router[0].name
  region = var.gcp_region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  # Only NAT the SLO (outside) subnets
  subnetwork {
    name                    = google_compute_subnetwork.site1_outside.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  subnetwork {
    name                    = google_compute_subnetwork.site2_outside.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ------------------------------------------------------------------------------
# Firewall Rules
# Required ports for F5XC CE (SMSv2):
#   - TCP 443     : HTTPS / control plane to RE
#   - UDP 4500    : IPsec tunnel to RE
#   - TCP/UDP 53  : DNS
#   - UDP 6080    : Intra-node cluster communication
#   - ICMP        : Health checks between nodes
# ------------------------------------------------------------------------------

# Allow F5XC CE control-plane egress (outbound from CE nodes)
resource "google_compute_firewall" "ce_egress_control_plane" {
  name        = "${var.vpc_name}-ce-egress-ctrl"
  network     = google_compute_network.vpc.id
  direction   = "EGRESS"
  description = "F5XC CE control-plane egress to Regional Edges"
  priority    = 1000

  target_tags = ["f5xc-ce"]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
  allow {
    protocol = "udp"
    ports    = ["4500"]
  }
  allow {
    protocol = "udp"
    ports    = ["53"]
  }
  allow {
    protocol = "tcp"
    ports    = ["53"]
  }

  destination_ranges = ["0.0.0.0/0"]
}

# Allow all egress on SLI (inside) for workload forwarding
resource "google_compute_firewall" "ce_egress_sli" {
  name        = "${var.vpc_name}-ce-egress-sli"
  network     = google_compute_network.vpc.id
  direction   = "EGRESS"
  description = "CE SLI workload forwarding egress"
  priority    = 1000

  target_tags        = ["f5xc-ce-sli"]
  destination_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "all"
  }
}

# Allow intra-CE cluster communication (UDP 6080, ICMP)
resource "google_compute_firewall" "ce_intracluster" {
  name        = "${var.vpc_name}-ce-intracluster"
  network     = google_compute_network.vpc.id
  direction   = "INGRESS"
  description = "F5XC CE intra-cluster communication"
  priority    = 1000

  target_tags = ["f5xc-ce"]
  source_tags = ["f5xc-ce"]

  allow {
    protocol = "udp"
    ports    = ["6080"]
  }
  allow {
    protocol = "icmp"
  }
}

# Allow SSH management access to CE nodes (restrict source_ranges in production)
resource "google_compute_firewall" "ce_ssh" {
  name        = "${var.vpc_name}-ce-ssh"
  network     = google_compute_network.vpc.id
  direction   = "INGRESS"
  description = "SSH management access to CE nodes - RESTRICT IN PRODUCTION"
  priority    = 1000

  target_tags   = ["f5xc-ce"]
  source_ranges = ["10.0.0.0/8"] # Restrict to your management CIDR

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Allow health-check probes from F5XC (GCP health check ranges)
resource "google_compute_firewall" "ce_healthcheck" {
  name        = "${var.vpc_name}-ce-healthcheck"
  network     = google_compute_network.vpc.id
  direction   = "INGRESS"
  description = "GCP health check probes"
  priority    = 1000

  target_tags   = ["f5xc-ce"]
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]

  allow {
    protocol = "tcp"
  }
}
