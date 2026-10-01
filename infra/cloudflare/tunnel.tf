# --- Cloudflare Tunnel (remotely managed) ------------------------------------
# cloudflared on the VM only makes OUTBOUND connections to Cloudflare; the
# ingress rules live in Cloudflare (config_src = "cloudflare").
resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id = var.account_id
  name       = var.tunnel_name
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id

  config = {
    ingress = [
      {
        # HTTPS to the loopback nginx listener with full certificate validation
        # (Let's Encrypt cert, SAN tunnel.iforecast.es) - the tunnel equivalent
        # of Full (strict). The zone SSL mode does not apply to Tunnel traffic.
        hostname = "${var.tunnel_hostname}.${var.zone_name}"
        service  = "https://127.0.0.1:8443"
        origin_request = {
          origin_server_name = "${var.tunnel_hostname}.${var.zone_name}"
          no_tls_verify      = false
          http2_origin       = true
        }
      },
      {
        # Mandatory catch-all.
        service = "http_status:404"
      }
    ]
  }
}

# Connector token for `cloudflared service install <token>` (sensitive output).
data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
}
