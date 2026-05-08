# Self-signed TLS for Zot.
# Talos clients trust it via insecureSkipVerify=true OR by passing ca_cert into
# the cluster stack's var.registry_mirror.

resource "tls_private_key" "zot" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "zot" {
  private_key_pem = tls_private_key.zot.private_key_pem

  subject {
    common_name  = local.fqdn
    organization = "home-lab"
  }

  # Cert lasts 10 years — this is a lab.
  validity_period_hours = 87600

  dns_names = [
    local.fqdn,
    var.hostname,
    "localhost",
  ]

  ip_addresses = [
    "127.0.0.1",
  ]

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}
