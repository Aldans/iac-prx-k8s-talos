# Cloudflare Tunnel (locally-managed mode).
#
# Creates:
#   1. A Tunnel resource on the Cloudflare side. config_src=local means routes
#      are managed in-cluster via config.yaml (Flux ConfigMap), not in the
#      Cloudflare dashboard.
#   2. credentials.json content (AccountTag + TunnelID + TunnelSecret) —
#      pushed into a Kubernetes Secret so the cloudflared Deployment can
#      mount it.
#   3. A ConfigMap with TUNNEL_ID for the Deployment to consume as $(TUNNEL_ID)
#      in its args — this is what keeps routes-in-Flux decoupled from the
#      tunnel resource identity.
#
# DNS records live in dns.tf.

# 32 random bytes, base64-encoded — Cloudflare uses this as the shared secret
# between the tunnel resource and the cloudflared connector.
resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id    = var.account_id
  name          = var.tunnel_name
  tunnel_secret = random_id.tunnel_secret.b64_std
  config_src    = "local"
}

# credentials.json — the exact format cloudflared expects on disk.
locals {
  credentials_json = jsonencode({
    AccountTag   = var.account_id
    TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.this.id
    TunnelSecret = random_id.tunnel_secret.b64_std
  })
}

resource "kubernetes_namespace" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.kubernetes_namespace
  }
}

# Mounted by the cloudflared Deployment at /etc/cloudflared/creds/credentials.json.
resource "kubernetes_secret" "credentials" {
  metadata {
    name      = var.credentials_secret_name
    namespace = var.kubernetes_namespace
    labels = {
      "app.kubernetes.io/name"       = "cloudflared"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "Opaque"

  data = {
    "credentials.json" = local.credentials_json
  }

  depends_on = [kubernetes_namespace.this]
}

# Consumed by the Deployment via envFrom — exposes TUNNEL_ID for the
# `cloudflared tunnel run $(TUNNEL_ID)` arg.
resource "kubernetes_config_map" "tunnel_id" {
  metadata {
    name      = var.tunnel_id_configmap_name
    namespace = var.kubernetes_namespace
    labels = {
      "app.kubernetes.io/name"       = "cloudflared"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    TUNNEL_ID = cloudflare_zero_trust_tunnel_cloudflared.this.id
  }

  depends_on = [kubernetes_namespace.this]
}
