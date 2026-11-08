import { describe, it, expect } from 'vitest';

import { resetLink, resetLinkBase, resetMail } from '../../src/lib/password-reset.js';
import { hashPasswordResetToken, hashRefreshToken } from '../../src/lib/tokens.js';

// OPH-406 (ADR-0064) — the pieces of a reset link that need no database.
describe('password reset links', () => {
  it('point at APP_PUBLIC_URL, else at a single CORS origin, else nowhere', () => {
    expect(resetLinkBase({ appPublicUrl: 'https://a.example/app', corsOrigin: true })).toBe(
      'https://a.example/app',
    );
    expect(resetLinkBase({ appPublicUrl: null, corsOrigin: ['https://a.example/'] })).toBe(
      'https://a.example',
    );
    expect(resetLinkBase({ appPublicUrl: null, corsOrigin: true })).toBeNull();
    expect(
      resetLinkBase({ appPublicUrl: null, corsOrigin: ['https://a.example', 'https://b.example'] }),
    ).toBeNull();
  });

  it('carry the token after the hash, where no server log sees it', () => {
    expect(resetLink('https://a.example', 'abc_-123')).toBe(
      'https://a.example/#/reset-password?token=abc_-123',
    );
  });

  it('are hashed with their own separator', () => {
    const digest = hashPasswordResetToken('t', 'secret');
    expect(digest).toMatch(/^[0-9a-f]{64}$/);
    expect(digest).not.toBe(hashRefreshToken('t', 'secret'));
  });

  it('mail in Turkish or English, English for anything else', () => {
    const tr = resetMail('tr', 'https://x/#/reset-password?token=t', 60);
    expect(tr.subject).toBe('AllisWell parolanı sıfırla');
    expect(tr.text).toContain('60 dakika');
    expect(resetMail(undefined, 'L', 30).text).toContain('for 30 minutes');
    expect(resetMail('de', 'L', 30).subject).toBe('Reset your AllisWell password');
  });
});
