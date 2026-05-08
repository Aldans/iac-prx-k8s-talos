terraform {
  # 1.10.0+ for native S3-backend locking (use_lockfile = true), used when the
  # state lives in Garage/MinIO/S3 — see storage_bootstrap/.
  required_version = ">= 1.10.0"

  # Empty backend block: real values come via `terraform init -backend-config=backend.s3.hcl`.
  # If backend.s3.hcl is absent, Terraform falls back to the local state file.
  backend "s3" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.69.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.7.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "~> 1.8"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.12"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "proxmox" {
  endpoint  = var.prx.endpoint
  api_token = var.prx.api_token
  insecure  = true
  ssh {
    agent    = true
    username = var.prx.username
    password = var.prx.password
  }
}

provider "kubernetes" {
  config_path = local_file.kubeconfig.filename
}

provider "helm" {
  kubernetes = {
    config_path = local_file.kubeconfig.filename
  }
}

provider "github" {
  owner = var.github_owner
  token = var.github_token
}

provider "flux" {
  kubernetes = {
    config_path = local_file.kubeconfig.filename
  }
  git = {
    url    = "ssh://git@github.com/${var.github_owner}/${var.github_repo}.git"
    branch = var.flux_branch
    ssh = {
      username    = "git"
      private_key = module.flux_bootstrap.private_key_pem
    }
  }
}
