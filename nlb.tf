# ==============================================================================
# GCP Pass-Through Internal Network Load Balancer
#
# Routes traffic across the two CE nodes' SLI (inside / eth1) interfaces.
# Uses a regional internal TCP/UDP NLB (pass-through, L4) so the CE sees the
# original client IP and handles all L7 logic itself.
#
# Architecture:
#   Clients on SLI subnets → Internal NLB (VIP) → CE site1 eth1 OR CE site2 eth1
#
# Why internal NLB on SLI?
#   - SLO (eth0) is the control/tunnel interface toward F5XC Regional Edges.
#   - SLI (eth1) is where workload / east-west traffic enters the CE.
#   - A pass-through NLB preserves the client source IP (no SNAT), which the
#     CE requires for correct policy enforcement and logging.
# ==============================================================================

# ------------------------------------------------------------------------------
# Health Check
# F5XC CE exposes a health endpoint on port 65500 on the SLI interface.
# Adjust to TCP 8080 or HTTPS 443 if you front an app VIP instead.
# ------------------------------------------------------------------------------
resource "google_compute_health_check" "ce_sli_hc" {
  name                = "${var.vpc_name}-ce-sli-hc"
  description         = "Health check for F5XC CE SLI interfaces"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = 65500
    # F5XC CE listens on 65500 for health probes on SLI.
    # If your CE version differs, change to 8080 or use an HTTP check.
  }
}

# ------------------------------------------------------------------------------
# Instance Group - Site 1 CE (unmanaged, single VM)
# ------------------------------------------------------------------------------
resource "google_compute_instance_group" "ce_site1_ig" {
  name        = "${var.site1_name}-ig"
  description = "Instance group for CE Site 1 SLI NLB backend"
  zone        = var.gcp_az_site1
  network     = google_compute_network.vpc.self_link

  instances = [
    google_compute_instance.ce_site1.self_link,
  ]

  named_port {
    name = "ce-sli"
    port = 65500
  }
}

# ------------------------------------------------------------------------------
# Instance Group - Site 2 CE (unmanaged, single VM)
# ------------------------------------------------------------------------------
resource "google_compute_instance_group" "ce_site2_ig" {
  name        = "${var.site2_name}-ig"
  description = "Instance group for CE Site 2 SLI NLB backend"
  zone        = var.gcp_az_site2
  network     = google_compute_network.vpc.self_link

  instances = [
    google_compute_instance.ce_site2.self_link,
  ]

  named_port {
    name = "ce-sli"
    port = 65500
  }
}

# ------------------------------------------------------------------------------
# Backend Service
# Pass-through (INTERNAL) = no proxy, no SNAT, original IP preserved.
# Both CE instance groups are backends so the NLB distributes across AZs.
# ------------------------------------------------------------------------------
resource "google_compute_region_backend_service" "ce_sli_backend" {
  name                  = "${var.vpc_name}-ce-sli-backend"
  region                = var.gcp_region
  description           = "Pass-through NLB backend across CE SLI interfaces"
  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL" # internal pass-through NLB
  health_checks         = [google_compute_health_check.ce_sli_hc.id]

  # SESSION AFFINITY OPTIONS:
  #   NONE           - distribute per-connection (default, good for stateless)
  #   CLIENT_IP      - pin a client IP to a CE (good for stateful flows)
  #   CLIENT_IP_PORT - pin on 5-tuple
  session_affinity = "CLIENT_IP"

  # Failover: if all backends in one AZ are unhealthy, spill to the other
  failover_policy {
    disable_connection_drain_on_failover = false
    drop_traffic_if_unhealthy            = false
    failover_ratio                       = 0.1
  }

  backend {
    group          = google_compute_instance_group.ce_site1_ig.self_link
    description    = "CE Site 1 - ${var.gcp_az_site1}"
    balancing_mode = "CONNECTION"
    failover       = false
  }

  backend {
    group          = google_compute_instance_group.ce_site2_ig.self_link
    description    = "CE Site 2 - ${var.gcp_az_site2}"
    balancing_mode = "CONNECTION"
    failover       = true # Site 2 is failover; flip both to false for active/active
  }
}

# ------------------------------------------------------------------------------
# Forwarding Rule (VIP)
# Creates the actual NLB VIP in the SLI subnet.
# ALL_PORTS = pass all TCP/UDP ports through to the CE unchanged.
#
# The VIP IP is auto-assigned from site1_inside_subnet. You can pin it:
#   ip_address = "10.100.2.10"   (must be within site1_inside_subnet_cidr)
# ------------------------------------------------------------------------------
resource "google_compute_forwarding_rule" "ce_sli_nlb" {
  name                  = "${var.vpc_name}-ce-sli-nlb"
  region                = var.gcp_region
  description           = "Internal pass-through NLB VIP for CE SLI traffic"
  load_balancing_scheme = "INTERNAL"
  backend_service       = google_compute_region_backend_service.ce_sli_backend.id
  network               = google_compute_network.vpc.self_link

  # Attach to the Site 1 SLI subnet — clients in either SLI subnet can reach
  # this VIP because GCP internal NLBs are accessible across subnets in the
  # same VPC when allow_global_access is true (set below).
  subnetwork = google_compute_subnetwork.site1_inside.self_link

  # ALL_PORTS passes every TCP/UDP port to the CE (true pass-through)
  all_ports   = true
  ip_protocol = "TCP"

  # allow_global_access lets clients in site2_inside_subnet (and any other
  # subnet in the VPC, including other regions) reach this VIP.
  allow_global_access = true
}

# ------------------------------------------------------------------------------
# Firewall — allow health check probes to reach CE SLI interfaces
# GCP health checkers source from 35.191.0.0/16 and 130.211.0.0/22
# ------------------------------------------------------------------------------
resource "google_compute_firewall" "ce_sli_hc_ingress" {
  name        = "${var.vpc_name}-ce-sli-hc"
  network     = google_compute_network.vpc.id
  direction   = "INGRESS"
  description = "Allow NLB health check probes to CE SLI port 65500"
  priority    = 900

  target_tags   = ["f5xc-ce-sli"]
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]

  allow {
    protocol = "tcp"
    ports    = ["65500"]
  }
}

# ------------------------------------------------------------------------------
# Firewall — allow all traffic destined for the NLB VIP
# Traffic enters on the SLI subnets; CE handles policy from here.
# Tighten source_ranges to your actual workload CIDRs in production.
# ------------------------------------------------------------------------------
resource "google_compute_firewall" "ce_sli_nlb_ingress" {
  name        = "${var.vpc_name}-ce-sli-nlb-ingress"
  network     = google_compute_network.vpc.id
  direction   = "INGRESS"
  description = "Allow workload traffic to CE SLI via NLB"
  priority    = 1000

  target_tags = ["f5xc-ce-sli"]
  source_ranges = [
    var.site1_inside_subnet_cidr,
    var.site2_inside_subnet_cidr,
  ]

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
}
