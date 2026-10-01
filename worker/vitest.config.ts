import { cloudflareTest } from '@cloudflare/vitest-pool-workers';
import { defineConfig } from 'vitest/config';

// Tests run inside workerd (Miniflare) with a local, isolated R2 bucket.
// Access settings are overridden so tests never depend on real configuration.
export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: './wrangler.jsonc' },
      miniflare: {
        bindings: {
          POLICY_AUD: 'test-aud',
          TEAM_DOMAIN: 'https://test.cloudflareaccess.com',
        },
      },
    }),
  ],
});