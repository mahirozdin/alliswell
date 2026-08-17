import { describe, it, expect } from 'vitest';
import { transactionWithRetry } from '../../src/db/tx.js';

/**
 * OPH-274: the deadlock restart MySQL's manual asks for.
 *
 * Measured trigger: a 500-item import running beside other note writers lost 9
 * scattered items to ER_LOCK_DEADLOCK (1213), each reported as an opaque
 * IMPORT_ITEM_FAILED. The victim's transaction was fully rolled back, so
 * re-running it was always the correct response — it just was not happening.
 */

const deadlock = () => Object.assign(new Error('Deadlock found'), { errno: 1213 });

/** A db whose transaction fails N times with `err` before succeeding. */
const flaky = (times, err = deadlock()) => {
  let calls = 0;
  return {
    calls: () => calls,
    transaction: async (fn) => {
      calls += 1;
      if (calls <= times) throw err;
      return fn('trx');
    },
  };
};

const instant = () => Promise.resolve();

describe('transactionWithRetry', () => {
  it('restarts a deadlock victim and returns the retried result', async () => {
    const db = flaky(2);
    const out = await transactionWithRetry(db, async (trx) => `ran in ${trx}`, {
      sleep: instant,
    });
    expect(out).toBe('ran in trx');
    expect(db.calls()).toBe(3);
  });

  it('gives up after the attempt budget, loudly', async () => {
    const db = flaky(99);
    await expect(
      transactionWithRetry(db, async () => 'never', { attempts: 3, sleep: instant }),
    ).rejects.toMatchObject({ errno: 1213 });
    expect(db.calls()).toBe(3);
  });

  it('does not retry anything that is not a deadlock', async () => {
    // 1205 (lock wait timeout) rolls back only the STATEMENT by default — a
    // "retry" would re-enter on top of a half-open transaction. It must
    // propagate, like every other error.
    const db = flaky(1, Object.assign(new Error('Lock wait timeout'), { errno: 1205 }));
    await expect(
      transactionWithRetry(db, async () => 'never', { sleep: instant }),
    ).rejects.toMatchObject({ errno: 1205 });
    expect(db.calls()).toBe(1);
  });

  it('a clean first run costs exactly one transaction', async () => {
    const db = flaky(0);
    expect(await transactionWithRetry(db, async () => 42, { sleep: instant })).toBe(42);
    expect(db.calls()).toBe(1);
  });
});
