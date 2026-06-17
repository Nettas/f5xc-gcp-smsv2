terraform {
  required_version = ">= 1.3.0"

  required_providers {
    volterra = {
      source  = "volterraedge/volterra"
      version = ">= 0.11.30"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
  }
}

# ---------------------------------------------------------------------------
# F5 Distributed Cloud Provider
# Credentials are sourced from environment variables:
#   export VOLT_API_URL="https://<tenant>.console.ves.volterra.io/api"
#   export VOLT_API_P12_FILE="/path/to/api-creds.p12"
#   export VES_P12_PASSWORD="<p12-password>"
# ---------------------------------------------------------------------------
provider "volterra" {
  api_p12_file = var.f5xc_api_p12_file
  url          = var.f5xc_api_url
  timeout      = "120s"
}

# ---------------------------------------------------------------------------
# Google Cloud Provider
# Credentials sourced from GOOGLE_APPLICATION_CREDENTIALS or gcloud auth
# ---------------------------------------------------------------------------
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}
