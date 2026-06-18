# ==============================================================================
# F5 Distributed Cloud - GCP Cloud Credentials
# The GCP service account key is base64-encoded and passed via env var:
#   export TF_VAR_gcp_service_account_key_b64=$(base64 -w0 sa-key.json)
# ==============================================================================

variable "gcp_service_account_key_b64" {
  description = "Base64-encoded GCP service account JSON key for F5XC cloud credentials"
  type        = string
  sensitive   = true
}

resource "volterra_cloud_credentials" "gcp" {
  name        = var.gcp_credentials_name
  namespace   = "system"
  description = "GCP credentials for F5XC CE deployment"

  gcp_cred_file {
    credential_file {
      clear_secret_info {
        url = "string:///${var.gcp_service_account_key_b64}"
      }
    }
  }
}

# ==============================================================================
# Site 1 - Single-Node CE | AZ-a | 2-NIC (SLO + SLI)
# ==============================================================================
resource "volterra_securemesh_site_v2" "site1" {
  name        = var.site1_name
  namespace   = var.f5xc_namespace
  description = "F5XC CE Site 1 - GCP ${var.gcp_az_site1} - 2-NIC"

  # ---- Logging ----
  logs_streaming_disabled = true

  # ---- Services ----
  block_all_services = false

  # ---- HA: single node, no HA ----
  enable_ha = false

  # ---- Labels ----
  labels = merge(var.site_labels, {
    "ves.io/provider" = "ves-io-GCP"
    "site-az"         = var.gcp_az_site1
  })

  # ---- Regional Edge selection ----
  re_select {
    geo_proximity = true
  }

  # ---- GCP not_managed (customer-managed infra) ----
  # Use `not_managed` because we provision the GCP VM ourselves via
  # google_compute_instance. Use `managed` only for F5XC-orchestrated infra.
  gcp {
    not_managed {
      node_list {
        hostname = "${var.site1_name}-node0"

        # Interface 0 - SLO (Site Local Outside) - eth0
        interface_list {
          description      = "SLO - Site Local Outside"
          dhcp_client      = true
          mtu              = 1460
          monitor_disabled = false

          network_option {
            site_local_network = true
          }

          ethernet_interface {
            device = "eth0"
          }
        }

        # Interface 1 - SLI (Site Local Inside) - eth1
        interface_list {
          description      = "SLI - Site Local Inside"
          dhcp_client      = true
          mtu              = 1460
          monitor_disabled = false

          network_option {
            site_local_inside_network = true
          }

          ethernet_interface {
            device = "eth1"
          }
        }
      }
    }
  }

  depends_on = [volterra_cloud_credentials.gcp]
}

# ==============================================================================
# Site 2 - Single-Node CE | AZ-b | 2-NIC (SLO + SLI)
# ==============================================================================
resource "volterra_securemesh_site_v2" "site2" {
  name        = var.site2_name
  namespace   = var.f5xc_namespace
  description = "F5XC CE Site 2 - GCP ${var.gcp_az_site2} - 2-NIC"

  logs_streaming_disabled = true
  block_all_services      = false
  enable_ha               = false

  labels = merge(var.site_labels, {
    "ves.io/provider" = "ves-io-GCP"
    "site-az"         = var.gcp_az_site2
  })

  re_select {
    geo_proximity = true
  }

  gcp {
    not_managed {
      node_list {
        hostname = "${var.site2_name}-node0"

        # Interface 0 - SLO (Site Local Outside) - eth0
        interface_list {
          description      = "SLO - Site Local Outside"
          dhcp_client      = true
          mtu              = 1460
          monitor_disabled = false

          network_option {
            site_local_network = true
          }

          ethernet_interface {
            device = "eth0"
          }
        }

        # Interface 1 - SLI (Site Local Inside) - eth1
        interface_list {
          description      = "SLI - Site Local Inside"
          dhcp_client      = true
          mtu              = 1460
          monitor_disabled = false

          network_option {
            site_local_inside_network = true
          }

          ethernet_interface {
            device = "eth1"
          }
        }
      }
    }
  }

  depends_on = [volterra_cloud_credentials.gcp]
}

# ==============================================================================
# Registration Tokens
# type = 1 => Site registration token (required for not_managed deployments)
# ==============================================================================
resource "volterra_token" "site1_token" {
  name      = "${var.site1_name}-token"
  namespace = var.f5xc_namespace
  type      = 1

  site_name = volterra_securemesh_site_v2.site1.name

  depends_on = [volterra_securemesh_site_v2.site1]
}

resource "volterra_token" "site2_token" {
  name      = "${var.site2_name}-token"
  namespace = var.f5xc_namespace
  type      = 1

  site_name = volterra_securemesh_site_v2.site2.name

  depends_on = [volterra_securemesh_site_v2.site2]
}
