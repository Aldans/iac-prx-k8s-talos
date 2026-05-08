# Secrets generated locally and baked into cloud-init.
# Outputs expose the access keys (sensitive) so the cluster stack can configure
# Terraform's S3 backend and Zot's S3 storage driver.

# Garage gossip / RPC secret. 32 hex bytes (= 64 hex chars).
resource "random_id" "garage_rpc_secret" {
  byte_length = 32
}

# Garage S3 access key for the "terraform" account (used by tfstate backend AND by Zot).
# Garage v1.0+ requires `GK` + exactly 24 hex chars ([a-f0-9]).
resource "random_id" "garage_access_key_id_suffix" {
  byte_length = 12 # 12 bytes = 24 hex chars
}

# Garage v1.0+ requires the secret to be exactly 32 hex-encoded bytes (64 hex chars).
resource "random_id" "garage_secret_access_key" {
  byte_length = 32
}

locals {
  garage_access_key_id     = "GK${random_id.garage_access_key_id_suffix.hex}"
  garage_secret_access_key = random_id.garage_secret_access_key.hex

  fqdn = "${var.hostname}.${var.dns_domain}"
}
