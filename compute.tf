# ==============================================================================
# GCP Compute Instances - F5XC CE Nodes
#
# Each instance has 2 NICs:
#   nic0 (eth0) -> SLO subnet (outside, internet-facing via Cloud NAT)
#   nic1 (eth1) -> SLI subnet (inside, workload network)
#
# Cloud-init injects the site token and cluster name so the CE self-registers
# with the F5XC console on first boot.
# ==============================================================================

# ------------------------------------------------------------------------------
# Fetch the latest F5XC CE image from GCP Marketplace
# Image family: f5xc-customer-edge (project: f5-7626-networks-public)
# ------------------------------------------------------------------------------
data "google_compute_image" "f5xc_ce" {
  project     = "f5-7626-networks-public"
  filter      = "name:f5xc-ce-crt-*"
  most_recent = true
}

# ------------------------------------------------------------------------------
# Cloud-init user-data template
# Replaces TOKEN and CLUSTER_NAME at render time
# ------------------------------------------------------------------------------
locals {
  ce_userdata_site1 = <<-USERDATA
    #cloud-config
    write_files:
      - path: /etc/hosts
        content: |
          127.0.0.1 localhost
          ::1       localhost
          127.0.1.1 vip
          169.254.169.254 metadata.google.internal
        permissions: '0644'
        owner: root

      - path: /etc/vpm/config.yaml
        permissions: '0644'
        owner: root
        content: |
          Vpm:
            ClusterType: ce
            ClusterName: ${var.site1_name}
            Token: ${volterra_token.site1_token.id}
            MauriceEndpoint: https://register.ves.volterra.io
            MauricePrivateEndpoint: https://register-tls.ves.volterra.io
            CertifiedHardwareEndpoint: https://vesio.blob.core.windows.net/releases/certified-hardware/gcp.yml
            Kubernetes:
              EtcdUseTLS: True
            Server:
              vip
            CloudProvider: disabled
  USERDATA

  ce_userdata_site2 = <<-USERDATA
    #cloud-config
    write_files:
      - path: /etc/hosts
        content: |
          127.0.0.1 localhost
          ::1       localhost
          127.0.1.1 vip
          169.254.169.254 metadata.google.internal
        permissions: '0644'
        owner: root

      - path: /etc/vpm/config.yaml
        permissions: '0644'
        owner: root
        content: |
          Vpm:
            ClusterType: ce
            ClusterName: ${var.site2_name}
            Token: ${volterra_token.site2_token.id}
            MauriceEndpoint: https://register.ves.volterra.io
            MauricePrivateEndpoint: https://register-tls.ves.volterra.io
            CertifiedHardwareEndpoint: https://vesio.blob.core.windows.net/releases/certified-hardware/gcp.yml
            Kubernetes:
              EtcdUseTLS: True
            Server:
              vip
            CloudProvider: disabled
  USERDATA
}

# ------------------------------------------------------------------------------
# CE Node - Site 1 (AZ-a)
# ------------------------------------------------------------------------------
resource "google_compute_instance" "ce_site1" {
  name         = "${var.site1_name}-node0"
  machine_type = var.gcp_instance_type
  zone         = var.gcp_az_site1

  tags = ["f5xc-ce", "f5xc-ce-sli"]

  labels = merge(var.site_labels, {
    "f5xc-site" = var.site1_name
  })

  boot_disk {
    initialize_params {
      image = data.google_compute_image.f5xc_ce.self_link
      size  = var.gcp_disk_size_gb
      type  = "pd-ssd"
    }
    auto_delete = true
  }

  # nic0 = eth0 = SLO (outside)
  # No access_config block = no ephemeral public IP; Cloud NAT handles egress
  network_interface {
    subnetwork = google_compute_subnetwork.site1_outside.self_link

    # Remove this access_config block if using Cloud NAT only (recommended)
    # Uncomment to assign a public IP directly on SLO:
    # access_config {}
  }

  # nic1 = eth1 = SLI (inside)
  network_interface {
    subnetwork = google_compute_subnetwork.site1_inside.self_link
  }

  metadata = {
    user-data          = local.ce_userdata_site1
    ssh-keys           = var.ssh_public_key != "" ? "admin:${var.ssh_public_key}" : null
    serial-port-enable = "true" # useful for initial bootstrap debugging
  }

  # Allow instance to call GCP APIs (metadata, etc.)
  service_account {
    scopes = ["cloud-platform"]
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
  }

  # CE must finish creating before we render user-data referencing its token
  depends_on = [
    volterra_token.site1_token,
    google_compute_subnetwork.site1_outside,
    google_compute_subnetwork.site1_inside,
    google_compute_router_nat.cloud_nat,
  ]

  lifecycle {
    # Prevent accidental recreation; CE re-registration is disruptive
    ignore_changes = [metadata["user-data"]]
  }
}

# ------------------------------------------------------------------------------
# CE Node - Site 2 (AZ-b)
# ------------------------------------------------------------------------------
resource "google_compute_instance" "ce_site2" {
  name         = "${var.site2_name}-node0"
  machine_type = var.gcp_instance_type
  zone         = var.gcp_az_site2

  tags = ["f5xc-ce", "f5xc-ce-sli"]

  labels = merge(var.site_labels, {
    "f5xc-site" = var.site2_name
  })

  boot_disk {
    initialize_params {
      image = data.google_compute_image.f5xc_ce.self_link
      size  = var.gcp_disk_size_gb
      type  = "pd-ssd"
    }
    auto_delete = true
  }

  # nic0 = eth0 = SLO (outside)
  network_interface {
    subnetwork = google_compute_subnetwork.site2_outside.self_link
  }

  # nic1 = eth1 = SLI (inside)
  network_interface {
    subnetwork = google_compute_subnetwork.site2_inside.self_link
  }

  metadata = {
    user-data          = local.ce_userdata_site2
    ssh-keys           = var.ssh_public_key != "" ? "admin:${var.ssh_public_key}" : null
    serial-port-enable = "true"
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
  }

  depends_on = [
    volterra_token.site2_token,
    google_compute_subnetwork.site2_outside,
    google_compute_subnetwork.site2_inside,
    google_compute_router_nat.cloud_nat,
  ]

  lifecycle {
    ignore_changes = [metadata["user-data"]]
  }
}
