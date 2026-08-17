import { defineConfig } from 'vitest/config';

// Integration files run SEQUENTIALLY (OPH-274 finding). They all talk to the
// one real MySQL on :3307, and running the files in parallel workers made
// them each other's load test: InnoDB picked deadlock victims across files
// (ER_LOCK_DEADLOCK in bulk import; intermittent 500s in folder cascades and
// sync push under the same contention). The note domain retries deadlocks now
// — that part is a production fix, two real users can collide the same way —
// but a shared-database suite asserting exact outcomes was WRITTEN assuming
// isolation, and serializing the files is what makes that assumption true.
// Unit tests keep full parallelism: their db is a fake.
export default defineConfig({
  test: {
    environment: 'node',
    testTimeout: 15000,
    hookTimeout: 30000,
    fileParallelism: process.env.INTEGRATION !== '1',
  },
});
