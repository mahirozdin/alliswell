/**
 * Deadlock-safe transactions (OPH-274 finding).
 *
 * InnoDB resolves a deadlock by killing one of the participants with
 * ER_LOCK_DEADLOCK (1213) and rolling it back — and MySQL's own manual is
 * explicit that this is NORMAL operation: "always be prepared to reissue a
 * transaction if it fails due to deadlock." Two inserts into `notes` +
 * `note_versions` from different connections are enough (secondary-index gap
 * locks plus the FK's shared lock on the parent row take locks in different
 * orders), so this is not a test-suite artifact: two real users saving notes
 * concurrently hit the same thing.
 *
 * Measured before this existed: a 500-item import running while other
 * connections wrote notes lost 9 scattered items to 1213, each surfacing as an
 * opaque IMPORT_ITEM_FAILED.
 *
 * Only 1213 is retried. A rolled-back victim left nothing behind, so re-running
 * the closure from the top is exactly the restart MySQL asks for. Everything
 * else — including ER_LOCK_WAIT_TIMEOUT (1205), which by default rolls back
 * only the STATEMENT and would leave a half-open transaction to "retry" —
 * propagates untouched.
 *
 * The closure must not mutate outer state before it commits (ours build row
 * objects and return ids, so re-entry is clean). Bounded attempts with a
 * quadratic, jittered backoff. Five attempts, not three: measured under the
 * integration suite's full concurrency, a linear 20–50 ms backoff still lost
 * one item in three runs — the deadlocking neighbour holds its locks for
 * longer than that window, so the later waits have to outlast a WRITER, not a
 * scheduler blip. Worst case is ~1.3 s for one item, in a request that is
 * already seconds long; unbounded retry under genuine contention would just
 * be a slower outage.
 */

const DEADLOCK = 1213;

export async function transactionWithRetry(db, fn, { attempts = 5, sleep } = {}) {
  const wait = sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  for (let attempt = 1; ; attempt += 1) {
    try {
      return await db.transaction(fn);
    } catch (err) {
      if (err?.errno !== DEADLOCK || attempt >= attempts) throw err;
      await wait(attempt * attempt * 25 + Math.floor(Math.random() * 50));
    }
  }
}
