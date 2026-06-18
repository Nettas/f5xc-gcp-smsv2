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
  │  [F5XC load balancer and origin pool configured manually via F5XC Console]
  ▼
App Server (app VPC: 10.201.1.0/24)
```

Each CE node registers as an independent F5XC `securemesh_site_v2` with:
- **`not_managed`** GCP — you manage the GCP VM; F5XC manages the software overlay
- **2-NIC** — eth0=SLO (outside/internet), eth1=SLI (inside/workload)
- **Cloud NAT** on SLO subnets for internet egress (no public IPs on VMs)

This is a single flat Terraform module — one state file, applied with one
`terraform apply`. All GCP and F5XC site resources are declared together and
reference each other directly (no remote state required).

F5XC application delivery objects (HTTP/TCP load balancers, origin pools,
health checks) are configured manually via the F5XC Console after the CE
infrastructure is deployed and both sites show `Online`.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Terraform >= 1.3 | `terraform version` |
| F5XC Tenant account | With CE deployment permissions |
| F5XC API P12 credential | Download from F5XC Console → Administration → Credentials |
| GCP project | With Compute Engine API enabled |
| GCP Service Account | See IAM section below for required permissions |
| GCP image access | `f5-7626-networks-public/f5xc-ce-crt-20251001-byol` — accept Marketplace terms |
| GCP quota | At least 16 vCPUs free in target region for two `n2-standard-8` CE nodes |

### Accept GCP Marketplace Terms

Before applying, verify Marketplace terms are accepted in your deployment project:

```bash
# Probe terms acceptance — creates and immediately deletes a tiny VM using the CE image
gcloud compute instances create license-check-tmp \
  --project=<your-gcp-project-id> \
  --zone=us-central1-a \
  --machine-type=e2-micro \
  --image=f5xc-ce-crt-20251001-byol \
  --image-project=f5-7626-networks-public \
  --no-address

# If it succeeds, delete it immediately
gcloud compute instances delete license-check-tmp \
  --zone=us-central1-a \
  --project=<your-gcp-project-id>
```

If the create fails with a terms/licensing error, accept the terms via the
GCP Marketplace listing before proceeding.

### GCP IAM — Required Permissions

The service account used by Terraform needs the following permissions (beyond
basic Compute Engine access) that are not always included in standard roles:

- `compute.networks.addPeering` / `removePeering` / `updatePeering`
- `compute.addresses.createInternal` / `deleteInternal`
- `compute.routers.create` / `delete` / `update`
- `compute.instanceGroups.update` / `delete`

If using a custom IAM role, add these explicitly. `roles/compute.admin` covers
all of them if you prefer a predefined role.

---

## Files

| File | Purpose |
|---|---|
| `providers.tf` | volterra + google provider config; credentials via env vars |
| `variables.tf` | Core variables: GCP project/region/AZs, VPC CIDRs, site names, instance type |
| `variables_extended.tf` | Extended variables: client VPC, app VPC, app server config |
| `networking.tf` | Shared CE VPC, 4 subnets (SLO+SLI per site), Cloud NAT, firewall rules |
| `f5xc_sites.tf` | GCP cloud credentials, 2x `volterra_securemesh_site_v2`, 2x `volterra_token` |
| `compute.tf` | 2x GCP VMs (2-NIC each), cloud-init injects site token via `/etc/vpm/user_data` |
| `nlb.tf` | GCP internal pass-through NLB: health check (TCP 65500), instance groups, backend service, forwarding rule |
| `client_app_vpcs.tf` | Client VPC + App VPC + subnets + firewall rules + VPC peering (CE↔Client, CE↔App) |
| `test_vms.tf` | Optional test VMs (`create_test_vms = true`): Debian client VM + nginx app VM |
| `outputs.tf` | Useful outputs: NLB VIP, site IPs, registration tokens (sensitive) |
| `terraform.tfvars.example` | Template tfvars — copy to `terraform.tfvars` before applying (optional if using env vars) |

---

## Deployment Steps

### 1. Set environment variables

Source `.f5xc-env.sh` before every Terraform session — environment variables
do not persist across shell sessions:

```bash
source .f5xc-env.sh
```

The file sets the following (fill in your values):

```bash
#!/usr/bin/env bash
# .f5xc-env.sh — gitignored, never commit this file

# F5XC provider auth
export VOLT_API_URL="https://YOUR-TENANT.console.ves.volterra.io/api"
export VOLT_API_P12_FILE="$HOME/path/to/api-credential.p12"
export VES_P12_PASSWORD="your-p12-password"

# Required Terraform variables
export TF_VAR_f5xc_api_url="$VOLT_API_URL"
export TF_VAR_f5xc_api_p12_file="$VOLT_API_P12_FILE"
export TF_VAR_gcp_project_id="your-gcp-project-id"

# GCP provider auth
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/path/to/sa-key.json"
export TF_VAR_gcp_service_account_key_b64=$(base64 -w0 "$HOME/path/to/sa-key.json")

# Optional: provision test VMs for traffic validation
# export TF_VAR_create_test_vms=true
```

Verify everything is set before running Terraform:

```bash
env | grep -E '^(TF_VAR_|VOLT_|VES_|GOOGLE_)' | sort
```

### 2. Set SSH public key

The SSH public key for CE node access is set in `terraform.tfvars` (gitignored):

```hcl
ssh_public_key = "ssh-ed25519 AAAA... your-key"
```

Connect to CE nodes post-deployment using:

```bash
ssh -i ~/.ssh/your-private-key admin@<ce-slo-or-sli-ip>
```

### 3. Initialize and plan

```bash
terraform init
terraform plan -out=tfplan
```

### 4. Apply

```bash
terraform apply "tfplan"
```

### 5. Verify CE registration

After `apply` completes, CE VMs boot and self-register (~5–10 mins):

1. Log into F5XC Console
2. Navigate to **Multi-Cloud Network Connect → Overview → Sites**
3. Both sites transition: `Waiting for Registration` → `Provisioning` → `Online`

If either site stalls at `Waiting for Registration`, check:

```bash
# Verify the token was written correctly on the CE node
ssh -i ~/.ssh/your-key admin@<ce-slo-ip>
cat /etc/vpm/user_data
```

The file should contain only:
```
token: <token-value>
```

---

## Post-Deployment: Configure F5XC Application Delivery

F5XC load balancers, origin pools, and health checks are configured manually
via the F5XC Console after both CE sites show `Online`. Terraform manages the
CE site infrastructure only.

Typical post-deployment configuration in the console:

1. **Health Check** — Multi-Cloud App Connect → Manage → Health Checks
2. **Origin Pool** — Multi-Cloud App Connect → Manage → Origin Pools
   - Use `private_ip` origin type with `inside_network = true`
   - Locate origin on CE site(s) via site locator
3. **HTTP or TCP Load Balancer** — Multi-Cloud App Connect → Manage → Load Balancers
   - Advertise on `SITE_LOCAL_INSIDE` of both CE sites
   - Target the origin pool created above

The NLB VIP is the entry point for client traffic:

```bash
terraform output nlb_vip
```

Clients in the client VPC send traffic to this VIP → NLB → CE SLI → F5XC LB.

---

## Testing with Optional Test VMs

Set `TF_VAR_create_test_vms=true` (or add `create_test_vms = true` to
`terraform.tfvars`) to provision a Debian client VM and an nginx app VM for
end-to-end validation.

```bash
# SSH into the client VM via IAP
gcloud compute ssh client-test-vm \
  --zone=us-central1-a \
  --tunnel-through-iap \
  --project=<your-gcp-project-id>

# From inside the client VM, hit the NLB VIP
curl -v http://<nlb_vip>/
```

The app VM runs nginx and has a `/health` endpoint at `http://<app-vm-ip>/health`.
SSH into it via IAP:

```bash
gcloud compute ssh app-test-vm \
  --zone=us-central1-a \
  --tunnel-through-iap \
  --project=<your-gcp-project-id>
```

---

## Key Design Decisions

### `not_managed` vs `managed`
- **`not_managed`**: You provision the GCP VM. F5XC manages the CE software overlay. Full control over VM sizing, placement, disk, networking.
- **`managed`**: F5XC orchestrates the entire GCP infrastructure including VMs. Less control but fully automated.

This config uses `not_managed` for maximum flexibility.

### 2-NIC layout
eth0=SLO (outside/internet), eth1=SLI (inside/workload). Required for
Ingress/Egress Gateway use cases. GCP does not allow adding NICs after VM
creation — choose 2-NIC from the start.

### Cloud NAT
Cloud NAT provides internet egress on the SLO subnet without public IPs on CE
nodes. This is the recommended GCP pattern for production deployments.

### CE registration token delivery
Registration tokens are generated by the `volterra_token` Terraform resource
(one per site, bound to the site object via `site_name`) and injected into each
CE VM via cloud-init, writing to `/etc/vpm/user_data` with the format:

```yaml
token: <token-value>
```

This is the current F5XC-documented format for `not_managed` SMSv2 deployments.
The older `/etc/vpm/config.yaml` format with `ClusterName`, `MauriceEndpoint`,
etc. is not used.

### Flat module
Single root module, one state file. Resources reference each other directly —
no `terraform_remote_state` required. Revisit only if separate teams need to
own the client VPC, app VPC, and CE VPC independently.

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

---

## Firewall Ports Reference

| Port | Protocol | Direction | Purpose |
|---|---|---|---|
| 443 | TCP | Egress | HTTPS control plane to RE |
| 4500 | UDP | Egress | IPsec tunnel to RE |
| 53 | TCP/UDP | Egress | DNS |
| 6080 | UDP | Intra-node | CE cluster communication |
| ICMP | — | Intra-node | Health checks |
| 65500 | TCP | Ingress | NLB health check probe on CE SLI |
| 22 | TCP | Ingress | SSH management (restrict to management CIDRs in production) |

---

## Teardown

```bash
terraform destroy
```

If you want to preserve GCP resources but remove the F5XC site objects:

```bash
terraform state rm volterra_securemesh_site_v2.site1
terraform state rm volterra_securemesh_site_v2.site2
terraform destroy
```

---

## Production Hardening TODOs

- [ ] Pin the volterra provider version in `providers.tf` (currently `>= 0.11.30`) to prevent schema drift on `terraform init -upgrade`
- [ ] Restrict SSH firewall rules to specific management CIDRs (currently `10.0.0.0/8`)
- [ ] Consider 3-node HA per site (`enable_ha = true`) for production workloads
- [ ] Add GCP Cloud Armor policy on NLB for DDoS protection
- [ ] Store Terraform state in GCS backend (`terraform { backend "gcs" {} }`)
- [ ] Add `volterra_service_policy` in F5XC Console to restrict which clients can reach the LB
- [ ] Add `volterra_app_firewall` (WAF) and attach to load balancer in F5XC Console
- [ ] Enable HTTPS on load balancer (TLS cert via `volterra_certificate`) in F5XC Console
- [ ] Enable TLS between CE and app origin in F5XC Console origin pool config
- [ ] Add `volterra_virtual_site` spanning both CE sites for unified origin pool reference
