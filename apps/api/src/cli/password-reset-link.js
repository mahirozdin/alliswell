#!/usr/bin/env node
/**
 * OPH-406 (ADR-0064) — a password-reset link issued by the server's operator.
 *
 * For an install with no outgoing mail (no SMTP_* block), where the app's
 * "Forgot password" screen says "ask the person who runs this server". The
 * operator runs, on the server:
 *
 *   docker compose -f docker-compose.selfhost.yml exec api \
 *     node apps/api/src/cli/password-reset-link.js person@example.com
 *
 *   (from a checkout: npm run password:reset-link -- person@example.com)
 *
 * and passes the printed link on by hand. It works once, for 24 hours, and
 * every earlier link of that account stops working. Without an address for
 * the web app (APP_PUBLIC_URL, or a single CORS_ORIGIN) it prints the code,
 * which the app's "I have a link" field also takes.
 *
 * It reads the same environment as the server, so it signs with the server's
 * JWT_REFRESH_SECRET — a link made with another secret would never match.
 */
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import knex from 'knex';

import { loadConfig } from '../config.js';
import { buildKnexConfig } from '../db/knexconfig.js';
import {
  ADMIN_RESET_TTL_MS,
  issuePasswordReset,
  resetLink,
  resetLinkBase,
} from '../lib/password-reset.js';

const USAGE = 'usage: password-reset-link <email>';

/**
 * @param {{ argv: string[], config?: object, db?: import('knex').Knex,
 *           out?: (line: string) => void, err?: (line: string) => void }} opts
 * @returns {Promise<number>} the exit code
 */
export async function run({
  argv,
  config = loadConfig(),
  db,
  out = (line) => process.stdout.write(`${line}\n`),
  err = (line) => process.stderr.write(`${line}\n`),
}) {
  const email = (argv[0] ?? '').trim().toLowerCase();
  if (argv.length !== 1 || !email.includes('@')) {
    err(USAGE);
    return 2;
  }
  const owned = !db;
  const conn = db ?? knex(buildKnexConfig(config));
  try {
    const user = await conn('users').where({ email }).whereNull('deleted_at').first('id');
    // The operator is trusted with this answer; the public form is not.
    if (!user) {
      err(`No account with the address ${email}.`);
      return 1;
    }
    const { token, expiresAt } = await issuePasswordReset(conn, {
      userId: user.id,
      secret: config.auth.refreshSecret,
      ttlMs: ADMIN_RESET_TTL_MS,
      source: 'admin',
    });
    const base = resetLinkBase(config);
    out(base ? resetLink(base, token) : token);
    if (!base) {
      err(
        'No web app address (APP_PUBLIC_URL) — that is the code itself. In the app: ' +
          'Forgot password → I have a link → paste it.',
      );
    }
    err(`Works once, until ${expiresAt.toISOString()}.`);
    return 0;
  } finally {
    if (owned) await conn.destroy();
  }
}

const invoked = process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url);
if (invoked) {
  run({ argv: process.argv.slice(2) }).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      process.stderr.write(`password-reset-link failed: ${error.message}\n`);
      process.exitCode = 1;
    },
  );
}
