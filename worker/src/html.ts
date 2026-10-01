export function escapeHtml(value: string): string {
  const entities: Record<string, string> = {
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  };
  return value.replace(/[&<>"']/g, (character) => entities[character]);
}

export function countryCode(value: unknown): string | undefined {
  if (typeof value !== 'string' || !/^[A-Za-z]{2}$/.test(value)) return undefined;
  const country = value.toUpperCase();
  return country === 'XX' ? undefined : country;
}

export function renderPage(email: string, timestamp: string, country?: string): string {
  const label = escapeHtml(country ?? 'unknown');
  const location = country ? `<a href="/secure/${escapeHtml(country)}">${label}</a>` : label;
  return `<!doctype html>\n<html lang="en"><head><meta charset="utf-8"><title>Authenticated access</title></head><body><p>${escapeHtml(email)} authenticated at ${escapeHtml(timestamp)} from ${location}</p></body></html>`;
}

export const htmlHeaders = {
  'Content-Type': 'text/html; charset=utf-8',
  'Content-Security-Policy': "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'Cache-Control': 'private, no-store',
  'X-Frame-Options': 'DENY',
};
