# --- Rules (scoped to the two assessment hosts only) -------------------------
locals {
  assessment_hosts      = ["${var.origin_hostname}.${var.zone_name}", "${var.tunnel_hostname}.${var.zone_name}"]
  assessment_hosts_set  = "{${join(" ", [for h in local.assessment_hosts : "\"${h}\""])}}"
  assessment_hosts_expr = "(http.host in ${local.assessment_hosts_set})"
}

# Configuration Rule: SSL/TLS mode Full (strict) ONLY for the assessment hosts.
# The zone-wide SSL mode stays "full" because the existing production hosts
# (Pages projects) must not be affected. Note: this ruleset is the zone's
# http_config_settings entry point; it currently contains only this rule.
resource "cloudflare_ruleset" "config_settings" {
  zone_id = var.zone_id
  name    = "default"
  kind    = "zone"
  phase   = "http_config_settings"

  rules = [{
    description = "cf-assessment: SSL Full (strict) only for origin+tunnel hosts"
    expression  = local.assessment_hosts_expr
    action      = "set_config"
    action_parameters = {
      ssl = "strict"
    }
    enabled = true
  }]
}

# Single Redirect: HTTP -> HTTPS (301) for the assessment hosts only, instead of
# flipping the zone-wide "Always Use HTTPS" toggle.
resource "cloudflare_ruleset" "redirects" {
  zone_id = var.zone_id
  name    = "default"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [{
    description = "cf-assessment: Always HTTPS for origin+tunnel hosts"
    expression  = "(http.host in ${local.assessment_hosts_set} and not ssl)"
    action      = "redirect"
    action_parameters = {
      from_value = {
        status_code = 301
        target_url = {
          expression = "concat(\"https://\", http.host, http.request.uri)"
        }
        preserve_query_string = false
      }
    }
    enabled = true
  }]
}
