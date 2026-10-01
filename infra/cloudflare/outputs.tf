output "tunnel_id" {
  description = "Cloudflare Tunnel UUID."
  value       = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

output "tunnel_cname_target" {
  value = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
}

output "tunnel_token" {
  description = "Connector token for `cloudflared service install`. Sensitive."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.this.token
  sensitive   = true
}

output "access_app_aud" {
  description = "Access application AUD tag (Worker POLICY_AUD)."
  value       = cloudflare_zero_trust_access_application.secure.aud
}

output "access_team_domain" {
  value = "https://iforecast.cloudflareaccess.com"
}

output "aop_certificate_id" {
  value = cloudflare_authenticated_origin_pulls_hostname_certificate.origin.id
}

output "r2_bucket" {
  value = cloudflare_r2_bucket.flags.name
}

output "worker_routes" {
  value = sort(local.worker_route_patterns)
}
