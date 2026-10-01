# --- Cloudflare Access (Zero Trust) ------------------------------------------
# IdPs: One-time PIN (pre-existing in the account, not managed here; its ID is referenced
# below) is the primary login method; GitHub (identity_provider.tf) is the optional SSO choice.
locals {
  otp_idp_id = "85134fd8-55cf-42d8-bb85-dbd9c0ad2806" # One-time PIN (email code)
}

# Reusable Allow policy: the owner's address + anyone with an @cloudflare.com e-mail.
resource "cloudflare_zero_trust_access_policy" "allow_owner_and_cloudflare" {
  account_id       = var.account_id
  name             = "cf-assessment-allow-owner-and-cloudflare"
  decision         = "allow"
  session_duration = var.access_session_duration

  include = concat(
    [for e in var.allowed_emails : { email = { email = e } }],
    [for d in var.allowed_email_domains : { email_domain = { domain = d } }],
  )
}

# Self-hosted app covering /secure and /secure/* on both assessment hostnames
# (tunnel.* is the one required by the assignment; origin.* mirrors it because
# the Worker is routed there too). Two destinations per host because "/secure/*"
# does not match "/secure" itself. All destinations share one AUD tag.
resource "cloudflare_zero_trust_access_application" "secure" {
  account_id                 = var.account_id
  name                       = "cf-assessment-secure"
  type                       = "self_hosted"
  domain                     = "${var.tunnel_hostname}.${var.zone_name}/secure"
  session_duration           = var.access_session_duration
  app_launcher_visible       = false
  http_only_cookie_attribute = true
  same_site_cookie_attribute = "lax"
  # Both methods are offered on the login page (no instant redirect): email One-time PIN is the
  # primary option, GitHub SSO the optional one. allowed_idps is a set in the provider (order is not
  # an input); the login page layout is decided by Cloudflare, see docs/ACCESS.md.
  allowed_idps = [
    local.otp_idp_id,
    cloudflare_zero_trust_access_identity_provider.github.id,
  ]
  auto_redirect_to_identity = false
  enable_binding_cookie     = false
  options_preflight_bypass  = false

  # Order matches what the API returns (alphabetical) to keep plans clean.
  destinations = [
    { type = "public", uri = "${var.origin_hostname}.${var.zone_name}/secure" },
    { type = "public", uri = "${var.origin_hostname}.${var.zone_name}/secure/*" },
    { type = "public", uri = "${var.tunnel_hostname}.${var.zone_name}/secure" },
    { type = "public", uri = "${var.tunnel_hostname}.${var.zone_name}/secure/*" },
  ]

  policies = [{
    id         = cloudflare_zero_trust_access_policy.allow_owner_and_cloudflare.id
    precedence = 1
  }]
}
