# Cloudflare configuration — iforecast.es (assessment resources)

This folder documents, and codifies in Terraform, every Cloudflare resource created for the
Application Services assessment on the existing zone **iforecast.es** (zone plan **Free**): DNS,
Configuration and Redirect rules, per-hostname AOP, Tunnel, Access policy and application, R2 bucket,
and the Worker object and routes. Worker code, versions and bindings are deployed with Wrangler from
[`worker/`](../../worker).

> **Production safety.** The zone already serves production traffic (apex, `www`, `cashflow`,
> `trazavolt`, `_domainconnect`, Zoho MX/TXT/DKIM/DMARC). Nothing here touches those records or any
> zone-wide setting: the zone SSL mode stays **Full**, zone-level Authenticated Origin Pulls stays
> **off**, and every rule is scoped by an `http.host in {...}` expression to the two assessment hosts.
> Every API change is logged in [`docs/change-log.md`](../../docs/change-log.md).

## Architecture

```
                         Cloudflare edge (zone iforecast.es)
Visitor ─HTTPS─▶ origin.iforecast.es  (A, proxied)  ── Config Rule: SSL Full (strict)
                 │                                      + per-hostname AOP client cert
                 └────────HTTPS :443 (only Cloudflare IPs: Azure NSG + ufw)──────────▶ nginx :443
                                                                                     │ ssl_verify_client on (private CA)
                                                                                     │ LE cert (non-Cloudflare)
Visitor ─HTTPS─▶ tunnel.iforecast.es  (CNAME → <tunnel>.cfargotunnel.com, proxied)   ▼
                 ├─ /secure, /secure/*  → Cloudflare Access (One-time PIN, main / GitHub SSO, optional) → Worker (code deployed by Wrangler from worker/)
                 └─ everything else → Cloudflare Tunnel ◀── outbound QUIC ── cloudflared (VM)
                                                                              └─▶ nginx 127.0.0.1:8443 (LE cert, SNI tunnel.iforecast.es)
                                                                                         └─▶ echo-headers app 127.0.0.1:8080
```

Origin VM: Azure `vm-cf-origin`, Ubuntu 24.04, `68.221.177.94`. Provisioning is code too:
[`infra/origin/provision.sh`](../origin/provision.sh) + [`origin/`](../../origin) (app, systemd unit, nginx site).

## Resources and why

| # | Resource | Identifier | Why |
|---|---|---|---|
| 1 | Origin app (VM) | `headers-app.service` on `127.0.0.1:8080` | Step 1: returns **all request headers** in the body (pretty JSON; `?format=text` for plain text). Python stdlib only, hardened systemd sandbox, never bound to a public interface. |
| 2 | DNS `A origin.iforecast.es → 68.221.177.94` (proxied) | record `cafac84ada372ddc039d193edc3d1724` | Step 2: classic reverse proxy through Cloudflare; the public only sees Cloudflare anycast IPs. |
| 3 | Let's Encrypt certificate (ECDSA P-256) | SAN `origin.iforecast.es`, `tunnel.iforecast.es`; issuer LE `YE2`; expires 2026-12-30 | Step 3: a **non-Cloudflare** publicly trusted cert, so Cloudflare can validate the origin in Full (strict). Issued with acme.sh DNS-01 via the Cloudflare API (no port 80 needed). |
| 4 | Configuration Rule (phase `http_config_settings`) | ruleset `5c135dd52cea402db74278159c1630e7`, rule `75dccd55126c4c78a0135ba8a2f0b23c` | Step 3: **SSL = Full (strict)** only for `origin` and `tunnel`. The zone default remains `full` so the production Pages hosts are unaffected. |
| 5 | Single Redirect rule (phase `http_request_dynamic_redirect`) | ruleset `2fdef789246743c4861f84b3ac9a3ed1` | HTTP→HTTPS 301 for the two hosts only (instead of the zone-wide *Always Use HTTPS* toggle). |
| 6 | Per-hostname Authenticated Origin Pulls | cert `f9deeaa7-daec-48cf-a343-c2959f44ff63` (private CA, ECDSA, expires 2027-10-01) associated with `origin.iforecast.es` | Step 6 (no bypass): Cloudflare presents **our own** client certificate; nginx rejects any TLS client without it (`400 No required SSL certificate was sent`). Unlike the shared Cloudflare AOP CA, this also blocks traffic proxied by *other* Cloudflare accounts. Zone-level AOP stays off. |
| 7 | nginx hardening | `origin/nginx/cf-assessment.conf` | `default_server` with `ssl_reject_handshake on` (raw-IP / unknown SNI gets a TLS alert), TLS 1.2/1.3 only, AOP enforced on 443, separate loopback 8443 listener for cloudflared (no mTLS: AOP does not apply to Tunnel). |
| 8 | Firewall | Azure NSG + ufw | 443 only from Cloudflare IPv4/IPv6 ranges; 22 only from the admin IP; port 80 closed. |
| 9 | Cloudflare Tunnel `cf-assessment` (remotely managed) | `f80ec30d-28ee-4deb-b5b6-fff2dcb21cf6` | Step 4: `cloudflared` (official apt repo, systemd) dials out to Cloudflare — no inbound port needed for this path. Ingress `tunnel.iforecast.es → https://127.0.0.1:8443` with `originServerName: tunnel.iforecast.es`, `noTLSVerify: false` (the tunnel equivalent of Full strict, validating the LE cert); catch-all `http_status:404`. |
| 10 | DNS `CNAME tunnel → f80ec30d-….cfargotunnel.com` (proxied) | record `615b34105426877e5a6a082e0870794f` | Routes `tunnel.iforecast.es` to the tunnel. |
| 11 | Identity providers | GitHub `bed3561d-2c26-4e60-b5a3-01c0dde988f4` (OAuth app owned by the candidate; Terraform `identity_provider.tf`, secret not managed) and One-time PIN `85134fd8-55cf-42d8-bb85-dbd9c0ad2806` (pre-existing); both listed in the app's `allowed_idps` | Step 5: GitHub is the federated SSO IdP (optional); the e-mail OTP is the main login method for reviewers. |
| 12 | Access policy (reusable) `cf-assessment-allow-owner-and-cloudflare` | `1262eec6-1476-41a8-9d2c-5ee099b26919` | Step 6: Allow if e-mail = the candidate's personal address **or** e-mail domain = `cloudflare.com`; session 24 h. |
| 13 | Access application `cf-assessment-secure` (self-hosted) | app `12466994-8322-407c-9c72-0fc96c4d567e`, **AUD `56caad5eb8cc92a41b86e6807e0f6d29fd3cd9e6ab681789a1d4c188ae993733`** | Step 6: protects `/secure` **and** `/secure/*` on `tunnel.iforecast.es` and `origin.iforecast.es` (four destinations, because `/secure/*` does not match `/secure`). Team domain `https://iforecast.cloudflareaccess.com`. The AUD is the Worker's `POLICY_AUD`. |
| 14 | R2 bucket `cf-assessment-flags` (private) | location WNAM | Step 7 prep: 257 flags at `flags/<cc>.svg` (ISO 3166-1 alpha-2, lowercase), `Content-Type: image/svg+xml`. r2.dev disabled, no custom domain — only reachable through the Worker binding. Source: [lipis/flag-icons](https://github.com/lipis/flag-icons) 4x3 set, commit `086f7e9`, **MIT License** © Panayiotis Lipiridis. |
| 15 | Worker `cf-assessment-secure` + 4 routes | Worker `41d0347049724ce9a2ed79d264e67177`; routes `{tunnel,origin}.iforecast.es/secure` and `/secure/*` | Step 7: identity page and flags (code in `worker/`, deployed with Wrangler). workers.dev and preview URLs disabled, so the Worker is only reachable behind Access. Every route has a matching Access destination. |

## Verification (see `docs/evidence/`)

| Test | Expected | Result |
|---|---|---|
| `curl https://68.221.177.94/` from a non-Cloudflare IP | fail | timeout (firewall) — `01-direct-ip.txt` |
| `curl --resolve origin.iforecast.es:443:68.221.177.94 https://origin.iforecast.es/` | fail | timeout (firewall) — `02` |
| Same, from the VM itself (firewall bypassed) | fail | unknown SNI → TLS alert *unrecognized name*; correct SNI without client cert → `400 No required SSL certificate was sent` — `09` |
| `curl https://origin.iforecast.es/` | 200 + all headers | 200, includes `cf-connecting-ip`, `cf-ray`, `cf-ipcountry`, custom `x-probe`; nginx logs `ssl_client_verify=SUCCESS` — `03`, `09` |
| `curl -I http://origin.iforecast.es/` | 301 to https | 301 — `04` |
| `curl https://tunnel.iforecast.es/` | 200 + headers via tunnel | 200, includes `cf-warp-tag-id` (tunnel) — `05` |
| `curl -I https://tunnel.iforecast.es/secure` and `/secure/ES` | 302 to Access | 302 → `iforecast.cloudflareaccess.com/cdn-cgi/access/login/...` — `06`, `07` |
| Public DNS | Cloudflare IPs only | `188.114.96.5/97.5` — `08` |
| Cloudflare API state snapshot | — | `10-cloudflare-api-state.txt` (zone SSL still `full`, zone AOP `off`) |
| Unauthenticated `/secure*` on both hosts, forged `Cf-Access-*` headers, workers.dev URL | 302 to Access / 404 | as expected — `11-worker-deploy-and-access.txt` |
| `terraform apply` (adoption) | import only | 16 imported, 0 added, 1 changed (identical AOP association), 0 destroyed — `terraform-apply.txt`; the GitHub IdP was imported later (17 resources managed) — `15` |
| `terraform plan` after apply | no changes | **No changes** — `terraform-plan-after.txt` |

## Terraform (IaC)

Files: `versions.tf`, `variables.tf`, `dns.tf`, `rules.tf`, `aop.tf`, `tunnel.tf`, `access.tf`, `r2.tf`,
`workers.tf`, `outputs.tf`, `imports.tf`, `terraform.tfvars.example`. Provider `cloudflare/cloudflare ~> 5.26`.
**Status:** applied on 2026-10-01 — 17 resources are in Terraform state (16 adopted first + the GitHub IdP) and a follow-up plan reports
*No changes*.

```bash
cd infra/cloudflare
cp terraform.tfvars.example terraform.tfvars        # git-ignored; no secrets inside
export CLOUDFLARE_API_TOKEN=...                     # runtime only, never committed
terraform init -backend-config="path=$HOME/.cf-assessment/terraform.tfstate"   # local state outside the repo
terraform plan                                      # imports.tf adopts the API-created objects
terraform apply                                     # writes state; then imports.tf can be deleted
terraform output access_app_aud
terraform output -raw tunnel_token                  # sensitive: feed to provision.sh, never commit
```

Notes:
- **Adoption.** `imports.tf` maps each resource to the live object IDs above, so the first apply
  imports instead of duplicating. The remaining in-place change is the AOP association: the provider's
  import does not fill the `config` list, so apply re-sends the identical config (idempotent PUT).
- **State contains secrets** (tunnel token data source, AOP key). Here it is a local, git-ignored file
  (`backend "local"`, path passed at init time). **Production should use an encrypted remote backend
  with locking** (e.g. access-restricted R2/S3 bucket with server-side encryption, or Terraform Cloud).
- **Rulesets are phase entry points.** `cloudflare_ruleset.config_settings` and `.redirects` own the
  whole `http_config_settings` / `http_request_dynamic_redirect` entry points of the zone. Today they
  contain only the assessment rules; if other rules are later added in the dashboard, add them here
  or Terraform will remove them.
- **Not in Terraform on purpose:** existing production DNS records and settings, the pre-existing OTP
  IdP, R2 objects (uploaded with Wrangler), and the Worker *code/bindings* (Wrangler in `worker/`).
  Terraform owns the Worker object (`cloudflare_worker`: workers.dev/previews off, observability) and the
  four `cloudflare_workers_route`s; the same routes are declared in `wrangler.jsonc`, so both tools converge.
- AOP certificate/key are read from files outside git (`aop_client_cert_path`, `aop_client_key_path`).

## How it was built (reproducible)

1. **Origin** — `sudo ./infra/origin/provision.sh --admin-ip <ip>/32 --tunnel-token-file <file>` on the
   VM after placing `fullchain.pem`, `privkey.pem` (600) and `aop-ca.pem` in `/etc/ssl/cf-assessment/`.
2. **Certificate** — from an admin workstation:
   `CF_Token=<zone DNS:Edit token> acme.sh --issue --server letsencrypt --dns dns_cf -d origin.iforecast.es -d tunnel.iforecast.es --keylength ec-256`.
   The cert and key were copied to the VM over SSH; the key was removed from the intermediate PC.
   **Production recommendation:** run certbot (`python3-certbot-dns-cloudflare`) or acme.sh **on the
   origin** with a dedicated token scoped to *Zone:DNS:Edit on iforecast.es only*, stored root-only
   (600), with a deploy hook `systemctl reload nginx`, so renewal is automatic (LE certs last 90 days;
   this one expires 2026-12-30).
3. **AOP private PKI** (openssl, ECDSA P-256): self-signed CA (`CA:TRUE`, 825 days) → client leaf
   (`CA:FALSE`, `extendedKeyUsage=clientAuth`, 365 days). Leaf + key uploaded to
   `POST /zones/{zone}/origin_tls_client_auth/hostnames/certificates`, then
   `PUT /zones/{zone}/origin_tls_client_auth/hostnames` with `{hostname, cert_id, enabled:true}`.
   Only the **CA certificate** goes to nginx (`ssl_client_certificate`). Rotate before 2027-10-01
   (an expiry notification can be enabled in Notifications).
4. **Rules** — `PUT /zones/{zone}/rulesets/phases/http_config_settings/entrypoint` (`set_config ssl=strict`)
   and `.../http_request_dynamic_redirect/entrypoint`.
5. **Tunnel** — `POST /accounts/{acct}/cfd_tunnel {name, config_src:"cloudflare"}`,
   `PUT .../cfd_tunnel/{id}/configurations` (ingress), `GET .../cfd_tunnel/{id}/token`,
   CNAME to `<id>.cfargotunnel.com`, `cloudflared service install <token>` on the VM.
6. **Access** — `POST /accounts/{acct}/access/policies`, `POST /accounts/{acct}/access/apps`.
6b. **GitHub IdP** — OAuth app on GitHub (callback `https://iforecast.cloudflareaccess.com/cdn-cgi/access/callback`),
   IdP added in the Zero Trust dashboard, then `terraform import`.
7. **Worker** — `wrangler deploy` from `worker/` (token passed only as process env). Then `terraform apply`
   adopted the Worker object and routes.
8. **R2** — `POST /accounts/{acct}/r2/buckets`, then for each flag
   `wrangler r2 object put cf-assessment-flags/flags/<cc>.svg --file <svg> --content-type image/svg+xml --remote`.

## Owner actions

- **GitHub IdP:** done (OAuth app on the candidate's GitHub account, added in the dashboard, adopted in
  `identity_provider.tf`). A complete GitHub login through to `/secure` was run by the candidate on 2026-10-01 (18:17 Europe/Madrid) — `docs/evidence/17-final-logins.txt`.
  To rotate the secret: generate a new one on GitHub and paste it in Zero Trust → Integrations → Identity
  providers → GitHub (Terraform ignores `client_secret`).
- Certificate renewal before 2026-12-30 (see recommendation above).
