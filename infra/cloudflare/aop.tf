# --- Per-hostname Authenticated Origin Pulls ---------------------------------
# Cloudflare presents this client certificate (signed by our own private CA)
# when it connects to origin.iforecast.es. nginx requires it
# (ssl_verify_client on + ssl_client_certificate = private CA), so only THIS
# zone's proxy can talk to the origin - not other Cloudflare customers, and not
# direct-to-IP clients. Zone-level AOP stays off so no other host is affected.
resource "cloudflare_authenticated_origin_pulls_hostname_certificate" "origin" {
  zone_id     = var.zone_id
  certificate = file(var.aop_client_cert_path)
  private_key = file(var.aop_client_key_path)

  lifecycle {
    # The API never returns the private key, so after an import Terraform cannot
    # compare it; rotate by changing the files and using -replace.
    ignore_changes = [private_key, certificate]
  }
}

resource "cloudflare_authenticated_origin_pulls" "origin" {
  zone_id = var.zone_id
  config = [{
    hostname = cloudflare_dns_record.origin.name
    cert_id  = cloudflare_authenticated_origin_pulls_hostname_certificate.origin.id
    enabled  = true
  }]
}
