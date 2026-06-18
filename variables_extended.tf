# ==============================================================================
# Additional variables for client VPC, app VPC, F5XC LB/origin
# Append these to variables.tf (or keep in a separate file)
# ==============================================================================

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

# -------------------------
#

# -------------------------
# VPC Peering (CE VPC <-> Client VPC and CE VPC <-> App VPC)
# -------------------------
variable "create_vpc_peering" {
  description = "Create GCP VPC peering between CE VPC and client/app VPCs"
  type        = bool
  default     = true
}
