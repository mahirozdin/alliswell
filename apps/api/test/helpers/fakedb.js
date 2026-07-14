/**
 * Minimal in-memory stand-in for the knex surface the API routes use, so unit
 * tests run without MySQL (AGENTS.md §5). Supported chain:
 *   db(table).where(obj).whereNull(col).whereIn(col, vals) → .first() / .select() / .update() / .delete()
 * plus db.transaction(fn) (no rollback simulation — partial-failure semantics
 * belong in test/integration) and the `uq_users_email` unique index, reported
 * the way mysql2 does (ER_DUP_ENTRY).
 */
export function fakeDb({ hideUsersFromPrecheck = false } = {}) {
  const tables = {
    users: [],
    workspaces: [],
    workspace_members: [],
    refresh_tokens: [],
  };

  const builder = (name) => {
    const filters = [];
    const matching = () => tables[name].filter((row) => filters.every((f) => f(row)));

    const api = {
      where(cond) {
        filters.push((row) => Object.entries(cond).every(([key, val]) => row[key] === val));
        return api;
      },
      whereNull(col) {
        filters.push((row) => row[col] === null || row[col] === undefined);
        return api;
      },
      whereIn(col, values) {
        filters.push((row) => values.includes(row[col]));
        return api;
      },
      // Column-selection args are irrelevant to the fake — full rows come back.
      async first() {
        if (name === 'users' && hideUsersFromPrecheck) return undefined;
        const row = matching()[0];
        return row ? { ...row } : undefined;
      },
      async select() {
        return matching().map((row) => ({ ...row }));
      },
      async update(patch) {
        const rows = matching();
        for (const row of rows) Object.assign(row, patch, { updated_at: new Date() });
        return rows.length;
      },
      async delete() {
        const doomed = new Set(matching());
        tables[name] = tables[name].filter((row) => !doomed.has(row));
        return doomed.size;
      },
      async insert(row) {
        if (name === 'users' && tables.users.some((u) => u.email === row.email)) {
          const err = new Error(`Duplicate entry '${row.email}' for key 'users.uq_users_email'`);
          err.code = 'ER_DUP_ENTRY';
          err.errno = 1062;
          throw err;
        }
        // Mimic the column defaults the real schema applies (ADR-0004 / OPH-011).
        const defaults = { created_at: new Date(), updated_at: new Date() };
        if (name === 'users')
          Object.assign(defaults, { timezone: 'Europe/Istanbul', locale: 'tr-TR' });
        if (name === 'workspaces') Object.assign(defaults, { color_rgb: '#2563EB' });
        tables[name].push({ ...defaults, ...row });
        return [1];
      },
    };
    return api;
  };

  const db = (name) => {
    if (!tables[name]) throw new Error(`fakeDb: unknown table "${name}"`);
    return builder(name);
  };
  // Single-connection fake: the "transaction" is just the db itself.
  db.transaction = async (fn) => fn(db);
  db.raw = async () => [[{ 1: 1 }]];

  return { db, tables };
}

export function fakeRedis() {
  return { ping: async () => 'PONG' };
}
