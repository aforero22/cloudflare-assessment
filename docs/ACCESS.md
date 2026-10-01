# Reviewer access guide

## URLs

| URL | What you should see | Who can access |
|---|---|---|
| https://origin.iforecast.es/ | JSON with **all request headers** (via Cloudflare proxy, Full strict) | Everyone |
| https://tunnel.iforecast.es/ | Same JSON, served through **Cloudflare Tunnel** (note `cf-warp-tag-id`) | Everyone |
| https://tunnel.iforecast.es/secure | `<your e-mail> authenticated at <timestamp> from <COUNTRY>` | Cloudflare Access |
| https://tunnel.iforecast.es/secure/ES | Country flag (SVG) from a private R2 bucket | Cloudflare Access |

Add `?format=text` to the first two URLs for plain text. `/secure` is also available on
`origin.iforecast.es` with the same protection.

## Who is allowed

- Any e-mail address ending in **`@cloudflare.com`**.
- The candidate's personal address.
- Everyone else is denied by Cloudflare Access.

## How to log in (`@cloudflare.com` reviewers)

Use **e-mail + Send login code** (one-time PIN). That is the main login method. **GitHub** (federated
SSO) is optional and only works if your GitHub account's primary e-mail is an `@cloudflare.com` address.
Cloudflare's login page always places identity-provider buttons at the top, so you will see a
*Sign in with: GitHub* button above the e-mail form; the blue **Send login code** button below it is the
one to use.

1. Open https://tunnel.iforecast.es/secure — you are redirected to `iforecast.cloudflareaccess.com`.
2. In the **Email** field, enter your `@cloudflare.com` address and click **Send login code**. You can
   ignore the *Sign in with: GitHub* button above it. (Optional: click **GitHub** instead; you get in only
   if the GitHub account's primary e-mail ends in `@cloudflare.com`.)
3. Enter the 6-digit code from the e-mail sent by Cloudflare Access.
4. You land on `/secure`:
   `you@cloudflare.com authenticated at 2026-10-02T09:15:00.000Z from ES`
   - The timestamp is the moment Access authenticated you (ISO-8601, UTC).
   - The country is computed per request from `request.cf.country` (where your request entered Cloudflare).
5. Click the country code to open `/secure/<CC>` and see the flag (`Content-Type: image/svg+xml`).

The session lasts 24 hours. Use a private window to start over.

## Quick checks from a terminal

```bash
# Headers through Cloudflare (expect 200, cf-connecting-ip and cf-ray in the body)
curl -s -H "X-Probe: reviewer" https://origin.iforecast.es/

# Through the tunnel
curl -s https://tunnel.iforecast.es/

# /secure without a session -> 302 to the Access login page
curl -sI https://tunnel.iforecast.es/secure | grep -iE '^(HTTP|location)'

# Direct to the origin IP -> must fail (timeout: only Cloudflare IP ranges may connect)
curl -v --connect-timeout 10 https://68.221.177.94/
curl -v --connect-timeout 10 --resolve origin.iforecast.es:443:68.221.177.94 https://origin.iforecast.es/
```

Even if a connection reached the server, nginx refuses unknown hostnames at the TLS handshake and
requires Cloudflare's client certificate (Authenticated Origin Pulls) for `origin.iforecast.es`
(see `evidence/09-on-vm-checks.txt`).

More detail: [`REPORT.md`](REPORT.md) · evidence in [`evidence/`](evidence).
