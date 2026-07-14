/**
 * Minimal in-memory stand-in for the knex surface the API routes use, so unit
 * tests run without MySQL (AGENTS.md §5). Supported chain:
 *
 *   db(table)
 *     .where(obj) / .where(col, val) / .where(col, op, val)   op: < <= > >= <> like
 *     .whereNull(col) / .whereNot(col, val) / .whereIn(col, vals)
 *     .orderBy(col, dir) / .limit(n)
 *     → .first() / .select() / .update(patch) / .delete() / .increment(col, n) / .insert(row)
 *
 * plus db.transaction(fn) (no rollback simulation — partial-failure semantics
 * belong in test/integration). Unique indexes are enforced on insert the way
 * mysql2 reports them (ER_DUP_ENTRY + index name in the message).
 */

const UNIQUE_INDEXES = {
  users: [{ name: 'users.uq_users_email', cols: ['email'] }],
  tags: [{ name: 'tags.uq_tags_workspace_slug', cols: ['workspace_id', 'slug'] }],
  workspaces: [{ name: 'workspaces.uq_workspaces_slug', cols: ['slug'] }],
  sync_revisions: [
    { name: 'sync_revisions.uq_workspace_revision', cols: ['workspace_id', 'revision'] },
  ],
};

const OPS = {
  '<': (a, b) => a < b,
  '<=': (a, b) => a <= b,
  '>': (a, b) => a > b,
  '>=': (a, b) => a >= b,
  '<>': (a, b) => a !== b,
  like: (a, b) => typeof a === 'string' && new RegExp(`^${String(b).replace(/%/g, '.*')}$`).test(a),
};

export function fakeDb({ hideUsersFromPrecheck = false } = {}) {
  const tables = {
    users: [],
    workspaces: [],
    workspace_members: [],
    refresh_tokens: [],
    projects: [],
    tags: [],
    tasks: [],
    task_tags: [],
    checklist_items: [],
    reminders: [],
    sync_revisions: [],
  };

  const columnDefaults = {
    users: () => ({ timezone: 'Europe/Istanbul', locale: 'tr-TR' }),
    workspaces: () => ({ color_rgb: '#2563EB', revision: 0 }),
    projects: () => ({
      color_rgb: '#2563EB',
      status: 'active',
      sort_order: 0,
      is_favorite: false,
      description: null,
      icon: null,
      revision: 0,
    }),
    tags: () => ({ color_rgb: '#64748B', icon: null, revision: 0 }),
    tasks: () => ({
      status: 'open',
      priority: 'none',
      timezone: 'Europe/Istanbul',
      is_urgent: false,
      requires_acknowledgement: false,
      sort_order: 0,
      revision: 0,
      project_id: null,
      parent_task_id: null,
      description: null,
      completed_at: null,
    }),
    checklist_items: () => ({ is_done: false, sort_order: 0, revision: 0 }),
    reminders: () => ({
      timezone: 'Europe/Istanbul',
      alarm_level: 'normal',
      requires_acknowledgement: false,
      status: 'scheduled',
      revision: 0,
    }),
  };

  function assertUnique(name, candidate, rows) {
    for (const index of UNIQUE_INDEXES[name] ?? []) {
      const clash = rows.some((row) =>
        index.cols.every((col) => row[col] !== undefined && row[col] === candidate[col]),
      );
      if (clash) {
        const err = new Error(
          `Duplicate entry '${index.cols.map((c) => candidate[c]).join('-')}' for key '${index.name}'`,
        );
        err.code = 'ER_DUP_ENTRY';
        err.errno = 1062;
        throw err;
      }
    }
  }

  const builder = (name) => {
    const filters = [];
    const orderings = [];
    let limitCount = Infinity;

    const matching = () => {
      let rows = tables[name].filter((row) => filters.every((f) => f(row)));
      if (orderings.length > 0) {
        rows = [...rows].sort((a, b) => {
          for (const { col, dir } of orderings) {
            const [av, bv] = [a[col], b[col]];
            if (av === bv) continue;
            const cmp = av > bv ? 1 : -1;
            return dir === 'desc' ? -cmp : cmp;
          }
          return 0;
        });
      }
      return rows.slice(0, limitCount);
    };

    const api = {
      where(condOrCol, opOrVal, maybeVal) {
        if (typeof condOrCol === 'object') {
          filters.push((row) => Object.entries(condOrCol).every(([key, val]) => row[key] === val));
        } else if (maybeVal === undefined) {
          filters.push((row) => row[condOrCol] === opOrVal);
        } else {
          const op = OPS[opOrVal];
          if (!op) throw new Error(`fakeDb: unsupported operator "${opOrVal}"`);
          filters.push((row) => op(row[condOrCol], maybeVal));
        }
        return api;
      },
      whereNull(col) {
        filters.push((row) => row[col] === null || row[col] === undefined);
        return api;
      },
      whereNot(col, val) {
        filters.push((row) => row[col] !== val);
        return api;
      },
      whereIn(col, values) {
        filters.push((row) => values.includes(row[col]));
        return api;
      },
      orderBy(col, dir = 'asc') {
        orderings.push({ col, dir });
        return api;
      },
      limit(n) {
        limitCount = n;
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
      async increment(col, amount = 1) {
        const rows = matching();
        for (const row of rows) row[col] = Number(row[col] ?? 0) + amount;
        return rows.length;
      },
      async delete() {
        const doomed = new Set(matching());
        tables[name] = tables[name].filter((row) => !doomed.has(row));
        return doomed.size;
      },
      async insert(rowOrRows) {
        const rows = Array.isArray(rowOrRows) ? rowOrRows : [rowOrRows];
        for (const row of rows) {
          assertUnique(name, row, tables[name]);
          tables[name].push({
            created_at: new Date(),
            updated_at: new Date(),
            ...(columnDefaults[name]?.() ?? {}),
            ...row,
          });
        }
        return [rows.length];
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
