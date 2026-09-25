#!/usr/bin/env node
/**
 * OPH-345 — a deploy does not ship an overlay commit its own CI has not passed.
 *
 * The core half of a release reaches a server only through release.yml's gate:
 * the tests pass, then the tag, then deploy.yml. The optional overlay did not.
 * deploy.yml fetched whatever `DEPLOY_OVERLAY_REF` (default `main`) pointed at,
 * and nothing asked whether that commit's CI had passed. The overlay's own
 * repository cannot make its CI a merge requirement either — branch protection
 * is a plan feature there — so this is the last gate between a red commit and a
 * server, and it lives here.
 *
 * What it does, in the job, before anything reaches the server:
 *
 *   1. resolves the ref to ONE commit (`GET /repos/:repo/commits/:ref`);
 *   2. reads that commit's workflow runs and keeps the overlay CI's, by name
 *      (`DEPLOY_OVERLAY_CI_WORKFLOW`, default `EE CI`);
 *   3. decides — `green`: its newest run succeeded; `red`: it completed any
 *      other way; `pending`: it is still running; `none`: it never ran on this
 *      commit, and nothing vouches for it;
 *   4. writes the commit and the verdict to the job summary and to the step's
 *      outputs, and exits 0 only on `green`.
 *
 * The server then checks out THAT commit rather than resolving the ref again,
 * so what was checked is what ships even if the branch moves in between.
 *
 * The token is the one that already fetches the overlay (`DEPLOY_OVERLAY_TOKEN`).
 * It needs to read the repository's contents AND its Actions runs — a
 * fine-grained token with Contents and Actions, both read-only, or a classic
 * token with `repo`. A token that cannot read the runs is refused by name: a
 * missing permission read as "no CI" would be a gate that opens when it breaks.
 *
 * No dependencies and no imports beyond Node itself, on purpose: deploy.yml runs
 * this file as the version committed with the workflow, from a scratch
 * directory, whatever tag it happens to be deploying.
 */
import { appendFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export const DEFAULT_WORKFLOW = 'EE CI';

export const VERDICTS = Object.freeze(['green', 'red', 'pending', 'none']);

/**
 * The verdict for one commit's workflow runs — pure, so every case is a fixture.
 *
 * The NEWEST run of the named workflow decides. A re-run after a red one is the
 * answer the maintainer went and got, and a red push run after a green pull
 * request run on the same commit is the one that happened last. A re-run of the
 * same run (a new attempt) changes that run's own status, so it needs no rule.
 */
export function decide(runs, { workflow = DEFAULT_WORKFLOW } = {}) {
  const mine = (runs ?? []).filter((run) => run && run.name === workflow);
  if (mine.length === 0) return { verdict: 'none', run: null };
  const latest = mine.reduce((a, b) =>
    Date.parse(b.created_at) > Date.parse(a.created_at) ? b : a,
  );
  if (latest.status !== 'completed') return { verdict: 'pending', run: latest };
  return { verdict: latest.conclusion === 'success' ? 'green' : 'red', run: latest };
}

/**
 * The one sentence the job summary and the failure both say.
 *
 * It never names the repository. `DEPLOY_OVERLAY_REPO` is a secret because the
 * overlay's name must not appear in this public repository's Actions pages:
 * logs mask a secret's literal text, and a job summary is not somewhere to
 * rely on that — nor is a run's URL, which carries the name.
 */
export function verdictSentence({ verdict, run, ref, sha, workflow = DEFAULT_WORKFLOW }) {
  const at = `overlay@${ref} → ${String(sha).slice(0, 12)}`;
  const which = run ? ` (run ${run.id})` : '';
  switch (verdict) {
    case 'green':
      return `${at}: ${workflow} passed${which} — this commit is deployed.`;
    case 'red':
      return (
        `${at}: ${workflow} ended "${run.conclusion}"${which} — not deployed. ` +
        'Fix the overlay, or point DEPLOY_OVERLAY_REF at a commit whose CI passed.'
      );
    case 'pending':
      return `${at}: ${workflow} is still ${run.status}${which} — not deployed. Run the deploy again when it finishes.`;
    default:
      return `${at}: ${workflow} never ran on this commit — not deployed. Nothing vouches for it.`;
  }
}

/** A ref may hold slashes (`release/2`); each segment is escaped, not the whole. */
const refPath = (ref) => String(ref).split('/').map(encodeURIComponent).join('/');

class GitHubError extends Error {
  constructor(status, path) {
    super(`GitHub answered ${status} for ${path}`);
    this.status = status;
    this.path = path;
  }
}

async function github(path, { token, fetchImpl }) {
  const res = await fetchImpl(`https://api.github.com${path}`, {
    headers: {
      accept: 'application/vnd.github+json',
      authorization: `Bearer ${token}`,
      'x-github-api-version': '2022-11-28',
      'user-agent': 'alliswell-deploy-overlay-ci',
    },
  });
  if (!res.ok) throw new GitHubError(res.status, path);
  return res.json();
}

/**
 * Resolves the ref and decides. Throws a `GitHubError` the caller turns into a
 * sentence — which endpoint refused says which permission is missing.
 */
export async function checkOverlay({
  repo,
  ref,
  token,
  workflow = DEFAULT_WORKFLOW,
  fetchImpl = globalThis.fetch,
}) {
  const commit = await github(`/repos/${repo}/commits/${refPath(ref)}`, { token, fetchImpl });
  const sha = commit.sha;
  const listed = await github(`/repos/${repo}/actions/runs?head_sha=${sha}&per_page=100`, {
    token,
    fetchImpl,
  });
  return { sha, ...decide(listed.workflow_runs, { workflow }) };
}

/** What a refusal from GitHub means for this gate, in words an operator can act on. */
export function explainError(err, { ref }) {
  if (!(err instanceof GitHubError)) return `the overlay's CI could not be checked: ${err.message}`;
  if (err.path.includes('/actions/runs')) {
    return (
      `DEPLOY_OVERLAY_TOKEN cannot read the overlay's workflow runs (HTTP ${err.status}) — ` +
      'give it Actions: read (fine-grained) or `repo` (classic). The deploy stops rather than ' +
      'ship a commit nobody checked.'
    );
  }
  if (err.status === 404 || err.status === 422) {
    return `the overlay has no commit for ref "${ref}" (HTTP ${err.status}) — check DEPLOY_OVERLAY_REF.`;
  }
  return `DEPLOY_OVERLAY_TOKEN cannot read the overlay (HTTP ${err.status}) — it needs Contents: read.`;
}

/**
 * The step: reads the job's environment, writes the step's outputs and the job
 * summary, and returns the exit code. Injectable end to end for the suite.
 */
export async function main({
  env = process.env,
  fetchImpl = globalThis.fetch,
  append = appendFileSync,
  log = console,
} = {}) {
  const repo = env.OVERLAY_REPO ?? '';
  const ref = env.OVERLAY_REF || 'main';
  const workflow = env.OVERLAY_CI_WORKFLOW || DEFAULT_WORKFLOW;
  const summary = (line) => env.GITHUB_STEP_SUMMARY && append(env.GITHUB_STEP_SUMMARY, `${line}\n`);
  const output = (key, value) =>
    env.GITHUB_OUTPUT && append(env.GITHUB_OUTPUT, `${key}=${value}\n`);

  // No overlay configured: the plain build ships, exactly as before this gate.
  if (!repo) {
    log.log('overlay: none configured — nothing to check');
    output('verdict', 'skipped');
    return 0;
  }
  if (!env.OVERLAY_TOKEN) {
    log.log(
      '::error::secrets.DEPLOY_OVERLAY_TOKEN is not set — the overlay cannot be checked or fetched',
    );
    return 1;
  }

  let result;
  try {
    result = await checkOverlay({ repo, ref, token: env.OVERLAY_TOKEN, workflow, fetchImpl });
  } catch (err) {
    const sentence = explainError(err, { ref });
    log.log(`::error::${sentence}`);
    summary(`### Overlay\n\n${sentence}`);
    output('verdict', 'error');
    return 1;
  }

  const sentence = verdictSentence({ ...result, ref, workflow });
  output('sha', result.sha);
  output('verdict', result.verdict);
  if (result.run) output('run_id', result.run.id);
  summary(`### Overlay\n\n${sentence}`);
  if (result.verdict !== 'green') {
    log.log(`::error::${sentence}`);
    return 1;
  }
  log.log(`overlay: ${sentence}`);
  return 0;
}

// Importing this file — which the suite does — must not run it.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await main();
}
