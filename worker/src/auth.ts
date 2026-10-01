import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';

export type AuthOptions = {
  getKey?: JWTVerifyGetKey;
  fetchIdentity?: typeof fetch;
};

export class AuthError extends Error {
  constructor(public readonly status: 403 | 500, public readonly outcome: string) {
    super(outcome);
  }
}

// Reuse jose's cached resolver across requests, separately for each issuer.
const resolvers = new Map<string, ReturnType<typeof createRemoteJWKSet>>();

function configuration(env: Env): { domain: string; audience: string } {
  const domain = env.TEAM_DOMAIN?.trim().replace(/\/+$/, '');
  const audience = env.POLICY_AUD?.trim();
  if (!domain || !audience || /REPLACE|PLACEHOLDER/i.test(`${domain} ${audience}`)) {
    throw new AuthError(500, 'auth_configuration');
  }
  try {
    const url = new URL(domain);
    if (url.protocol !== 'https:' || url.origin !== domain || url.username || url.password) {
      throw new Error('Invalid issuer');
    }
  } catch {
    throw new AuthError(500, 'auth_configuration');
  }
  return { domain, audience };
}

export async function authenticate(request: Request, env: Env, options: AuthOptions = {}) {
  const { domain, audience } = configuration(env);
  const token = request.headers.get('Cf-Access-Jwt-Assertion');
  if (!token) throw new AuthError(403, 'auth_missing');
  let getKey = options.getKey;
  if (!getKey) {
    let resolver = resolvers.get(domain);
    if (!resolver) {
      resolver = createRemoteJWKSet(new URL(`${domain}/cdn-cgi/access/certs`));
      resolvers.set(domain, resolver);
    }
    getKey = resolver;
  }
  let payload;
  try {
    ({ payload } = await jwtVerify(token, getKey, {
      issuer: domain,
      audience,
      algorithms: ['RS256'],
      requiredClaims: ['exp', 'iat'],
      clockTolerance: 5,
    }));
  } catch {
    throw new AuthError(403, 'auth_invalid');
  }
  let email = typeof payload.email === 'string' ? payload.email.trim() : '';
  if (!email) {
    // Look up the identity of the assertion that was just verified. A separately supplied
    // CF_Authorization cookie is never used, so the identity is always bound to this token.
    const authorization = `CF_Authorization=${token}`;
    try {
      const response = await (options.fetchIdentity ?? fetch)(`${domain}/cdn-cgi/access/get-identity`, {
        headers: { Cookie: authorization },
        redirect: 'error',
        signal: AbortSignal.timeout(5000),
      });
      if (response.ok) {
        const identity: unknown = await response.json();
        if (identity && typeof identity === 'object' && 'email' in identity && typeof identity.email === 'string') {
          email = identity.email.trim();
        }
      }
    } catch {
      // Identity failure is intentionally indistinguishable to the client.
    }
  }
  if (!email) throw new AuthError(403, 'auth_no_email');
  if (typeof payload.iat !== 'number') throw new AuthError(403, 'auth_invalid');
  // TIMESTAMP is the moment Access issued the token, i.e. the time of authentication.
  const timestamp = new Date(payload.iat * 1000).toISOString();
  return { email, timestamp };
}
