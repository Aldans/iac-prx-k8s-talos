terraform {
  required_version = ">= 1.10.0"

  required_providers {
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
  }
}
