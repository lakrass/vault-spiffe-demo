terraform {
  required_version = ">= 1.5.0"

  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "~> 3.5"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.13.0"
    }
  }
}

variable "vault_address" {
  description = "Vault API address reachable from the machine running Terraform."
  type        = string
  default     = "http://localhost:8200"
}

provider "vault" {
  address = var.vault_address
}

locals {
  trust_domain = "example.org"
  jwt_audience = "vault"
  workloads = {
    x509-demo = "ns/default/sa/x509-demo"
    jwt-demo  = "ns/default/sa/jwt-demo"
  }
}
