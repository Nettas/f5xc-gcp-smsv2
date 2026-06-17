# Environment Variables Reference

This project is driven entirely by environment variables — no `terraform.tfvars`
file is required. There are three categories:

1. **Provider auth vars** — read directly by the `volterra` provider or by
   Google's auth libraries. Not Terraform variables themselves.
2. **`TF_VAR_*` required vars** — map directly to Terraform variables that have
   no default in `variables.tf` / `variables_extended.tf`. Terraform will fail
   at `plan` time if any of these are missing.
3. **`TF_VAR_*` optional overrides** — every other variable already has a
   sensible default. Only export these if you want to change a default.

---

## Quick Start — Copy, Fill In, Source

Save this as `.f5xc-env.sh` in the repo root (it's already excluded by
`.gitignore` — never commit it), fill in your real values, then run
`source .f5xc-env.sh` before any `terraform` command.

```bash
#!/usr/bin/env bash
# .f5xc-env.sh — F5XC GCP SMSv2 deployment environment
# Usage: source .f5xc-env.sh

# --- F5XC provider auth ---
export VOLT_API_URL="https://YOUR-TENANT.console.ves.volterra.io/api"
export VOLT_API_P12_FILE="/path/to/api-credential.p12"
export VES_P12_PASSWORD="your-p12-password"

# --- Required Terraform variables (no defaults in variables.tf) ---
export TF_VAR_f5xc_api_url="$VOLT_API_URL"
export TF_VAR_f5xc_api_p12_file="$VOLT_API_P12_FILE"
export TF_VAR_f5xc_tenant="YOUR-TENANT"              # subdomain only, e.g. "mycompany"
export TF_VAR_gcp_project_id="your-gcp-project-id"

# --- GCP provider auth (separate from the F5XC cloud-credentials object) ---
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/sa-key.json"
export TF_VAR_gcp_service_account_key_b64=$(base64 -w0 /path/to/sa-key.json)

# --- Optional: enable test VMs for end-to-end traffic validation ---
export TF_VAR_create_test_vms=true
```

---

## 1. Provider Auth Variables (not `TF_VAR_*`)

These are read directly by the provider or by underlying auth libraries —
they are **not** Terraform variables and setting `TF_VAR_<name>` for these
does nothing.

| Variable | Required? | Read by | Description |
|---|---|---|---|
| `VES_P12_PASSWORD` | Yes, if your P12 file is password-protected | `volterra` provider | Password for the F5XC API P12 credential file. The provider reads this directly; there is no corresponding Terraform variable. |
| `GOOGLE_APPLICATION_CREDENTIALS` | Yes | Google auth libraries (`google` provider, `gcloud`) | Path to the GCP service account JSON key file. This is how Terraform's `google` provider authenticates to GCP — separate from the F5XC cloud-credentials object below. |
| `VOLT_API_URL` | No (convenience only) | Nothing — bash only | Not read by Terraform. Exists purely so you can set it once and reuse it for `TF_VAR_f5xc_api_url` below without retyping the value. |
| `VOLT_API_P12_FILE` | No (convenience only) | Nothing — bash only | Same idea — convenience source for `TF_VAR_f5xc_api_p12_file`. |

```bash
export VES_P12_PASSWORD="your-p12-password"
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/sa-key.json"
```

---

## 2. Required `TF_VAR_*` Variables

These map directly to Terraform variables with **no default** — `terraform
plan` will prompt interactively or fail in non-interactive contexts (like CI)
if any are missing.

| Environment Variable | Terraform Variable | Type | Sensitive | Description |
|---|---|---|---|---|
| `TF_VAR_f5xc_api_url` | `f5xc_api_url` | string | No | F5XC tenant API URL, e.g. `https://mytenant.console.ves.volterra.io/api` |
| `TF_VAR_f5xc_api_p12_file` | `f5xc_api_p12_file` | string | **Yes** | Filesystem path to the F5XC API P12 credential file |
| `TF_VAR_f5xc_tenant` | `f5xc_tenant` | string | No | F5XC tenant name — just the subdomain portion of your console URL (e.g. `mycompany`, not the full URL) |
| `TF_VAR_gcp_project_id` | `gcp_project_id` | string | No | GCP project ID Terraform will deploy into |
| `TF_VAR_gcp_service_account_key_b64` | `gcp_service_account_key_b64` | string | **Yes** | Base64-encoded contents of the GCP service account JSON key. Used to build the F5XC `volterra_cloud_credentials` object (separate from `GOOGLE_APPLICATION_CREDENTIALS`, which only authenticates the `google` provider itself). |

```bash
export TF_VAR_f5xc_api_url="https://YOUR-TENANT.console.ves.volterra.io/api"
export TF_VAR_f5xc_api_p12_file="/path/to/api-credential.p12"
export TF_VAR_f5xc_tenant="YOUR-TENANT"
export TF_VAR_gcp_project_id="your-gcp-project-id"
export TF_VAR_gcp_service_account_key_b64=$(base64 -w0 /path/to/sa-key.json)
```

> **Note:** `base64 -w0` disables line-wrapping (GNU coreutils). On macOS use
> `base64 -i /path/to/sa-key.json` instead — BSD `base64` doesn't wrap by
> default, so `-w0` isn't needed (and isn't a valid flag).

---

## 3. Optional `TF_VAR_*` Overrides

Every variable below already has a default in `variables.tf` /
`variables_extended.tf`. Only export one of these if you want to change that
default — otherwise leave it alone.

### GCP region / sizing

| Environment Variable | Default | Description |
|---|---|---|
| `TF_VAR_gcp_region` | `us-central1` | GCP region for the VPC and CE sites |
| `TF_VAR_gcp_az_site1` | `us-central1-a` | AZ for Site 1 |
| `TF_VAR_gcp_az_site2` | `us-central1-b` | AZ for Site 2 |
| `TF_VAR_gcp_instance_type` | `n2-standard-8` | CE node machine type (8 vCPU/32GB; `n1-standard-4` acceptable for dev/test) |
| `TF_VAR_gcp_disk_size_gb` | `80` | Boot disk size per CE node |
| `TF_VAR_create_cloud_nat` | `true` | Create Cloud NAT for SLO subnet internet egress |

### VPC / subnet CIDRs

| Environment Variable | Default | Description |
|---|---|---|
| `TF_VAR_vpc_name` | `f5xc-ce-vpc` | Shared CE VPC name |
| `TF_VAR_vpc_cidr` | `10.100.0.0/16` | Reference-only overall CIDR (GCP allocates per-subnet) |
| `TF_VAR_site1_outside_subnet_cidr` | `10.100.1.0/24` | Site 1 SLO (eth0) subnet |
| `TF_VAR_site1_inside_subnet_cidr` | `10.100.2.0/24` | Site 1 SLI (eth1) subnet |
| `TF_VAR_site2_outside_subnet_cidr` | `10.100.11.0/24` | Site 2 SLO (eth0) subnet |
| `TF_VAR_site2_inside_subnet_cidr` | `10.100.12.0/24` | Site 2 SLI (eth1) subnet |
| `TF_VAR_client_vpc_name` | `f5xc-client-vpc` | Client-side VPC name |
| `TF_VAR_client_subnet_cidr` | `10.200.1.0/24` | Client workload subnet |
| `TF_VAR_client_subnet_az` | `us-central1-a` | Client subnet zone |
| `TF_VAR_app_vpc_name` | `f5xc-app-vpc` | Application-side VPC name |
| `TF_VAR_app_subnet_cidr` | `10.201.1.0/24` | App server subnet |
| `TF_VAR_app_subnet_az` | `us-central1-a` | App subnet zone |

### F5XC site / namespace config

| Environment Variable | Default | Description |
|---|---|---|
| `TF_VAR_f5xc_namespace` | `system` | F5XC namespace for site objects |
| `TF_VAR_f5xc_namespace_workload` | `default` | F5XC namespace for LB/origin objects |
| `TF_VAR_site1_name` | `gcp-ce-site1-az-a` | F5XC Site 1 name |
| `TF_VAR_site2_name` | `gcp-ce-site2-az-b` | F5XC Site 2 name |
| `TF_VAR_gcp_credentials_name` | `gcp-cloud-cred` | Name of the F5XC GCP cloud-credentials object |
| `TF_VAR_ssh_public_key` | `""` | SSH public key string for CE node access (optional but recommended) |
| `TF_VAR_re_region` | `""` | F5XC Regional Edge region preference; leave empty for geo-proximity |

### Application delivery

| Environment Variable | Default | Description |
|---|---|---|
| `TF_VAR_app_server_ip` | `10.201.1.10` | Private IP of the backend app server |
| `TF_VAR_app_server_port` | `80` | TCP port the app listens on |
| `TF_VAR_app_domain` | `app.internal.example.com` | Host header clients send to reach the app via the CE VIP |
| `TF_VAR_vip_address` | `10.100.2.100` | VIP advertised on CE SLI; must fall within `site1_inside_subnet_cidr` |
| `TF_VAR_snat_pool_prefix` | `10.201.1.200/32` | CIDR the CE SNATs to before forwarding to the app server |

### Toggles

| Environment Variable | Default | Description |
|---|---|---|
| `TF_VAR_create_vpc_peering` | `true` | Create VPC peering between CE VPC and client/app VPCs |
| `TF_VAR_create_test_vms` | `false` | Provision a Debian client VM + nginx app VM for end-to-end traffic validation |

### Labels (map type — needs HCL-style JSON when set via env var)

| Environment Variable | Default | Description |
|---|---|---|
| `TF_VAR_site_labels` | `{environment="production", managed-by="terraform"}` | Labels applied to F5XC site objects and GCP resources. To override via env var, use JSON syntax: `export TF_VAR_site_labels='{"environment":"staging","managed-by":"terraform"}'` |

---

## Verifying What's Set

Before running `terraform plan`, sanity-check that everything required is
actually exported in your current shell:

```bash
env | grep -E '^(TF_VAR_|VOLT_|VES_|GOOGLE_APPLICATION_CREDENTIALS)' | sort
```

Confirm at minimum these five are present and non-empty:
`TF_VAR_f5xc_api_url`, `TF_VAR_f5xc_api_p12_file`, `TF_VAR_f5xc_tenant`,
`TF_VAR_gcp_project_id`, `TF_VAR_gcp_service_account_key_b64`, plus
`GOOGLE_APPLICATION_CREDENTIALS` and `VES_P12_PASSWORD` if your P12 is
password-protected.

---

## Security Notes

- Never commit `.f5xc-env.sh`, your `.p12` file, or your service account
  JSON key — all three are already excluded by `.gitignore`.
- `TF_VAR_f5xc_api_p12_file` and `TF_VAR_gcp_service_account_key_b64` are
  marked `sensitive = true` in `variables.tf` / `f5xc_sites.tf`, so Terraform
  will redact them from `plan`/`apply` console output — but they still land
  in the Terraform **state file** in plaintext. Treat `terraform.tfstate` as
  a secret and never commit it (also already gitignored).
- If you used the embedded-token form of `git push` (token in the URL) to
  push this repo, scrub it from `~/.bash_history` — it does not apply to
  these deployment variables, but it's worth a reminder if you're reusing
  that shell session.
