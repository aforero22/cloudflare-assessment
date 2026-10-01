# --- Worker (identity page + flags from private R2) --------------------------
# Split of ownership, on purpose:
#   * Terraform owns the Worker *object* (name, workers.dev/preview URLs disabled,
#     observability) and its zone routes.
#   * Wrangler (worker/, `wrangler deploy` or the CI deploy job) owns the code
#     versions and bindings, as the assignment requires the Wrangler CLI.
# Routes are also declared in worker/wrangler.jsonc with identical values, so a
# `wrangler deploy` and a `terraform apply` converge on the same state.

resource "cloudflare_worker" "secure" {
  account_id = var.account_id
  name       = var.worker_name

  # No *.workers.dev or preview URL: the Worker must only be reachable on the
  # Access-protected routes below.
  subdomain = {
    enabled          = false
    previews_enabled = false
  }

  observability = {
    enabled            = true
    head_sampling_rate = 1
    logs = {
      enabled            = true
      head_sampling_rate = 1
      invocation_logs    = true
      persist            = true
    }
  }
}

locals {
  # Every route has a matching destination in the Access application (access.tf).
  worker_route_patterns = flatten([
    for h in local.assessment_hosts : ["${h}/secure", "${h}/secure/*"]
  ])
}

resource "cloudflare_workers_route" "secure" {
  for_each = toset(local.worker_route_patterns)

  zone_id = var.zone_id
  pattern = each.value
  script  = cloudflare_worker.secure.name
}
