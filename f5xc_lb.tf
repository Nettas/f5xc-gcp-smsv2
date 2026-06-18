/*
# ==============================================================================
# F5 Distributed Cloud - Application Delivery
#
# Flow:
#   Client (client VPC)
#     → GCP NLB VIP (SLI subnet)
#       → CE eth1 (SLI) receives traffic on advertised VIP
#         → F5XC HTTP LB (advertised on SLI of both CE sites)
#           → Origin Pool (app server private IP via CE SLI)
#             → CE SNATs to snat_pool_prefix
#               → App server (app VPC)
#
# The VIP is advertised on SITE_LOCAL_INSIDE (SLI / eth1) of both CE sites
# using advertise_custom so it appears on the internal NLB-facing interface.
# ==============================================================================

# ------------------------------------------------------------------------------
# Health Check
# F5XC probes the app server from the CE SLI interface.
# ------------------------------------------------------------------------------
resource "volterra_healthcheck" "app_hc" {
  name      = "app-healthcheck"
  namespace = var.f5xc_namespace_workload

  http_health_check {
    use_origin_server_name = true
    path                   = "/health"
    # Use "/"" if your app has no dedicated health endpoint
  }

  healthy_threshold   = 2
  interval            = 15
  timeout             = 5
  unhealthy_threshold = 3
}

# ------------------------------------------------------------------------------
# Origin Pool
# Points to the app server private IP, reachable via CE SLI (inside_network).
# snat_pool tells the CE to SNAT outbound connections to the app using the
# specified prefix — this makes return traffic route back through the CE.
# ------------------------------------------------------------------------------
resource "volterra_origin_pool" "app_pool" {
  name      = "app-origin-pool"
  namespace = var.f5xc_namespace_workload

  # -- Origin: app server by private IP, discovered via CE SLI --
  origin_servers {
    private_ip {
      ip = var.app_server_ip

      # CE reaches the app over its inside (SLI / eth1) network
      inside_network = true

      # Locate the origin on Site 1 first; Site 2 provides redundancy.
      # Use a virtual_site here instead if you want both CEs to be
      # active-active origins simultaneously.
      site_locator {
        site {
          name      = volterra_securemesh_site_v2.site1.name
          namespace = var.f5xc_namespace
          tenant    = var.f5xc_tenant
        }
      }

      # SNAT: CE rewrites the source IP to snat_pool_prefix before
      # forwarding to the app. This ensures the app's return traffic
      # routes back through the CE (not directly to the client).
      snat_pool {
        snat_pool {
          prefixes = [var.snat_pool_prefix]
        }
      }
    }

    labels = {}
  }

  # Add Site 2 as a second origin server for redundancy
  origin_servers {
    private_ip {
      ip             = var.app_server_ip
      inside_network = true

      site_locator {
        site {
          name      = volterra_securemesh_site_v2.site2.name
          namespace = var.f5xc_namespace
          tenant    = var.f5xc_tenant
        }
      }

      snat_pool {
        snat_pool {
          prefixes = [var.snat_pool_prefix]
        }
      }
    }

    labels = {}
  }

  # Port the app listens on
  port = var.app_server_port

  # No TLS between CE and app server (plain HTTP/TCP)
  # Change to use_tls {} if your app requires TLS upstream
  no_tls = true

  # LOCALPREFERED: prefer the origin server reachable from the same CE
  # that received the client request. Falls back to the other CE.
  endpoint_selection = "LOCALPREFERED"

  # ROUND_ROBIN across healthy origin servers
  loadbalancer_algorithm = "ROUND_ROBIN"

  healthcheck {
    name      = volterra_healthcheck.app_hc.name
    namespace = var.f5xc_namespace_workload
    tenant    = var.f5xc_tenant
  }

  depends_on = [
    volterra_securemesh_site_v2.site1,
    volterra_securemesh_site_v2.site2,
    volterra_healthcheck.app_hc,
  ]
}

# ------------------------------------------------------------------------------
# HTTP Load Balancer
#
# Advertised on SITE_LOCAL_INSIDE (SLI) of BOTH CE sites using
# advertise_custom. Clients hit the NLB VIP → CE SLI → this LB.
#
# The `ip` in advertise_custom pins the VIP to a specific address within
# the SLI subnet so the GCP NLB can forward to it predictably.
# ------------------------------------------------------------------------------
resource "volterra_http_loadbalancer" "app_lb" {
  name      = "app-http-lb"
  namespace = var.f5xc_namespace_workload

  # Domain(s) the LB responds to. Clients must send Host: <app_domain>
  # or configure a wildcard/catch-all if preferred.
  domains = [var.app_domain]

  # Plain HTTP listener (change to https {} + TLS cert for production)
  http {
    dns_volterra_managed = false
    port                 = tostring(var.app_server_port)
  }

  # -- Advertise on CE SLI (inside network) of both sites --
  # This is what makes the VIP appear on the CE's internal interface
  # so the GCP internal NLB can forward traffic to it.
  advertise_custom {
    advertise_where {
      site {
        network = "SITE_LOCAL_INSIDE" # SLI / eth1
        ip      = var.vip_address

        site {
          name      = volterra_securemesh_site_v2.site1.name
          namespace = var.f5xc_namespace
          tenant    = var.f5xc_tenant
        }
      }
      port = var.app_server_port
    }

    advertise_where {
      site {
        network = "SITE_LOCAL_INSIDE" # SLI / eth1
        ip      = var.vip_address

        site {
          name      = volterra_securemesh_site_v2.site2.name
          namespace = var.f5xc_namespace
          tenant    = var.f5xc_tenant
        }
      }
      port = var.app_server_port
    }
  }

  # -- Default route: send all traffic to the app origin pool --
  default_route_pools {
    pool {
      name      = volterra_origin_pool.app_pool.name
      namespace = var.f5xc_namespace_workload
      tenant    = var.f5xc_tenant
    }
    weight   = 1
    priority = 1
  }

  # -- No WAF for now (enable volterra_app_firewall here for production) --
  disable_waf = true

  # -- No rate limiting --
  disable_rate_limit = true

  # -- No bot defense --
  #bot_defense_regional {
  #  regional_endpoint = "US"
  #  policy {
  #    disable_bot_defense = true
  #  }
  #}

  # -- Connection/timeout settings --
  add_location                    = false
  service_policies_from_namespace = true

  depends_on = [
    volterra_origin_pool.app_pool,
    volterra_securemesh_site_v2.site1,
    volterra_securemesh_site_v2.site2,
  ]
}

# ------------------------------------------------------------------------------
# Update GCP NLB health check port to match the VIP port
# (if you changed app_server_port from the default 80, the NLB health check
# in nlb.tf stays on 65500 which is correct — it checks CE health,
# not app health. No change needed there.)
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# GCP: Static internal IP reservation for the VIP
# Pins the VIP address in the SLI subnet so it doesn't shift between applies.
# The F5XC LB advertises this IP; the GCP NLB forwards to it.
# ------------------------------------------------------------------------------
resource "google_compute_address" "vip" {
  name         = "${var.vpc_name}-ce-vip"
  address_type = "INTERNAL"
  subnetwork   = google_compute_subnetwork.site1_inside.self_link
  region       = var.gcp_region
  address      = var.vip_address
  description  = "Reserved VIP for F5XC CE application LB on SLI"
}
*/