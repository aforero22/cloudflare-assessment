# Terraform + Cloudflare provider pinning.
# Authentication: the provider reads CLOUDFLARE_API_TOKEN from the environment
# at run time. The token is NEVER stored in this repository or in tfvars.
terraform {
  required_version = ">= 1.6.0"

  # Local state (git-ignored). The path can be moved outside the repo with
  #   terraform init -backend-config="path=/secure/location/terraform.tfstate"
  # Production: use an encrypted remote backend with locking instead (e.g. an
  # access-restricted R2/S3 bucket or Terraform Cloud), because state contains
  # secrets (tunnel token, AOP private key).
  backend "local" {}
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.26"
    }
  }
}

provider "cloudflare" {}
