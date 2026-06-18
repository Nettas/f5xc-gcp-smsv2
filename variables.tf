# ==============================================================================
# F5 Distributed Cloud - GCP SMSv2 Customer Edge
# 2x Single-Node Sites | 2-NIC (SLO + SLI) | Single VPC | 2 AZs
# ==============================================================================

# -------------------------
# F5XC Tenant / API
# -------------------------
variable "f5xc_api_url" {
  description = "F5XC tenant API URL, e.g. https://mytenant.console.ves.volterra.io/api"
  type        = string
}

variable "f5xc_api_p12_file" {
  description = "Path to the F5XC API P12 credential file"
  type        = string
  sensitive   = true
}

# -------------------------
# GCP
# -------------------------
variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for the VPC and CE sites"
  type        = string
  default     = "us-central1"
}

variable "gcp_az_site1" {
  description = "GCP availability zone for Site 1 (must be in gcp_region)"
  type        = string
  default     = "us-central1-a"
}

variable "gcp_az_site2" {
  description = "GCP availability zone for Site 2 (must be in gcp_region)"
  type        = string
  default     = "us-central1-b"
}

variable "gcp_instance_type" {
  description = "GCP machine type for CE nodes"
  type        = string
  default     = "n2-standard-8"
  # Minimum recommended for production: n2-standard-8
  # Acceptable: n1-standard-4 (dev/test only)
}

variable "gcp_disk_size_gb" {
  description = "Boot disk size in GB for each CE node"
  type        = number
  default     = 80
}

# -------------------------
# Networking - VPC
# -------------------------
variable "vpc_name" {
  description = "Name of the shared GCP VPC"
  type        = string
  default     = "f5xc-ce-vpc"
}

variable "vpc_cidr" {
  description = "Overall VPC CIDR for reference (GCP uses per-subnet CIDRs)"
  type        = string
  default     = "10.100.0.0/16"
}

# Site 1 subnets (AZ-a)
variable "site1_outside_subnet_cidr" {
  description = "SLO (outside) subnet CIDR for Site 1"
  type        = string
  default     = "10.100.1.0/24"
}

variable "site1_inside_subnet_cidr" {
  description = "SLI (inside) subnet CIDR for Site 1"
  type        = string
  default     = "10.100.2.0/24"
}

# Site 2 subnets (AZ-b)
variable "site2_outside_subnet_cidr" {
  description = "SLO (outside) subnet CIDR for Site 2"
  type        = string
  default     = "10.100.11.0/24"
}

variable "site2_inside_subnet_cidr" {
  description = "SLI (inside) subnet CIDR for Site 2"
  type        = string
  default     = "10.100.12.0/24"
}

# -------------------------
# F5XC Site Config
# -------------------------
variable "f5xc_namespace" {
  description = "F5XC namespace for site objects (use 'system' for CE sites)"
  type        = string
  default     = "system"
}

variable "site1_name" {
  description = "F5XC site name for Site 1"
  type        = string
  default     = "gcp-ce-site1-az-a"
}

variable "site2_name" {
  description = "F5XC site name for Site 2"
  type        = string
  default     = "gcp-ce-site2-az-b"
}

variable "gcp_credentials_name" {
  description = "Name of the F5XC GCP Cloud Credentials object"
  type        = string
  default     = "gcp-cloud-cred"
}

variable "ssh_public_key" {
  description = "SSH public key for CE node access"
  type        = string
  default     = ""
}

variable "site_labels" {
  description = "Labels to apply to the F5XC CE site objects"
  type        = map(string)
  default = {
    "environment" = "production"
    "managed-by"  = "terraform"
  }
}

variable "re_region" {
  description = "F5XC Regional Edge region preference (e.g. us-east-1). Leave empty for geo-proximity."
  type        = string
  default     = ""
}

# -------------------------
# Optional: Cloud NAT / Internet
# -------------------------
variable "create_cloud_nat" {
  description = "Create Cloud NAT for SLO subnets (required if no public IPs on CE)"
  type        = bool
  default     = true
}

variable "ssh_public_key" {
  description = "SSH public key for CE node access"
  type        = string
  default     = ""
}