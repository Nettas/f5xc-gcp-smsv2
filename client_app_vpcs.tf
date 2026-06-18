# ==============================================================================
# Client VPC
# Hosts workloads that will send traffic to the CE VIP via the NLB.
# Peered to the CE VPC so clients can reach the SLI NLB VIP.
#
# App VPC
# Hosts the backend application. Peered to the CE VPC so the CE's SLI (eth1)
# can forward (SNAT'd) traffic to the app server.
# ==============================================================================

# ------------------------------------------------------------------------------
# Client VPC
# ------------------------------------------------------------------------------
resource "google_compute_network" "client_vpc" {
  name                    = var.client_vpc_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "Client workload VPC - accesses app via CE VIP"
}

resource "google_compute_subnetwork" "client_subnet" {
  name                     = "${var.client_vpc_name}-subnet"
  ip_cidr_range            = var.client_subnet_cidr
  region                   = var.gcp_region
  network                  = google_compute_network.client_vpc.id
  private_ip_google_access = true
  description              = "Client subnet - ${var.client_subnet_az}"
}

# Allow all internal egress from client VPC (clients initiate traffic)
resource "google_compute_firewall" "client_egress" {
  name        = "${var.client_vpc_name}-allow-egress"
  network     = google_compute_network.client_vpc.id
  direction   = "EGRESS"
  description = "Allow client workloads to initiate connections"
  priority    = 1000

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  destination_ranges = ["0.0.0.0/0"]
}

# Allow SSH into client VMs for testing
resource "google_compute_firewall" "client_ssh" {
  name        = "${var.client_vpc_name}-allow-ssh"
  network     = google_compute_network.client_vpc.id
  direction   = "INGRESS"
  description = "SSH into client test VMs"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # GCP IAP range
}

# Allow return traffic from CE SLI subnets back to clients (post-SNAT)
resource "google_compute_firewall" "client_from_ce_sli" {
  name        = "${var.client_vpc_name}-from-ce-sli"
  network     = google_compute_network.client_vpc.id
  direction   = "INGRESS"
  description = "Allow return/response traffic from CE SLI network"
  priority    = 1000

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  source_ranges = [
    var.site1_inside_subnet_cidr,
    var.site2_inside_subnet_cidr,
  ]
}

# ------------------------------------------------------------------------------
# App VPC
# ------------------------------------------------------------------------------
resource "google_compute_network" "app_vpc" {
  name                    = var.app_vpc_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "Application VPC - backend servers behind F5XC CE"
}

resource "google_compute_subnetwork" "app_subnet" {
  name                     = "${var.app_vpc_name}-subnet"
  ip_cidr_range            = var.app_subnet_cidr
  region                   = var.gcp_region
  network                  = google_compute_network.app_vpc.id
  private_ip_google_access = true
  description              = "App server subnet - ${var.app_subnet_az}"
}

# Allow ingress to app servers ONLY from CE SNAT pool
# This enforces that all app traffic flows through the CE (no bypass)
resource "google_compute_firewall" "app_from_ce_sli" {
  name        = "${var.app_vpc_name}-from-ce-sli"
  network     = google_compute_network.app_vpc.id
  direction   = "INGRESS"
  description = "Allow CE SLI traffic to reach app servers"
  priority    = 900

  target_tags = ["f5xc-app-server"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.app_server_port)]
  }

  source_ranges = [
    var.site1_inside_subnet_cidr,
    var.site2_inside_subnet_cidr,
  ]
}

# Allow app server health check responses back to CE SLI
resource "google_compute_firewall" "app_to_ce_sli" {
  name        = "${var.app_vpc_name}-to-ce-sli"
  network     = google_compute_network.app_vpc.id
  direction   = "EGRESS"
  description = "App servers respond back to CE SLI"
  priority    = 1000

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  destination_ranges = [
    var.site1_inside_subnet_cidr,
    var.site2_inside_subnet_cidr,
  ]
}

# Allow SSH for management/testing of app servers
resource "google_compute_firewall" "app_ssh" {
  name        = "${var.app_vpc_name}-allow-ssh"
  network     = google_compute_network.app_vpc.id
  direction   = "INGRESS"
  description = "SSH into app VMs via IAP"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}

# ==============================================================================
# VPC Peering
#
# CE VPC <-> Client VPC:  clients reach the NLB VIP (10.100.2.x)
# CE VPC <-> App VPC:     CE SLI reaches app servers (10.201.x.x)
#
# GCP VPC Peering is non-transitive: client VPC does NOT automatically
# reach app VPC through the CE VPC. All inter-VPC routing is via the CE.
# ==============================================================================

# --- CE <-> Client ---
resource "google_compute_network_peering" "ce_to_client" {
  count        = var.create_vpc_peering ? 1 : 0
  name         = "ce-vpc-to-client-vpc"
  network      = google_compute_network.vpc.self_link
  peer_network = google_compute_network.client_vpc.self_link

  export_custom_routes = true
  import_custom_routes = true
}

resource "google_compute_network_peering" "client_to_ce" {
  count        = var.create_vpc_peering ? 1 : 0
  name         = "client-vpc-to-ce-vpc"
  network      = google_compute_network.client_vpc.self_link
  peer_network = google_compute_network.vpc.self_link

  export_custom_routes = true
  import_custom_routes = true

  depends_on = [google_compute_network_peering.ce_to_client]
}

# --- CE <-> App ---
resource "google_compute_network_peering" "ce_to_app" {
  count        = var.create_vpc_peering ? 1 : 0
  name         = "ce-vpc-to-app-vpc"
  network      = google_compute_network.vpc.self_link
  peer_network = google_compute_network.app_vpc.self_link

  export_custom_routes = true
  import_custom_routes = true
}

resource "google_compute_network_peering" "app_to_ce" {
  count        = var.create_vpc_peering ? 1 : 0
  name         = "app-vpc-to-ce-vpc"
  network      = google_compute_network.app_vpc.self_link
  peer_network = google_compute_network.vpc.self_link

  export_custom_routes = true
  import_custom_routes = true

  depends_on = [google_compute_network_peering.ce_to_app]
}

# ==============================================================================
# Firewall additions to CE VPC for peered traffic
# ==============================================================================

# Clients coming from client_subnet reach CE SLI (NLB VIP)
resource "google_compute_firewall" "ce_sli_from_clients" {
  name        = "${var.vpc_name}-sli-from-clients"
  network     = google_compute_network.vpc.id
  direction   = "INGRESS"
  description = "Allow client VPC traffic to reach CE SLI NLB VIP"
  priority    = 900

  target_tags   = ["f5xc-ce-sli"]
  source_ranges = [var.client_subnet_cidr]

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }
}

# CE SLI can reach app servers in app VPC
resource "google_compute_firewall" "ce_sli_to_app" {
  name        = "${var.vpc_name}-sli-to-app"
  network     = google_compute_network.vpc.id
  direction   = "EGRESS"
  description = "Allow CE SLI to forward SNAT'd traffic to app VPC"
  priority    = 900

  target_tags        = ["f5xc-ce-sli"]
  destination_ranges = [var.app_subnet_cidr]

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }
}
