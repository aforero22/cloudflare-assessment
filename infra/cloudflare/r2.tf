# --- R2 ----------------------------------------------------------------------
# Private bucket: no r2.dev public URL and no custom domain. Objects are only
# reachable through the Worker's R2 binding (behind Cloudflare Access).
# Objects (flags/<cc>.svg) are uploaded with wrangler, not Terraform (see README).
resource "cloudflare_r2_bucket" "flags" {
  account_id = var.account_id
  name       = var.r2_bucket_name
  location   = "wnam"
}
