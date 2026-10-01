function hasBody(object: R2Object): object is R2ObjectBody {
  return 'body' in object;
}

export async function flagResponse(bucket: R2Bucket, country: string, head: boolean): Promise<Response | undefined> {
  const cc = country.toLowerCase();
  for (const extension of ['svg', 'png'] as const) {
    const key = `flags/${cc}.${extension}`;
    const object: R2Object | R2ObjectBody | null = head ? await bucket.head(key) : await bucket.get(key);
    if (!object) continue;
    const headers = new Headers({
      'Content-Type': object.httpMetadata?.contentType ?? (extension === 'svg' ? 'image/svg+xml' : 'image/png'),
      ETag: object.httpEtag,
      'Cache-Control': 'private, max-age=3600',
      'X-Content-Type-Options': 'nosniff',
    });
    if (extension === 'svg') {
      headers.set('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; sandbox");
    }
    return new Response(!head && hasBody(object) ? object.body : null, { headers });
  }
  return undefined;
}
