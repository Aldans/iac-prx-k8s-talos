output "tunnel_id" {
  description = "UUID of the Cloudflare Tunnel resource. Same value that the cloudflared Deployment reads via the TUNNEL_ID ConfigMap entry."
  value       = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

output "tunnel_name" {
  description = "Display name of the tunnel — useful for `cloudflared tunnel list` and the Zero Trust dashboard."
  value       = cloudflare_zero_trust_tunnel_cloudflared.this.name
}

output "tunnel_cname_target" {
  description = "Hostname any additional DNS record should point at if you want to route extra zones through the same tunnel. Format: <tunnel-id>.cfargotunnel.com."
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
}

output "zone_id" {
  description = "Cloudflare zone ID of the public domain — handy for downstream resources (Access apps, Page Rules, additional records)."
  value       = data.cloudflare_zone.this.id
}

output "credentials_secret_name" {
  description = "Name of the Kubernetes Secret that the cloudflared Deployment mounts at /etc/cloudflared/creds/credentials.json."
  value       = kubernetes_secret.credentials.metadata[0].name
}

output "tunnel_id_configmap_name" {
  description = "Name of the Kubernetes ConfigMap that exposes TUNNEL_ID to the Deployment via envFrom."
  value       = kubernetes_config_map.tunnel_id.metadata[0].name
}
