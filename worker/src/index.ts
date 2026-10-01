import { authenticate, AuthError, type AuthOptions } from './auth';
import { flagResponse } from './flags';
import { countryCode, htmlHeaders, renderPage } from './html';

const errorMessages: Record<number, string> = {
  403: 'Forbidden', 404: 'Not Found', 405: 'Method Not Allowed', 500: 'Internal Server Error',
};

function errorResponse(status: number, head: boolean): Response {
  const message = errorMessages[status] ?? 'Internal Server Error';
  return new Response(head ? null : message, {
    status,
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
      'X-Content-Type-Options': 'nosniff',
      'Cache-Control': 'no-store',
      ...(status === 405 ? { Allow: 'GET, HEAD' } : {}),
    },
  });
}

export function createHandler(options: AuthOptions = {}) {
  return {
    async fetch(request: Request, env: Env): Promise<Response> {
      const path = new URL(request.url).pathname;
      const country = countryCode(request.cf?.country);
      const head = request.method === 'HEAD';
      let response: Response;
      let outcome: string;
      try {
        // Authentication always precedes routing and method handling.
        const identity = await authenticate(request, env, options);
        const flag = /^\/secure\/([A-Za-z]{2})$/.exec(path);
        if (path !== '/secure' && path !== '/secure/' && !flag) {
          response = errorResponse(404, head);
          outcome = 'route_missing';
        } else if (request.method !== 'GET' && !head) {
          response = errorResponse(405, false);
          outcome = 'method_rejected';
        } else if (flag) {
          response = await flagResponse(env.FLAGS, flag[1], head) ?? errorResponse(404, head);
          outcome = response.status === 404 ? 'flag_missing' : 'flag_served';
        } else {
          response = new Response(head ? null : renderPage(identity.email, identity.timestamp, country), { headers: htmlHeaders });
          outcome = 'page_served';
        }
      } catch (error) {
        const authError = error instanceof AuthError ? error : undefined;
        response = errorResponse(authError?.status ?? 500, head);
        outcome = authError?.outcome ?? 'internal_error';
      }
      // Log route shape rather than arbitrary user-controlled path segments.
      const logPath = path === '/secure' || path === '/secure/' ? path : /^\/secure\/[A-Za-z]{2}$/.test(path) ? '/secure/:country' : 'other';
      console.log(JSON.stringify({ path: logPath, status: response.status, outcome, country: country ?? 'unknown' }));
      return response;
    },
  } satisfies ExportedHandler<Env>;
}

export default createHandler() satisfies ExportedHandler<Env>;
