output "fqdn" {
  description = "Public FQDN of the app — what users visit (e.g. hubble.apps.dvlab.top)."
  value       = local.fqdn
}

output "dns_record_id" {
  description = "ID of the Cloudflare DNS record. Handy for troubleshooting or for referencing in higher-level modules."
  value       = cloudflare_dns_record.app.id
}

output "access_application_id" {
  description = "ID of the Access application — null when access is disabled. Use it to attach extra policies / service tokens later."
  value       = try(cloudflare_zero_trust_access_application.app[0].id, null)
}

output "access_enabled" {
  description = "Whether Cloudflare Access is gating this app."
  value       = var.access.enabled
}
