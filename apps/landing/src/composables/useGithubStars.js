import { onMounted, ref } from 'vue';

const REPO = 'mahirozdin/alliswell';
const CACHE_KEY = 'aw_gh_stars_v1';
const CACHE_TTL_MS = 6 * 60 * 60 * 1000; // six hours

/**
 * Live star count for the repo, read straight from the public GitHub API.
 *
 * Deliberately NOT an iframe or a third-party badge image: both hand a visitor's
 * IP and referrer to somebody else on every page view, and both block the paint
 * until a foreign host answers. One `fetch` to api.github.com, cached in
 * localStorage for six hours, degrades to a plain "Star on GitHub" link when the
 * call is rate-limited (60/hour per IP unauthenticated) or blocked.
 */
export function useGithubStars() {
  const stars = ref(null);
  const forks = ref(null);
  const loaded = ref(false);

  const format = (n) =>
    n >= 1000 ? `${(n / 1000).toFixed(n >= 10000 ? 0 : 1).replace(/\.0$/, '')}k` : String(n);

  onMounted(async () => {
    try {
      const cached = JSON.parse(localStorage.getItem(CACHE_KEY) ?? 'null');
      if (cached && Date.now() - cached.at < CACHE_TTL_MS) {
        stars.value = cached.stars;
        forks.value = cached.forks;
        loaded.value = true;
        return;
      }
    } catch {
      /* unreadable cache is not an error worth surfacing */
    }

    try {
      const res = await fetch(`https://api.github.com/repos/${REPO}`, {
        headers: { accept: 'application/vnd.github+json' },
      });
      if (!res.ok) return;
      const data = await res.json();
      stars.value = data.stargazers_count ?? null;
      forks.value = data.forks_count ?? null;
      loaded.value = true;
      localStorage.setItem(
        CACHE_KEY,
        JSON.stringify({ at: Date.now(), stars: stars.value, forks: forks.value }),
      );
    } catch {
      /* offline, blocked or rate-limited — the link still works */
    }
  });

  return { stars, forks, loaded, format, repo: REPO };
}
