import { describe, it, expect, afterAll, beforeAll } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { buildApp } from '../../src/app.js';
import { upsertMetadataClient, clientRedirectUris } from '../../src/db/oauth.js';

/**
 * ADR-0047 over real MySQL: a metadata URL maps to ONE ordinary client row —
 * a refresh updates it in place, and two first sightings racing each other
 * meet on the unique key instead of making two rows.
 */
const enabled = process.env.INTEGRATION === '1';

describe.runIf(enabled)('metadata clients (ADR-0047)', () => {
  let app;
  const url = `https://cimd-int-${Date.now()}.example/oauth/meta.json`;
  const later = () => new Date(Date.now() + 3600 * 1000);

  beforeAll(async () => {
    app = await buildApp({ config: loadConfig({ ...process.env, NODE_ENV: 'test' }) });
  });

  afterAll(async () => {
    if (!app) return;
    await app.db('oauth_clients').where({ metadata_url: url }).delete();
    await app.close();
  });

  it('maps a URL to one row, refreshes it in place, and survives a race', async () => {
    const first = await upsertMetadataClient(app.db, {
      url,
      name: 'Claude',
      redirectUris: ['https://cimd.example/cb'],
      expiresAt: later(),
    });
    expect(first.id).toHaveLength(26);
    expect(first.token_endpoint_auth_method).toBe('none');

    const refreshed = await upsertMetadataClient(app.db, {
      url,
      name: 'Claude (renamed)',
      redirectUris: ['https://cimd.example/cb2'],
      expiresAt: later(),
    });
    expect(refreshed.id).toBe(first.id);
    expect(refreshed.name).toBe('Claude (renamed)');
    expect(clientRedirectUris(refreshed)).toEqual(['https://cimd.example/cb2']);

    await app.db('oauth_clients').where({ metadata_url: url }).delete();
    const raced = await Promise.all(
      [1, 2, 3].map(() =>
        upsertMetadataClient(app.db, {
          url,
          name: 'Claude',
          redirectUris: ['https://cimd.example/cb'],
          expiresAt: later(),
        }),
      ),
    );
    expect(new Set(raced.map((row) => row.id)).size).toBe(1);
    expect(await app.db('oauth_clients').where({ metadata_url: url }).count({ n: '*' })).toEqual([
      { n: 1 },
    ]);
  });
});
