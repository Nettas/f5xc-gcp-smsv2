# ==============================================================================
# Additional variables for client VPC, app VPC, F5XC LB/origin
# Append these to variables.tf (or keep in a separate file)
# ==============================================================================

# -------------------------
# F5XC Tenant (needed for origin pool site_locator)
# -------------------------
variable "f5xc_tenant" {
  description = "F5XC tenant name (the subdomain of your console URL, e.g. 'mycompany')"
  type        = string
}

variable "f5xc_namespace_workload" {
  description = "F5XC namespace for LB/origin objects (can differ from 'system')"
  type        = string
  default     = "default"
}

# -------------------------
# Client VPC
# -------------------------
variable "client_vpc_name" {
  description = "Name for the client-side GCP VPC"
  type        = string
  default     = "f5xc-client-vpc"
}

variable "client_subnet_cidr" {
  description = "Subnet CIDR for client workloads"
  type        = string
  default     = "10.200.1.0/24"
}

variable "client_subnet_az" {
  description = "Zone for the client subnet (should match or peer to CE AZs)"
  type        = string
  default     = "us-central1-a"
}

# -------------------------
# App VPC
# -------------------------
variable "app_vpc_name" {
  description = "Name for the application-side GCP VPC"
  type        = string
  default     = "f5xc-app-vpc"
}

variable "app_subnet_cidr" {
  description = "Subnet CIDR for application servers"
  type        = string
  default     = "10.201.1.0/24"
}

variable "app_subnet_az" {
  description = "Zone for the app subnet"
  type        = string
  default     = "us-central1-a"
}

variable "app_server_ip" {
  description = "Private IP of the application server (must be within app_subnet_cidr)"
  type        = string
  default     = "10.201.1.10"
}

variable "app_server_port" {
  description = "TCP port the application listens on"
  type        = number
  default     = 80
}

variable "app_domain" {
  description = "Domain/hostname clients use to reach the application via the CE VIP"
  type        = string
  default     = "app.internal.example.com"
}

# -------------------------
# VIP advertised on CE SLI
# -------------------------
variable "vip_address" {
  description = "VIP IP advertised on CE SLI for clients to reach. Must be within site1_inside_subnet_cidr."
  type        = string
  default     = "10.100.2.100"
}

# -------------------------
# SNAT pool
# CE SNATs traffic to the app VPC using IPs from the app SLI subnet range.
# The CE's SLI eth1 IP is used by default; specify a dedicated pool if needed.
# -------------------------
variable "snat_pool_prefix" {
  description = "CIDR prefix the CE uses to SNAT traffic toward the app. Should be a /32 or small range within app_subnet_cidr."
  type        = string
  default     = "10.201.1.200/32"
}

# -------------------------
# VPC Peering (CE VPC <-> Client VPC and CE VPC <-> App VPC)
# -------------------------
variable "create_vpc_peering" {
  description = "Create GCP VPC peering between CE VPC and client/app VPCs"
  type        = bool
  default     = true
}
