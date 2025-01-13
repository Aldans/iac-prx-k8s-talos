provider "proxmox" {
  endpoint = var.prx.endpoint
  api_token = var.prx.api_token
  insecure = true
  ssh {
    agent    = true
    username = var.prx.username
    password = var.prx.password
  }
}
