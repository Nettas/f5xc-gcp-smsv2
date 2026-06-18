# ==============================================================================
# Optional Test VMs
# Set create_test_vms = true in tfvars to provision these.
# Client VM: simulates a workload hitting the CE VIP
# App VM:    simulates the backend application (nginx by default)
# ==============================================================================

variable "create_test_vms" {
  description = "Create test VMs in client and app VPCs for end-to-end validation"
  type        = bool
  default     = false
}

data "google_compute_image" "debian" {
  family  = "debian-12"
  project = "debian-cloud"
}

# ------------------------------------------------------------------------------
# Client test VM
# Sits in client_subnet; runs curl/wget to hit the CE VIP
# ------------------------------------------------------------------------------
resource "google_compute_instance" "client_vm" {
  count        = var.create_test_vms ? 1 : 0
  name         = "client-test-vm"
  machine_type = "e2-micro"
  zone         = var.client_subnet_az

  tags = ["client-test"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = 20
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.client_subnet.self_link
    # No access_config = no public IP; use IAP for SSH
  }

  metadata_startup_script = <<-SCRIPT
    #!/bin/bash
    apt-get update -q
    apt-get install -y -q curl dnsutils netcat-openbsd
    echo "Client VM ready. NLB VIP: ${google_compute_forwarding_rule.ce_sli_nlb.ip_address}" \
      > /home/debian/README.txt
    # Test: curl -v http://<nlb_vip>/
  SCRIPT

  service_account {
    scopes = ["cloud-platform"]
  }

  labels = merge(var.site_labels, { role = "client-test" })

  depends_on = [
    google_compute_subnetwork.client_subnet,
    google_compute_network_peering.client_to_ce,
  ]
}

# ------------------------------------------------------------------------------
# App test VM
# Sits in app_subnet with the static IP var.app_server_ip; runs nginx
# ------------------------------------------------------------------------------
resource "google_compute_instance" "app_vm" {
  count        = var.create_test_vms ? 1 : 0
  name         = "app-test-vm"
  machine_type = "e2-micro"
  zone         = var.app_subnet_az

  tags = ["f5xc-app-server", "app-test"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.debian.self_link
      size  = 20
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.app_subnet.self_link
    network_ip = var.app_server_ip
    # No access_config = no public IP; use IAP for SSH
  }

  metadata_startup_script = <<-SCRIPT
    #!/bin/bash
    apt-get update -q
    apt-get install -y -q nginx
    # Health endpoint
    mkdir -p /var/www/html/health
    echo "OK" > /var/www/html/health/index.html
    # App page showing source IP (should be CE SNAT prefix)
    cat > /var/www/html/index.html <<EOF
    <html><body>
    <h1>App Server</h1>
    <p>Served by: $(hostname)</p>
    <p>Client source IP (SNAT'd by CE): $REMOTE_ADDR</p>
    </body></html>
    EOF
    systemctl enable nginx && systemctl start nginx
  SCRIPT

  service_account {
    scopes = ["cloud-platform"]
  }

  labels = merge(var.site_labels, { role = "app-server" })

  depends_on = [
    google_compute_subnetwork.app_subnet,
    google_compute_network_peering.app_to_ce,
  ]
}
