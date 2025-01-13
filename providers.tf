# This file defines the required providers for the Terraform configuration.
terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "0.69.0"
    }
    talos = {
      source = "siderolabs/talos"
      version = "0.7.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.17.0"
    }
  }
}
