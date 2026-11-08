import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * OPH-412 (landing-audit K2): what the homepage may say about itself, counted
 * from the GitHub API when the site is built: the number of releases, the
 * month of the first one, and the stars.
 *
 * It never fails a build. No network, a rate limit or `AW_PROOF=off` gives
 * null, and the page prints its fixed line instead (src/home/proof.js). The
 * result is cached for an hour in node_modules/.cache so the client and the
 * SSR pass of one `landing:build` read the same numbers with one request.
 */

const API = 'https://api.github.com/repos/mahirozdin/alliswell';
const here = path.dirname(fileURLToPath(import.meta.url));
const CACHE = path.resolve(here, '../node_modules/.cache/landing-proof.json');
const CACHE_MS = 60 * 60 * 1000;
const PAGES = 10;

/**
 * Published releases only: a draft or a pre-release is not a release a
 * visitor can download.
 * @returns {{ releases: number, first: string } | null}
 */
export function summariseReleases(list) {
  const dates = (list ?? [])
    .filter((r) => r && !r.draft && !r.prerelease && typeof r.published_at === 'string')
    .map((r) => r.published_at)
    .sort();
  if (dates.length === 0) return null;
  return { releases: dates.length, first: dates[0].slice(0, 7) };
}

async function getJson(fetch, url, headers) {
  const res = await fetch(url, { headers, signal: AbortSignal.timeout(8000) });
  if (!res.ok) throw new Error(`${url} answered ${res.status}`);
  return res.json();
}

/**
 * @param {{ env?: Record<string, string|undefined>, fetch?: typeof globalThis.fetch, cache?: string | null, now?: number }} [opts]
 * @returns {Promise<{ releases: number, first: string, stars: number } | null>}
 */
export async function loadProof({ env = process.env, fetch = globalThis.fetch, cache = CACHE, now = Date.now() } = {}) {
  if (env.AW_PROOF === 'off') return null;
  if (cache) {
    try {
      const hit = JSON.parse(readFileSync(cache, 'utf8'));
      if (now - hit.at < CACHE_MS) return hit.proof;
    } catch {
      /* no cache yet */
    }
  }
  const headers = { accept: 'application/vnd.github+json', 'user-agent': 'alliswell-landing-build' };
  const token = env.GITHUB_TOKEN || env.GH_TOKEN;
  if (token) headers.authorization = `Bearer ${token}`;
  let proof = null;
  try {
    const repo = await getJson(fetch, API, headers);
    const releases = [];
    for (let page = 1; page <= PAGES; page += 1) {
      const batch = await getJson(fetch, `${API}/releases?per_page=100&page=${page}`, headers);
      if (!Array.isArray(batch)) break;
      releases.push(...batch);
      if (batch.length < 100) break;
    }
    const summary = summariseReleases(releases);
    if (summary && typeof repo?.stargazers_count === 'number') {
      proof = { ...summary, stars: repo.stargazers_count };
    }
  } catch (err) {
    console.warn(`proof: the GitHub API was not read (${err.message}); the page prints its fixed line`);
    return null;
  }
  if (cache && proof) {
    try {
      mkdirSync(path.dirname(cache), { recursive: true });
      writeFileSync(cache, JSON.stringify({ at: now, proof }));
    } catch {
      /* a read-only tree: the next pass asks again */
    }
  }
  return proof;
}
