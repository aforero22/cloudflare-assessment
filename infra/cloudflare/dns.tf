# --- DNS ---------------------------------------------------------------------
# Only two NEW records are managed here. Existing production records (apex, www,
# cashflow, trazavolt, _domainconnect, MX/TXT) are intentionally NOT in Terraform
# so that this stack can never modify or delete them.

# Classic reverse-proxy path: orange-clouded A record to the VM. Visitors only
# ever see Cloudflare anycast IPs.
resource "cloudflare_dns_record" "origin" {
  zone_id = var.zone_id
  name    = "${var.origin_hostname}.${var.zone_name}"
  type    = "A"
  content = var.origin_ip
  proxied = true
  ttl     = 1 # 1 = automatic (required for proxied records)
  comment = "cf-assessment origin (managed by infra/cloudflare)"
}

# Tunnel path: proxied CNAME to the tunnel's cfargotunnel.com name.
resource "cloudflare_dns_record" "tunnel" {
  zone_id = var.zone_id
  name    = "${var.tunnel_hostname}.${var.zone_name}"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "cf-assessment tunnel (managed by infra/cloudflare)"
}
