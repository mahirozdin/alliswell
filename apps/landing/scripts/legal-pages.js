import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { marked } from 'marked';

/**
 * Renders the repo's legal/support markdown into real static HTML pages.
 *
 * The App Store and Google Play both fetch the privacy and support URLs during
 * review and reject a 404 or a redirect to raw GitHub — so these have to be
 * pages on our own domain. They are generated from `docs/*.md` rather than
 * retyped into components for one reason: a privacy policy that says one thing
 * in the repo and another on the website is worse than having only one of them.
 * One source, two renderings.
 *
 * Static HTML, not a Vue route: legal text has no interactivity, and a page a
 * reviewer can read with JavaScript disabled is one less thing to explain.
 */

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '../../..');

/** route → { source markdown, <title>, description, and its language twin } */
export const LEGAL_PAGES = [
  {
    route: 'privacy',
    file: 'docs/PRIVACY.md',
    title: 'Privacy Policy — AllisWell',
    description:
      'What AllisWell collects, why, how long it is kept, and how to get it deleted. GDPR and KVKK.',
    lang: 'en',
    alternates: [
      { label: 'English', href: '/privacy' },
      { label: 'Türkçe', href: '/privacy/tr' },
    ],
  },
  {
    route: 'privacy/tr',
    file: 'docs/PRIVACY.tr.md',
    title: 'Gizlilik Politikası — AllisWell',
    description:
      'AllisWell hangi verileri neden topluyor, ne kadar saklıyor ve nasıl sildiriyorsunuz. KVKK ve GDPR.',
    lang: 'tr',
    alternates: [
      { label: 'English', href: '/privacy' },
      { label: 'Türkçe', href: '/privacy/tr' },
    ],
  },
  {
    route: 'support',
    file: 'docs/SUPPORT.md',
    title: 'Support — AllisWell',
    description:
      'How to reach us, what to include in a bug report, and answers to the questions people actually ask.',
    lang: 'en',
    alternates: [
      { label: 'English', href: '/support' },
      { label: 'Türkçe', href: '/support/tr' },
    ],
  },
  {
    route: 'support/tr',
    file: 'docs/SUPPORT.tr.md',
    title: 'Destek — AllisWell',
    description:
      'Bize nasıl ulaşırsınız, hata bildirirken neye ihtiyacımız var ve sık sorulan soruların yanıtları.',
    lang: 'tr',
    alternates: [
      { label: 'English', href: '/support' },
      { label: 'Türkçe', href: '/support/tr' },
    ],
  },
];

/**
 * Rewrites the markdown's repo-relative links so they work on the website.
 *
 * `docs/PRIVACY.md` links to its siblings as `PRIVACY.tr.md` and to the repo
 * root as `../SECURITY.md`. On the site the first must become a route and the
 * second must point at GitHub — otherwise every link in a legal document 404s,
 * which is exactly what a store reviewer clicks.
 */
const REPO = 'https://github.com/mahirozdin/alliswell/blob/main';
const ROUTE_FOR = new Map([
  ['PRIVACY.md', '/privacy'],
  ['PRIVACY.tr.md', '/privacy/tr'],
  ['SUPPORT.md', '/support'],
  ['SUPPORT.tr.md', '/support/tr'],
]);

function rewriteLink(href) {
  if (/^(https?:|mailto:|#|\/)/.test(href)) return href;
  const [pathPart, hash = ''] = href.split('#');
  const base = pathPart.replace(/^\.\//, '');
  if (ROUTE_FOR.has(base)) return ROUTE_FOR.get(base) + (hash ? `#${hash}` : '');
  if (base.startsWith('../')) return `${REPO}/${base.slice(3)}${hash ? `#${hash}` : ''}`;
  return `${REPO}/docs/${base}${hash ? `#${hash}` : ''}`;
}

function shell({ title, description, lang, alternates, route, body }) {
  const canonical = `https://alliswell.space/${route}`;
  const nav = alternates
    .map(
      (a) =>
        `<a href="${a.href}"${a.href === `/${route}` ? ' aria-current="page"' : ''}>${a.label}</a>`,
    )
    .join('');
  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="theme-color" content="#0B1233" media="(prefers-color-scheme: dark)">
<meta name="theme-color" content="#E9F2FF" media="(prefers-color-scheme: light)">
<title>${title}</title>
<meta name="description" content="${description}">
<link rel="canonical" href="${canonical}">
${alternates.map((a) => `<link rel="alternate" hreflang="${a.href.endsWith('/tr') ? 'tr' : 'en'}" href="https://alliswell.space${a.href}">`).join('\n')}
<meta property="og:title" content="${title}">
<meta property="og:description" content="${description}">
<meta property="og:url" content="${canonical}">
<link rel="icon" type="image/svg+xml" href="/logo.svg">
<link rel="stylesheet" href="/legal.css">
</head>
<body>
<header class="doc__top">
  <a class="doc__brand" href="/">
    <svg width="26" height="26" viewBox="0 0 64 64" aria-hidden="true">
      <defs><linearGradient id="m" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0%" stop-color="#2563EB"/><stop offset="100%" stop-color="#6D3DEB"/>
      </linearGradient></defs>
      <rect width="64" height="64" rx="16" fill="url(#m)"/>
      <path d="M18 33.5 27.5 43 46 22" fill="none" stroke="#fff" stroke-width="6.5"
            stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
    <span>AllisWell</span>
  </a>
  <nav class="doc__langs" aria-label="Language">${nav}</nav>
</header>
<main class="doc">
${body}
</main>
<footer class="doc__foot">
  <p>
    <a href="/">alliswell.space</a> ·
    <a href="/app">Open the app</a> ·
    <a href="/privacy">Privacy</a> ·
    <a href="/support">Support</a> ·
    <a href="https://github.com/mahirozdin/alliswell">GitHub</a>
  </p>
  <!--email_off--><p>BUBIAPSS BILGI TEKNOLOJILERI ARGE LIMITED SIRKETI · Talas / Kayseri · Türkiye ·
     <a href="mailto:info@bubiapps.com">info@bubiapps.com</a></p><!--/email_off-->
</footer>
</body>
</html>
`;
}

/**
 * Opts the whole document out of Cloudflare's Email Address Obfuscation.
 *
 * That feature is on by default for the zone and rewrites every address it
 * finds into the literal string "[email protected]" plus a decoder script — so
 * with JavaScript off, the mandatory contact field of the privacy policy reads
 * `[email protected]`. These pages are static and JS-free precisely so a store
 * reviewer or an automated validator can read them; obfuscation put the JS
 * dependency back on the single line that matters most.
 *
 * `<!--email_off-->` is Cloudflare's documented opt-out and is scoped to this
 * markup, so it keeps working regardless of what the dashboard setting is later
 * changed to. It stays a comment in the HTML — harmless anywhere else.
 */
function keepEmailsReadable(html) {
  return `<!--email_off-->\n${html}\n<!--/email_off-->`;
}

export function renderLegalPage(page) {
  const md = readFileSync(path.join(repoRoot, page.file), 'utf8');

  const renderer = new marked.Renderer();
  const baseLink = renderer.link.bind(renderer);
  renderer.link = (token) => baseLink({ ...token, href: rewriteLink(token.href) });

  const body = keepEmailsReadable(
    marked.parse(md, { renderer, gfm: true, mangle: false, headerIds: true }),
  );
  return shell({ ...page, body });
}

/**
 * Vite plugin: emits every legal page into the bundle, and serves them from the
 * dev server so `npm run landing:dev` shows the same thing the deploy will.
 */
export function legalPagesPlugin() {
  return {
    name: 'alliswell-legal-pages',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const url = (req.url ?? '').split('?')[0].replace(/\/$/, '');
        const page = LEGAL_PAGES.find((p) => url === `/${p.route}`);
        if (!page) return next();
        res.setHeader('Content-Type', 'text/html; charset=utf-8');
        res.end(renderLegalPage(page));
      });
    },
    generateBundle() {
      for (const page of LEGAL_PAGES) {
        this.emitFile({
          type: 'asset',
          fileName: `${page.route}/index.html`,
          source: renderLegalPage(page),
        });
      }
    },
  };
}
