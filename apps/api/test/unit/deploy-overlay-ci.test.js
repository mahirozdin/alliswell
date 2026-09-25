import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

import {
  DEFAULT_WORKFLOW,
  VERDICTS,
  checkOverlay,
  decide,
  main,
  verdictSentence,
} from '../../../../scripts/deploy/overlay-ci.mjs';

/// OPH-345 — the deploy's last gate: an overlay commit whose own CI has not
/// passed does not reach a server.
///
/// The decision is pure and every case is a fixture in the shape GitHub
/// returns (`GET /repos/:repo/actions/runs?head_sha=:sha`), so the four
/// verdicts are read, not believed. The step itself (`main`) is driven end to
/// end with a fake `fetch` and captured outputs: what it prints, what it
/// writes for the next steps, and the exit code the job stops on.

const fixture = (name) =>
  JSON.parse(
    readFileSync(
      fileURLToPath(new URL(`../fixtures/overlay-ci/${name}.json`, import.meta.url)),
      'utf8',
    ),
  );
const SHA = fixture('commit').sha;

/** A GitHub that answers the two questions the gate asks, and records them. */
function fakeGitHub({ runs = 'green', commitStatus = 200, runsStatus = 200 } = {}) {
  const asked = [];
  const fetchImpl = async (url, init) => {
    asked.push({ url, auth: init.headers.authorization });
    const answer = (status, body) => ({
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
    });
    if (url.includes('/actions/runs')) return answer(runsStatus, fixture(runs));
    return answer(commitStatus, fixture('commit'));
  };
  return { fetchImpl, asked };
}

/** The job's environment, with its two files captured instead of written. */
function job(env = {}) {
  const files = { '/out': '', '/summary': '' };
  const lines = [];
  return {
    env: {
      OVERLAY_REPO: 'owner/overlay',
      OVERLAY_REF: 'main',
      OVERLAY_TOKEN: 'ghp_test',
      GITHUB_OUTPUT: '/out',
      GITHUB_STEP_SUMMARY: '/summary',
      ...env,
    },
    append: (path, text) => {
      files[path] += text;
    },
    log: { log: (line) => lines.push(line) },
    files,
    lines,
  };
}

describe('the verdict is read from the commit’s own CI runs', () => {
  test('the four verdicts, one fixture each', () => {
    expect(decide(fixture('green').workflow_runs).verdict).toBe('green');
    expect(decide(fixture('red').workflow_runs).verdict).toBe('red');
    expect(decide(fixture('pending').workflow_runs).verdict).toBe('pending');
    expect(decide(fixture('none').workflow_runs).verdict).toBe('none');
    expect(VERDICTS).toEqual(['green', 'red', 'pending', 'none']);
  });

  test('only the overlay’s CI counts — another workflow failing or passing says nothing', () => {
    // green.json carries a failed bench run beside the passed CI run; none.json
    // carries ONLY a passed bench run. The first is green and the second is
    // not: a workflow that is not the gate cannot open it.
    expect(decide(fixture('green').workflow_runs)).toMatchObject({
      verdict: 'green',
      run: { id: 101 },
    });
    expect(decide(fixture('none').workflow_runs)).toEqual({ verdict: 'none', run: null });
  });

  test('the newest run decides, whatever order GitHub lists them in', () => {
    const runs = fixture('rerun').workflow_runs;
    expect(decide(runs)).toMatchObject({ verdict: 'green', run: { id: 502 } });
    expect(decide([...runs].reverse())).toMatchObject({ verdict: 'green', run: { id: 502 } });
  });

  test('the workflow is named, and the name can be changed without a code change', () => {
    expect(DEFAULT_WORKFLOW).toBe('EE CI');
    // Only the CI's own runs are renamed — the bench run beside it stays what it is.
    const renamed = fixture('green').workflow_runs.map((r) =>
      r.name === 'EE CI' ? { ...r, name: 'Overlay CI' } : r,
    );
    expect(decide(renamed).verdict).toBe('none');
    expect(decide(renamed, { workflow: 'Overlay CI' }).verdict).toBe('green');
  });

  test('an empty or missing list is "none", never green', () => {
    expect(decide([]).verdict).toBe('none');
    expect(decide(undefined).verdict).toBe('none');
  });
});

describe('the ref is resolved to one commit, and that commit is what is judged', () => {
  test('ref → SHA, then the runs of THAT SHA', async () => {
    const github = fakeGitHub();
    const result = await checkOverlay({
      repo: 'owner/overlay',
      ref: 'release/2',
      token: 'ghp_test',
      fetchImpl: github.fetchImpl,
    });
    expect(result).toMatchObject({ sha: SHA, verdict: 'green' });
    // A ref with a slash keeps its slash; each segment is escaped on its own.
    expect(github.asked[0].url).toBe(
      'https://api.github.com/repos/owner/overlay/commits/release/2',
    );
    expect(github.asked[1].url).toContain(`/actions/runs?head_sha=${SHA}`);
    expect(github.asked.every((q) => q.auth === 'Bearer ghp_test')).toBe(true);
  });
});

describe('the step: what it writes, what it prints, and where the job stops', () => {
  test('AW-E23: the overlay’s main is red, so the deploy stops before the server and says why', async () => {
    const j = job();
    const code = await main({ ...j, fetchImpl: fakeGitHub({ runs: 'red' }).fetchImpl });
    expect(code).toBe(1);
    expect(j.files['/out']).toContain(`sha=${SHA}`);
    expect(j.files['/out']).toContain('verdict=red');
    expect(j.files['/summary']).toContain('ended "failure"');
    expect(j.files['/summary']).toContain('not deployed');
    expect(j.lines.some((l) => l.startsWith('::error::'))).toBe(true);
  });

  test('AW-E23: when it is green the commit ships, and its SHA is in the deploy summary', async () => {
    const j = job();
    const code = await main({ ...j, fetchImpl: fakeGitHub({ runs: 'green' }).fetchImpl });
    expect(code).toBe(0);
    expect(j.files['/out']).toContain(`sha=${SHA}`);
    expect(j.files['/out']).toContain('verdict=green');
    expect(j.files['/out']).toContain('run_id=101');
    expect(j.files['/summary']).toContain(SHA.slice(0, 12));
    expect(j.files['/summary']).toContain('this commit is deployed');
  });

  test('still running, or never run: not deployed either', async () => {
    for (const [runs, words] of [
      ['pending', 'still in_progress'],
      ['none', 'never ran on this commit'],
    ]) {
      const j = job();
      expect(await main({ ...j, fetchImpl: fakeGitHub({ runs }).fetchImpl })).toBe(1);
      expect(j.files['/summary']).toContain(words);
    }
  });

  test('a token that cannot read the runs is refused by name — never read as "no CI"', async () => {
    const j = job();
    const code = await main({ ...j, fetchImpl: fakeGitHub({ runsStatus: 403 }).fetchImpl });
    expect(code).toBe(1);
    expect(j.files['/out']).toContain('verdict=error');
    expect(j.files['/summary']).toContain('Actions: read');
  });

  test('a ref the overlay does not have says so', async () => {
    const j = job({ OVERLAY_REF: 'v9.9.9' });
    const code = await main({ ...j, fetchImpl: fakeGitHub({ commitStatus: 422 }).fetchImpl });
    expect(code).toBe(1);
    expect(j.files['/summary']).toContain('no commit for ref "v9.9.9"');
  });

  test('no overlay configured: the plain build ships, and nothing is asked', async () => {
    const j = job({ OVERLAY_REPO: '' });
    const github = fakeGitHub();
    expect(await main({ ...j, fetchImpl: github.fetchImpl })).toBe(0);
    expect(github.asked).toEqual([]);
    expect(j.files['/out']).toBe('verdict=skipped\n');
  });

  test('the private repository’s name never reaches the public summary', async () => {
    // DEPLOY_OVERLAY_REPO is a secret so that this public repository's Actions
    // pages do not name it. Every verdict, and every refusal, is checked.
    const secretName = 'acme/secret-overlay';
    const cases = [
      { runs: 'green' },
      { runs: 'red' },
      { runs: 'pending' },
      { runs: 'none' },
      { runsStatus: 403 },
      { commitStatus: 404 },
      { commitStatus: 401 },
    ];
    for (const options of cases) {
      const j = job({ OVERLAY_REPO: secretName });
      await main({ ...j, fetchImpl: fakeGitHub(options).fetchImpl });
      expect(j.files['/summary']).not.toContain('secret-overlay');
      expect(j.files['/summary']).not.toContain('acme');
    }
    expect(verdictSentence({ verdict: 'green', run: { id: 1 }, ref: 'main', sha: SHA })).toMatch(
      /^overlay@main → /,
    );
  });
});

describe('deploy.yml wires the gate where it can stop the deploy', () => {
  // A gate the workflow does not run is not a gate — it is a claim. These are
  // source reads of the workflow, the one file that decides what reaches the
  // server; `actionlint` checks its syntax, this checks its meaning.
  const workflow = readFileSync(
    fileURLToPath(new URL('../../../../.github/workflows/deploy.yml', import.meta.url)),
    'utf8',
  );
  const at = (needle) => {
    const index = workflow.indexOf(needle);
    expect(index, `deploy.yml no longer contains: ${needle}`).toBeGreaterThan(-1);
    return index;
  };

  test('the check runs first, for every overlay deploy, from the workflow’s own commit', () => {
    const gate = at("- name: Check the overlay's CI");
    // Before any build — a deploy that will stop stops in seconds — and before
    // the payload that carries the overlay to the server.
    expect(gate).toBeLessThan(at('- name: Build the web bundle for production'));
    expect(gate).toBeLessThan(at('- name: Prepare the overlay payload'));
    const step = workflow.slice(gate, at('- name: Build the web bundle for production'));
    expect(step).toContain("if: env.OVERLAY_REPO != ''");
    expect(step).toContain('id: overlay_ci');
    expect(step).toContain('git show "$WORKFLOW_SHA:scripts/deploy/overlay-ci.mjs"');
    expect(step).toContain('node "$RUNNER_TEMP/overlay-ci.mjs"');
    expect(step).toContain('WORKFLOW_SHA: ${{ github.workflow_sha }}');
  });

  test('the server is handed the CHECKED commit, and refuses to deploy without one', () => {
    at("OVERLAY_SHA='${{ steps.overlay_ci.outputs.sha }}'");
    at('SHA="${OVERLAY_SHA:-}"');
    at('[ -n "$SHA" ] || {');
    // The ref is still read — but only to warn that it moved, never to choose
    // the commit. A `SHA=` taken from the ref again would reopen the race.
    expect(workflow).not.toMatch(/SHA=\$\(git -C "\$OVERLAY_DIR" rev-parse/);
    at('git -C "$OVERLAY_DIR" checkout -f --quiet "$SHA"');
  });
});
