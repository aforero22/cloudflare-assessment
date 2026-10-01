# Federated SSO for Zero Trust (Requirement 5): GitHub OAuth app "iforecast Cloudflare Access",
# owned by the candidate's GitHub account. It is the optional login choice; the main method is the
# e-mail One-time PIN (pre-existing, not managed here), so @cloudflare.com reviewers need no GitHub account.
# The Access application lists both in allowed_idps (access.tf).
#
# The client ID is public (it appears in every GitHub authorize URL). The client secret is NOT in
# this repository: it was entered in the dashboard, the API never returns it, and Terraform ignores it.
# To rotate it, generate a new secret on GitHub and paste it in Zero Trust -> Login methods -> GitHub.
resource "cloudflare_zero_trust_access_identity_provider" "github" {
  account_id = var.account_id
  name       = "GitHub"
  type       = "github"
  config = {
    client_id = "Ov23liHGsF1STW7lSMa9"
  }

  lifecycle {
    ignore_changes = [config.client_secret]
  }
}
