import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it, vi } from 'vitest';
import { generateKeyPair, SignJWT, type JWTPayload } from 'jose';
import worker, { createHandler } from '../src/index';

const issuer = 'https://test.cloudflareaccess.com';
const iat = 1700000000;
let keys: Awaited<ReturnType<typeof generateKeyPair>>;
let otherKeys: Awaited<ReturnType<typeof generateKeyPair>>;
const noNetwork: typeof fetch = () => Promise.reject(new Error('Network forbidden in tests'));

beforeAll(async () => {
  keys = await generateKeyPair('RS256');
  otherKeys = await generateKeyPair('RS256');
});

async function token(claims: JWTPayload = {}, badSignature = false): Promise<string> {
  return new SignJWT({
    email: 'user@example.com', iss: issuer, aud: 'test-aud', iat,
    exp: Math.floor(Date.now() / 1000) + 3600, ...claims,
  }).setProtectedHeader({ alg: 'RS256' }).sign(badSignature ? otherKeys.privateKey : keys.privateKey);
}

async function request(path = '/secure', options: {
  jwt?: string | null;
  method?: string;
  country?: string;
  bindings?: Env;
  fetchIdentity?: typeof fetch;
  cookie?: string;
} = {}): Promise<Response> {
  const headers = new Headers();
  const jwt = options.jwt === undefined ? await token() : options.jwt;
  if (jwt) headers.set('Cf-Access-Jwt-Assertion', jwt);
  if (options.cookie) headers.set('Cookie', options.cookie);
  const handler = createHandler({ getKey: () => keys.publicKey, fetchIdentity: options.fetchIdentity ?? noNetwork });
  return handler.fetch(new Request(`https://tunnel.iforecast.es${path}`, {
    method: options.method ?? 'GET', headers,
    cf: { country: options.country ?? 'ES' },
  }), options.bindings ?? env);
}

describe('authenticated page', () => {
  it('renders the exact sentence, link, and security headers', async () => {
    const response = await request();
    expect(response.status).toBe(200);
    expect(await response.text()).toContain('user@example.com authenticated at 2023-11-14T22:13:20.000Z from <a href="/secure/ES">ES</a>');
    expect(response.headers.get('Content-Type')).toBe('text/html; charset=utf-8');
    expect(response.headers.get('Content-Security-Policy')).toBe("default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
    expect(response.headers.get('X-Content-Type-Options')).toBe('nosniff');
    expect(response.headers.get('Referrer-Policy')).toBe('no-referrer');
    expect(response.headers.get('Cache-Control')).toBe('private, no-store');
    expect(response.headers.get('X-Frame-Options')).toBe('DENY');
  });

  it('accepts the trailing slash and HEAD', async () => {
    expect((await request('/secure/')).status).toBe(200);
    const response = await request('/secure', { method: 'HEAD' });
    expect(response.status).toBe(200);
    expect(await response.text()).toBe('');
  });

  it.each(['XX', 'T1', ''])('does not link unknown country %s', async (country) => {
    const response = await request('/secure', { country });
    expect(response.status).toBe(200);
    expect(await response.text()).toContain('from unknown</p>');
  });

  it('renders unknown when request.cf is absent', async () => {
    const handler = createHandler({ getKey: () => keys.publicKey, fetchIdentity: noNetwork });
    const response = await handler.fetch(new Request('https://tunnel.iforecast.es/secure', {
      headers: { 'Cf-Access-Jwt-Assertion': await token() },
    }), env);
    expect(response.status).toBe(200);
    expect(await response.text()).toContain('from unknown</p>');
  });

  it('escapes all five HTML-sensitive characters', async () => {
    const response = await request('/secure', { jwt: await token({ email: `<img src="x" onerror='x'>&` }) });
    expect(await response.text()).toContain('&lt;img src=&quot;x&quot; onerror=&#39;x&#39;&gt;&amp;');
  });

  it('rejects a token without iat, because TIMESTAMP is the authentication time', async () => {
    expect((await request('/secure', { jwt: await token({ iat: undefined }) })).status).toBe(403);
  });
});

describe('authentication', () => {
  it.each(['/secure', '/secure/ES', '/secureXYZ'])('rejects missing JWT before routing %s', async (path) => {
    const response = await request(path, { jwt: null });
    expect(response.status).toBe(403);
    expect(await response.text()).toBe('Forbidden');
    expect(response.headers.get('Cache-Control')).toBe('no-store');
    expect(response.headers.get('X-Content-Type-Options')).toBe('nosniff');
  });

  it('rejects a bad signature', async () => {
    expect((await request('/secure', { jwt: await token({}, true) })).status).toBe(403);
  });

  it.each([
    { aud: 'wrong' }, { iss: 'https://wrong.example.com' },
    { exp: Math.floor(Date.now() / 1000) - 60 }, { exp: undefined },
  ])('rejects invalid claims %j', async (claims) => {
    expect((await request('/secure', { jwt: await token(claims) })).status).toBe(403);
  });

  it.each([
    { POLICY_AUD: 'REPLACE_WITH_ACCESS_APPLICATION_AUD' }, { POLICY_AUD: '' },
    { TEAM_DOMAIN: '' }, { TEAM_DOMAIN: 'REPLACE_WITH_TEAM_DOMAIN' },
    { TEAM_DOMAIN: 'http://test.cloudflareaccess.com' },
  ])('fails closed for invalid configuration %j', async (overrides) => {
    expect((await request('/secure', { bindings: { ...env, ...overrides }, jwt: null })).status).toBe(500);
  });

  it('normalizes the issuer trailing slash', async () => {
    expect((await request('/secure', { bindings: { ...env, TEAM_DOMAIN: `${issuer}/` } })).status).toBe(200);
  });

  it('does not fetch identity when the claim contains email', async () => {
    const fetchIdentity = vi.fn(noNetwork);
    expect((await request('/secure', { fetchIdentity })).status).toBe(200);
    expect(fetchIdentity).not.toHaveBeenCalled();
  });

  it('binds identity lookup to the verified assertion, ignoring any other cookie', async () => {
    const jwt = await token({ email: undefined });
    const fetchIdentity = vi.fn<typeof fetch>(async () => Response.json({ email: 'identity@example.com' }));
    const response = await request('/secure', {
      jwt, fetchIdentity,
      cookie: 'other=secret; CF_Authorization=someone-elses-cookie; unrelated=value',
    });
    expect(response.status).toBe(200);
    expect(await response.text()).toContain('identity@example.com authenticated');
    expect(fetchIdentity.mock.calls[0][0]).toBe(`${issuer}/cdn-cgi/access/get-identity`);
    expect(new Headers(fetchIdentity.mock.calls[0][1]?.headers).get('Cookie')).toBe(`CF_Authorization=${jwt}`);
  });

  it('can use the verified JWT as the identity cookie', async () => {
    const jwt = await token({ email: undefined });
    const fetchIdentity = vi.fn<typeof fetch>(async () => Response.json({ email: 'identity@example.com' }));
    expect((await request('/secure', { jwt, fetchIdentity })).status).toBe(200);
    expect(new Headers(fetchIdentity.mock.calls[0][1]?.headers).get('Cookie')).toBe(`CF_Authorization=${jwt}`);
  });

  it('rejects identities without email and network failures', async () => {
    const jwt = await token({ email: undefined });
    expect((await request('/secure', { jwt })).status).toBe(403);
    expect((await request('/secure', { jwt, fetchIdentity: async () => Response.json({}) })).status).toBe(403);
  });
});

describe('flags and routes', () => {
  it('serves SVG with metadata, ETag, cache policy, and CSP', async () => {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg"/>';
    const object = await env.FLAGS.put('flags/es.svg', svg, { httpMetadata: { contentType: 'image/svg+xml' } });
    const response = await request('/secure/ES');
    expect(response.status).toBe(200);
    expect(response.headers.get('Content-Type')).toBe('image/svg+xml');
    expect(response.headers.get('ETag')).toBe(object!.httpEtag);
    expect(response.headers.get('Cache-Control')).toBe('private, max-age=3600');
    expect(response.headers.get('X-Content-Type-Options')).toBe('nosniff');
    expect(response.headers.get('Content-Security-Policy')).toBe("default-src 'none'; style-src 'unsafe-inline'; sandbox");
    expect(await response.text()).toBe(svg);
    const head = await request('/secure/ES', { method: 'HEAD' });
    expect(head.headers.get('ETag')).toBe(object!.httpEtag);
    expect(await head.text()).toBe('');
  });

  it('falls back to PNG without content-type metadata', async () => {
    // Use a country without an SVG: R2 storage is shared by tests in this file.
    await env.FLAGS.put('flags/fr.png', new Uint8Array([137, 80, 78, 71]));
    const response = await request('/secure/fr');
    expect(response.status).toBe(200);
    expect(response.headers.get('Content-Type')).toBe('image/png');
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(new Uint8Array([137, 80, 78, 71]));
  });

  it.each(['/secure/ZZ', '/secure/e1', '/secure/..%2F', '/secure/ESP', '/secureXYZ', '/secure/es/extra', '/elsewhere'])('returns 404 for %s', async (path) => {
    expect((await request(path)).status).toBe(404);
  });

  it.each(['/secure', '/secure/ES'])('rejects POST with Allow for %s', async (path) => {
    const response = await request(path, { method: 'POST' });
    expect(response.status).toBe(405);
    expect(response.headers.get('Allow')).toBe('GET, HEAD');
  });

  it('logs categories without email, JWT, or arbitrary path values', async () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => {});
    try {
      await request('/secure/private@example.com');
      const entry = JSON.parse(log.mock.calls[0][0] as string);
      expect(entry).toEqual({ path: 'other', status: 404, outcome: 'route_missing', country: 'ES' });
    } finally {
      log.mockRestore();
    }
  });
});

describe('default export', () => {
  it('rejects a malformed JWT before any JWKS fetch', async () => {
    const response = await worker.fetch(new Request('https://tunnel.iforecast.es/secure', {
      headers: { 'Cf-Access-Jwt-Assertion': 'not-a-jwt' },
    }), env);
    expect(response.status).toBe(403);
  });
});