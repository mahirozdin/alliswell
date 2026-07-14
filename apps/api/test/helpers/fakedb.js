/**
 * Minimal in-memory stand-in for the knex surface the auth routes use
 * (`db(table).where().first()`, `db.transaction()`, `trx(table).insert()`),
 * so unit tests run without MySQL (AGENTS.md §5). It enforces the
 * `uq_users_email` unique index the way mysql2 reports it (ER_DUP_ENTRY).
 */
export function fakeDb({ hideUsersFromPrecheck = false } = {}) {
  const tables = {
    users: [],
    workspaces: [],
    workspace_members: [],
    refresh_tokens: [],
  };

  const matches = (row, cond) => Object.entries(cond).every(([key, val]) => row[key] === val);

  const builder = (name) => ({
    where(cond) {
      return {
        // `first('id')` & friends — column selection is irrelevant to the fake.
        async first() {
          if (name === 'users' && hideUsersFromPrecheck) return undefined;
          return tables[name].find((row) => matches(row, cond));
        },
      };
    },
    async insert(row) {
      if (name === 'users' && tables.users.some((u) => u.email === row.email)) {
        const err = new Error(`Duplicate entry '${row.email}' for key 'users.uq_users_email'`);
        err.code = 'ER_DUP_ENTRY';
        err.errno = 1062;
        throw err;
      }
      tables[name].push({ ...row });
      return [1];
    },
  });

  const db = (name) => {
    if (!tables[name]) throw new Error(`fakeDb: unknown table "${name}"`);
    return builder(name);
  };
  // Single-connection fake: the "transaction" is just the db itself. Rollback is not
  // simulated — tests that need partial-failure semantics belong in test/integration.
  db.transaction = async (fn) => fn(db);
  db.raw = async () => [[{ 1: 1 }]];

  return { db, tables };
}

export function fakeRedis() {
  return { ping: async () => 'PONG' };
}
