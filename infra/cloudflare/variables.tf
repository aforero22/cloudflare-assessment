variable "account_id" {
  description = "Cloudflare account ID that owns the zone."
  type        = string
}

variable "zone_id" {
  description = "Zone ID of iforecast.es."
  type        = string
}

variable "zone_name" {
  description = "Apex domain of the zone."
  type        = string
  default     = "iforecast.es"
}

variable "origin_ip" {
  description = "Public IPv4 of the origin VM (Azure vm-cf-origin)."
  type        = string
}

variable "origin_hostname" {
  description = "Label of the classic proxied origin hostname."
  type        = string
  default     = "origin"
}

variable "tunnel_hostname" {
  description = "Label of the Cloudflare Tunnel hostname (required by the assignment: 'tunnel')."
  type        = string
  default     = "tunnel"
}

variable "tunnel_name" {
  description = "Name of the remotely-managed Cloudflare Tunnel."
  type        = string
  default     = "cf-assessment"
}

variable "allowed_emails" {
  description = "Individual e-mail addresses allowed through Cloudflare Access on /secure."
  type        = list(string)
}

variable "allowed_email_domains" {
  description = "E-mail domains allowed through Cloudflare Access on /secure."
  type        = list(string)
  default     = ["cloudflare.com"]
}

variable "access_session_duration" {
  description = "Access session lifetime."
  type        = string
  default     = "24h"
}

variable "r2_bucket_name" {
  description = "Private R2 bucket holding the flag SVGs served by the Worker."
  type        = string
  default     = "cf-assessment-flags"
}

# Per-hostname AOP client certificate (leaf signed by our private CA) and key.
# They live OUTSIDE the repo (paths only); the key is a secret.
variable "aop_client_cert_path" {
  description = "Path to the PEM client certificate presented by Cloudflare to the origin."
  type        = string
}

variable "aop_client_key_path" {
  description = "Path to the PEM private key of that client certificate (secret, not in git)."
  type        = string
  sensitive   = true
}

variable "worker_name" {
  description = "Name of the Worker deployed by Wrangler from worker/."
  type        = string
  default     = "cf-assessment-secure"
}
