# --- Adopt resources that were first created through the API -----------------
# Status: applied on 2026-10-01. 17 resources managed in Terraform (16 initial + GitHub IdP);
# kept for reproducibility of the adoption.
# These import blocks let `terraform plan/apply` take ownership of the live
# objects created on 2026-10-01 (see docs/change-log.md) instead of creating
# duplicates. After the first successful apply they are no-ops and can be removed.
# For a fresh environment, delete this file and Terraform will create everything.

import {
  to = cloudflare_dns_record.origin
  id = "${var.zone_id}/cafac84ada372ddc039d193edc3d1724"
}

import {
  to = cloudflare_dns_record.tunnel
  id = "${var.zone_id}/615b34105426877e5a6a082e0870794f"
}

import {
  to = cloudflare_ruleset.config_settings
  id = "zones/${var.zone_id}/5c135dd52cea402db74278159c1630e7"
}

import {
  to = cloudflare_ruleset.redirects
  id = "zones/${var.zone_id}/2fdef789246743c4861f84b3ac9a3ed1"
}

import {
  to = cloudflare_authenticated_origin_pulls_hostname_certificate.origin
  id = "${var.zone_id}/f9deeaa7-daec-48cf-a343-c2959f44ff63"
}

import {
  to = cloudflare_authenticated_origin_pulls.origin
  id = "${var.zone_id}/origin.iforecast.es"
}

import {
  to = cloudflare_zero_trust_tunnel_cloudflared.this
  id = "${var.account_id}/f80ec30d-28ee-4deb-b5b6-fff2dcb21cf6"
}

import {
  to = cloudflare_zero_trust_tunnel_cloudflared_config.this
  id = "${var.account_id}/f80ec30d-28ee-4deb-b5b6-fff2dcb21cf6"
}

import {
  to = cloudflare_zero_trust_access_policy.allow_owner_and_cloudflare
  id = "${var.account_id}/1262eec6-1476-41a8-9d2c-5ee099b26919"
}

import {
  to = cloudflare_zero_trust_access_application.secure
  id = "accounts/${var.account_id}/12466994-8322-407c-9c72-0fc96c4d567e"
}

import {
  to = cloudflare_r2_bucket.flags
  id = "${var.account_id}/cf-assessment-flags/default"
}

import {
  to = cloudflare_worker.secure
  id = "${var.account_id}/41d0347049724ce9a2ed79d264e67177"
}

import {
  to = cloudflare_workers_route.secure["origin.iforecast.es/secure"]
  id = "${var.zone_id}/278da6b26d504ccc8211cfb5bdfd7f2d"
}

import {
  to = cloudflare_workers_route.secure["origin.iforecast.es/secure/*"]
  id = "${var.zone_id}/b7485faf7ff4435e82d2bd398c149661"
}

import {
  to = cloudflare_workers_route.secure["tunnel.iforecast.es/secure"]
  id = "${var.zone_id}/5f6d1771c92241ad82b0512263816a59"
}

import {
  to = cloudflare_workers_route.secure["tunnel.iforecast.es/secure/*"]
  id = "${var.zone_id}/6132ac48290248dc84198751e912b1e7"
}

import {
  to = cloudflare_zero_trust_access_identity_provider.github
  id = "accounts/${var.account_id}/bed3561d-2c26-4e60-b5a3-01c0dde988f4"
}
