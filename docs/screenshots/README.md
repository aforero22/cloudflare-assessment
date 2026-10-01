# Dashboard screenshots

Files referenced from `../REPORT.md` (23 captures), all captured on 2026-10-01. Browser chrome is cropped (except 13, 14
and 23, which keep the address bar). The candidate e-mail, the admin source IP, the Azure tenant/subscription, the
Cloudflare account ID and the workers.dev subdomain are blurred.

| File | Page | What it shows |
|---|---|---|
| `01-zone-overview.png` | Zone `iforecast.es` → Overview | Zone overview, plan badge **free** |
| `02-dns-records.png` | DNS → Records | `A origin` and the `tunnel` record (shown as type Tunnel → `cf-assessment`; a CNAME to `<id>.cfargotunnel.com`), both proxied |
| `03-ssl-overview.png` | SSL/TLS → Overview | Zone encryption mode **Full** (left unchanged for the other sites) |
| `04-configuration-rule-strict.png` | Rules → Configuration Rules → edit | SSL setting **Strict** in the assessment rule (host expression in `../evidence/10-cloudflare-api-state.txt`) |
| `05-redirect-rule.png` | Rules → Redirect Rules | HTTP → HTTPS rule scoped to the two hosts |
| `06-aop-per-hostname.png` | SSL/TLS → Origin Server → Authenticated Origin Pulls | Global and zone-level AOP **off** (intended); per-hostname association is in `../evidence/10` |
| `07-tunnel-healthy.png` | Zero Trust → Networks → Tunnels | `cf-assessment`, type cloudflared, **Healthy** (connections listed in `../evidence/10`) |
| `08-tunnel-route-tls.png` | Tunnel → published application route → TLS | Service `https://127.0.0.1:8443`, Origin Server Name, TLS verification on |
| `09-idp-login-methods.png` | Zero Trust → Integrations → Identity providers | **One-time PIN** and **GitHub** |
| `10-access-app-destinations.png` | Access → Applications → `cf-assessment-secure` | Destinations (origin `/secure`, `/secure/*` visible; all four and the AUD in `../evidence/13-access-final-state.txt`) |
| `11-access-policy.png` | Access → Policies | Allow: candidate e-mail (blurred) or e-mails ending in `@cloudflare.com` |
| `12-access-login-page.png` | Browser → `https://tunnel.iforecast.es/secure` (no session; re-captured after the `allowed_idps` change, page only, no address bar) | Access login page: *Sign in with: GitHub* (optional) above the e-mail field and the primary **Send login code** button |
| `13-secure-page.png` | Browser after login → `/secure` | Identity sentence (e-mail blurred) and `text/html`; captured from a US-egress browser, so it reads `from US` and links to `/secure/US` |
| `14-flag-page.png` | Browser → `/secure/ES` (opened directly) | Flag and `image/svg+xml` |
| `15-access-logs.png` | Zero Trust → Logs → Access | Allowed login for `cf-assessment-secure` (e-mail blurred) |
| `16-worker-domains-routes.png` | Worker → Settings → Domains & Routes | workers.dev and Preview URLs disabled (subdomain blurred); first route visible |
| `17-worker-bindings.png` | API rendering of `GET …/workers/scripts/cf-assessment-secure/settings` | R2 binding `FLAGS → cf-assessment-flags`, vars `TEAM_DOMAIN`, `POLICY_AUD` (the dashboard capture duplicated 16) |
| `18-worker-observability.png` | Worker → Observability | `page_served` / `flag_served` events, no identity in logs |
| `19-r2-bucket-settings.png` | R2 → `cf-assessment-flags` → Settings | r2.dev public URL disabled, no custom domains |
| `20-azure-nsg-rules.png` | Azure Portal → `nsg-cf-origin` → Inbound rules | 22 from one admin /32 (blurred), 443 from Cloudflare ranges |
| `21-r2-objects.png` | R2 → `cf-assessment-flags` → Objects | Flag objects with type `image/svg+xml` |
| `22-github-actions.png` | GitHub → Actions | Worker workflow run green (lint + tests), deploy skipped (manual) |
| `23-idp-github-login.png` | Browser → `https://tunnel.iforecast.es/secure` (no session) | Access login: *Sign in with GitHub*, or e-mail + *Send login code* |

The country in `/secure` is computed per request from `request.cf.country`; the candidate's own login from
Madrid showed `ES` (`../evidence/12-e2e-browser-login.txt`).
