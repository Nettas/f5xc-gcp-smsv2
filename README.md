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

Client VM (client VPC: 10.200.1.0/24)
  │  [VPC Peer]
  ▼
GCP Internal Pass-Through NLB (VIP: 10.100.2.x, all TCP/UDP ports)
  │  [forwards to CE SLI backends]
  ▼
CE Site 1 / CE Site 2 (SLI eth1)
  │  [F5XC HTTP LB advertised on SLI, VIP: 10.100.2.100]
  ▼
Origin Pool (LOCALPREFERED, ROUND_ROBIN)
  │  [SNAT source → 10.201.1.200/32]
  │  [VPC Peer]
  ▼
App Server (app VPC: 10.201.1.0/24, IP: 10.201.1.10, port: 80)
```

Each CE node registers as an independent F5XC `securemesh_site_v2` with:
- **`multiple_interface`** mode (Ingress/Egress Gateway)
- **`not_managed`** GCP — you manage the GCP VM; F5XC manages the software overlay
- **Cloud NAT** on SLO subnets for internet egress (no public IPs on VMs)

This is a single flat Terraform module — one state file, applied with one
`terraform apply`. All resources (VPCs, CE sites, NLB, F5XC LB) are declared
together and reference each other directly (no remote state required).

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
| GCP quota | At least 16 vCPUs free in target region for two `n2-standard-8` CE nodes |

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
| `providers.tf` | volterra + google provider config; credentials via env vars |
| `variables.tf` | Core variables: GCP project/region/AZs, VPC CIDRs, site names, instance type |
| `variables_extended.tf` | Extended variables: client VPC, app VPC, VIP, SNAT prefix, F5XC tenant, domain |
| `networking.tf` | Shared CE VPC, 4 subnets (SLO+SLI per site), Cloud NAT, firewall rules |
| `f5xc_sites.tf` | GCP cloud credentials, 2x `volterra_securemesh_site_v2`, 2x `volterra_token` |
| `compute.tf` | 2x GCP VMs (2-NIC each), cloud-init injects site token + cluster name |
| `nlb.tf` | GCP internal pass-through NLB: health check, instance groups, backend service, forwarding rule |
| `client_app_vpcs.tf` | Client VPC + App VPC + subnets + firewall rules + VPC peering (CE↔Client, CE↔App) |
| `f5xc_lb.tf` | `volterra_healthcheck`, `volterra_origin_pool`, `volterra_http_loadbalancer`, GCP static VIP reservation |
| `test_vms.tf` | Optional test VMs (`create_test_vms = true`): Debian client VM + nginx app VM |
| `outputs.tf` | All useful outputs including NLB VIP, site IPs, tokens (sensitive), traffic path summary |
| `terraform.tfvars.example` | Template tfvars — copy to `terraform.tfvars` before applying (optional if using env vars) |

---

## Deployment Steps

### 1. Set environment variables

This config can be driven entirely by environment variables instead of a
`terraform.tfvars` file. Required `TF_VAR_*` names match the variable names
in `variables.tf` / `variables_extended.tf` exactly.

```bash
# F5XC provider auth
export VOLT_API_URL="https://YOUR-TENANT.console.ves.volterra.io/api"
export VOLT_API_P12_FILE="/path/to/api-credential.p12"
export VES_P12_PASSWORD="your-p12-password"

# Required Terraform variables (no defaults set in variables.tf)
export TF_VAR_f5xc_api_url="$VOLT_API_URL"
export TF_VAR_f5xc_api_p12_file="$VOLT_API_P12_FILE"
export TF_VAR_f5xc_tenant="YOUR-TENANT"          # subdomain only, e.g. "mycompany"
export TF_VAR_gcp_project_id="your-gcp-project-id"

# GCP provider auth (separate from the F5XC cloud-credentials object)
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/sa-key.json"
export TF_VAR_gcp_service_account_key_b64=$(base64 -w0 /path/to/sa-key.json)

# Optional: turn on test VMs for end-to-end traffic validation
export TF_VAR_create_test_vms=true
```

Everything else has sane defaults (region, AZs, CIDRs, instance type, site
names) in `variables.tf` / `variables_extended.tf`. Override any of them with
additional `TF_VAR_<name>` exports, or use `terraform.tfvars` instead if you
prefer a file-based approach — copy `terraform.tfvars.example` to
`terraform.tfvars` and fill it in (then make sure it's gitignored).

### 2. Initialize and plan

```bash
terraform init
terraform plan -out=tfplan
```

### 3. Apply

```bash
terraform apply tfplan
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

## Testing End-to-End Application Traffic

Set `TF_VAR_create_test_vms=true` before applying to provision a Debian
client VM (in the client VPC) and an nginx app VM (in the app VPC, bound to
`app_server_ip`).

Once both CE sites show `Online` and `terraform apply` has finished:

```bash
# Grab the NLB VIP and app domain from outputs
terraform output nlb_vip
terraform output -raw f5xc_vip_address

# SSH into the client test VM via IAP
gcloud compute ssh client-test-vm --zone=<client_subnet_az> --tunnel-through-iap

# From inside the client VM, hit the app through the full path:
#   client → NLB VIP → CE SLI → F5XC HTTP LB → origin pool → app VM
curl -v -H "Host: app.internal.example.com" http://<nlb_vip>/
curl -v -H "Host: app.internal.example.com" http://<nlb_vip>/health
```

A successful response means traffic crossed: client VPC → VPC peering → GCP
NLB → CE SLI → F5XC HTTP LB → origin pool (SNAT'd) → app VPC → nginx. If it
fails, check in this order: CE site status in the F5XC console, NLB backend
health (`gcloud compute backend-services get-health`), and the F5XC HTTP LB
status/origin pool health in the console.

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

### Flat module vs split root modules
This repo intentionally stays a single root module with one state file.
Resources reference each other directly (e.g. `volterra_securemesh_site_v2.site1.name`
in `f5xc_lb.tf`), which is simpler to reason about and apply than splitting into
separate VPC modules wired together with `terraform_remote_state`. Revisit this
only if separate teams need to own the client VPC, app VPC, and CE VPC independently.

---

## Default CIDR Layout

| Network | CIDR | Purpose |
|---|---|---|
| CE VPC | 10.100.0.0/16 | Shared CE VPC |
| Site 1 SLO (eth0) | 10.100.1.0/24 | AZ-a outside/internet |
| Site 1 SLI (eth1) | 10.100.2.0/24 | AZ-a inside/workload |
| Site 2 SLO (eth0) | 10.100.11.0/24 | AZ-b outside/internet |
| Site 2 SLI (eth1) | 10.100.12.0/24 | AZ-b inside/workload |
| Client VPC | 10.200.1.0/24 | Client workloads |
| App VPC | 10.201.1.0/24 | Backend app servers |
| CE VIP | 10.100.2.100/32 | F5XC LB VIP on SLI |
| SNAT pool | 10.201.1.200/32 | CE SNAT source toward app |

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

---

## Production Hardening TODOs

- [ ] Add `volterra_app_firewall` resource and attach to `volterra_http_loadbalancer` for WAF
- [ ] Switch HTTP LB to HTTPS (`https {}` block + TLS cert via `volterra_certificate`)
- [ ] Enable TLS between CE and app origin (`use_tls {}` in origin pool)
- [ ] Restrict SSH firewall rules to specific management CIDRs (currently `10.0.0.0/8`)
- [ ] Add `volterra_service_policy` to restrict which clients can reach the LB
- [ ] Consider 3-node HA per site (`enable_ha = true`) for production workloads
- [ ] Add GCP Cloud Armor policy on NLB for DDoS protection
- [ ] Store state in GCS backend (`terraform { backend "gcs" {} }`)
- [ ] Pin the F5XC CE image version instead of using the `family` data source
- [ ] Add `volterra_virtual_site` spanning both CE sites for unified origin pool reference
