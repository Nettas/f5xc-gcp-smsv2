# F5 Distributed Cloud — GCP SMSv2 Customer Edge
## 2x Single-Node CE Sites | 2-NIC | Single VPC | 2 Availability Zones

---

## Architecture

```
GCP Region (e.g. us-central1)
└── Shared VPC: f5xc-ce-vpc
    │
    ├── AZ-a (us-central1-a)  ─── Site 1 CE Node (2-NIC)
    │   ├── SLO subnet: 10.100.1.0/24   (eth0 - outside, internet via Cloud NAT)
    │   └── SLI subnet: 10.100.2.0/24   (eth1 - inside, workload traffic)
    │
    └── AZ-b (us-central1-b)  ─── Site 2 CE Node (2-NIC)
        ├── SLO subnet: 10.100.11.0/24  (eth0 - outside, internet via Cloud NAT)
        └── SLI subnet: 10.100.12.0/24  (eth1 - inside, workload traffic)
```

Each CE node registers as an independent F5XC `securemesh_site_v2` with:
- **`multiple_interface`** mode (Ingress/Egress Gateway)
- **`not_managed`** GCP — you manage the GCP VM; F5XC manages the software overlay
- **Cloud NAT** on SLO subnets for internet egress (no public IPs on VMs)

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Terraform >= 1.3 | `terraform version` |
| F5XC Tenant account | With CE deployment permissions |
| F5XC API P12 credential | Download from F5XC Console → Administration → Credentials |
| GCP project | With Compute Engine API enabled |
| GCP Service Account | Roles: `Compute Admin`, `Service Account User` |
| GCP image access | `f5-7626-networks-public/f5xc-customer-edge` — accept Marketplace terms |

### Accept GCP Marketplace Terms
```bash
gcloud compute images list --project f5-7626-networks-public --no-standard-images
# Accept terms if required:
gcloud compute images describe f5xc-customer-edge \
  --project=f5-7626-networks-public
```

---

## Files

| File | Purpose |
|---|---|
| `providers.tf` | Volterra + Google provider config |
| `variables.tf` | All input variables with defaults |
| `networking.tf` | VPC, subnets, firewall rules, Cloud NAT |
| `f5xc_sites.tf` | GCP cloud credentials, SMSv2 site objects, tokens |
| `compute.tf` | GCP VM instances with 2-NIC and cloud-init |
| `outputs.tf` | Useful outputs (IPs, site names, tokens) |
| `terraform.tfvars.example` | Template — copy to `terraform.tfvars` and fill in |

---

## Deployment Steps

### 1. Set environment variables
```bash
# F5XC credentials
export VOLT_API_URL="https://YOUR-TENANT.console.ves.volterra.io/api"
export VOLT_API_P12_FILE="/path/to/api-credential.p12"
export VES_P12_PASSWORD="your-p12-password"

# GCP service account key (base64 encoded) for F5XC cloud credentials
export TF_VAR_gcp_service_account_key_b64=$(base64 -w0 /path/to/sa-key.json)

# GCP application credentials (for Terraform google provider)
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/sa-key.json"
```

### 2. Configure variables
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 3. Initialize and apply
```bash
terraform init
terraform plan
terraform apply
```

### 4. Verify CE registration
After `apply` completes, the CE VMs will boot and self-register (~5-10 mins):

1. Log into F5XC Console
2. Navigate to **Multi-Cloud Network Connect → Overview → Sites**
3. Both sites should transition: `Waiting for Registration` → `Online`

---

## Post-Deployment: Accept Registration (if required)

For `not_managed` sites, you may need to manually approve the node registration:

1. Console → **Manage → Site Management → Registrations**
2. Accept the pending registration for each node
3. Set **Cluster Name** to match your `site1_name` / `site2_name` variables

---

## Key Design Decisions

### `not_managed` vs `managed`
- **`not_managed`**: You provision the GCP VM. F5XC manages the CE software overlay. Full control over VM sizing, placement, disk, networking.
- **`managed`**: F5XC orchestrates the entire GCP infrastructure including VMs. Less control but fully automated.

This config uses `not_managed` for maximum flexibility.

### 2-NIC (`multiple_interface`) vs 1-NIC (`single_interface`)
- **2-NIC**: eth0=SLO (outside/internet), eth1=SLI (inside/workload). Required for Ingress/Egress Gateway use cases.
- **1-NIC**: eth0=SLO only. Ingress gateway only. **GCP does not allow adding NICs after VM creation** — choose 2-NIC from the start.

### Cloud NAT
Cloud NAT provides internet egress on the SLO subnet without public IPs on CE nodes. This is the recommended GCP pattern for production deployments.

---

## Firewall Ports Reference

| Port | Protocol | Direction | Purpose |
|---|---|---|---|
| 443 | TCP | Egress | HTTPS control plane to RE |
| 4500 | UDP | Egress | IPsec tunnel to RE |
| 53 | TCP/UDP | Egress | DNS |
| 6080 | UDP | Intra-node | CE cluster communication |
| ICMP | — | Intra-node | Health checks |
| 22 | TCP | Ingress | SSH management (restrict!) |

---

## Teardown

```bash
terraform destroy
```

Note: Destroying the F5XC site objects in the console (`volterra_securemesh_site_v2`) will
also destroy the GCP VMs. If you want to preserve the GCP resources, remove the
`volterra_securemesh_site_v2` resources from state first:

```bash
terraform state rm volterra_securemesh_site_v2.site1
terraform state rm volterra_securemesh_site_v2.site2
```
