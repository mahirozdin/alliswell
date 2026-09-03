import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { marked } from 'marked';

/**
 * Renders repo markdown into real static HTML pages.
 *
 * It began as the legal pages only. The App Store and Google Play both fetch
 * the privacy and support URLs during review and reject a 404 or a redirect to
 * raw GitHub — so those have to be pages on our own domain. They are generated
 * from `docs/*.md` rather than retyped into components for one reason: a
 * privacy policy that says one thing in the repo and another on the website is
 * worse than having only one of them. One source, two renderings.
 *
 * `/enterprise` (EE-119) joined them because it wants exactly the same three
 * properties and none of the Vue app's: it must be indexable, it must read
 * with JavaScript off, and it must exist in Turkish. The Vue site has no i18n
 * layer at all — `src/content.js` is one English file that has always said the
 * copy could be "translated later", and later never came — so the only route
 * to a Turkish page on this site is the one the legal pages already take: a
 * second markdown source at a second route, with hreflang between them.
 *
 * What it did NOT want was the legal chrome. A privacy policy and a sales page
 * are both documents, but they are not the same document: one is read under
 * duress at 46rem, the other is skimmed. So `shell()` now takes its
 * stylesheets from the page instead of hard-coding one, and `enterprise.css`
 * layers over the shared base rather than replacing it. Copying this file into
 * a near-identical sibling was the other option and it is the one this repo has
 * already paid for once (see sync-screenshots.mjs on why two copies drift).
 */

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, '../../..');

/** The shared document base. Every generated page loads it. */
const BASE_STYLES = ['/legal.css'];

/**
 * Every page this plugin emits — the single list the build, the dev server and
 * CI all read.
 *
 * CI reads it by importing this module rather than repeating the routes in
 * bash. That is deliberate: the gate that guarded these pages used to carry its
 * own hand-typed copy of the list, so a page added here was a page nothing
 * checked. A gate whose set excludes the new thing is indistinguishable from a
 * passing gate — this repo has now watched that happen five times.
 *
 * route → { source markdown, <title>, description, language twin, stylesheets }
 */
export const STATIC_PAGES = [
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
  {
    route: 'enterprise',
    file: 'docs/ENTERPRISE.md',
    title: 'AllisWell Enterprise — service desk, units and SLAs on your own servers',
    description:
      'Teams, subdomains, permissions, units, ITSM with SLAs and service health, a public request portal and meeting-note AI — self-hosted, offline-first, on your own database.',
    lang: 'en',
    styles: [...BASE_STYLES, '/enterprise.css'],
    alternates: [
      { label: 'English', href: '/enterprise' },
      { label: 'Türkçe', href: '/enterprise/tr' },
    ],
  },
  {
    // OPH-295: the public REST reference. English only — the file is
    // generated from the server's own route schemas (ADR-0035), and a second
    // language would be a second generator plus a translation that goes stale
    // the first time a schema changes.
    route: 'docs/api',
    file: 'docs/API.md',
    title: 'AllisWell REST API — endpoints, examples and a Postman collection',
    description:
      'The full REST API behind AllisWell: personal API keys, every endpoint ' +
      'with its parameters, request and response examples, error codes, rate ' +
      'limits and a downloadable Postman collection.',
    lang: 'en',
    styles: [...BASE_STYLES, '/api-docs-1.css'],
  },
  {
    route: 'enterprise/tr',
    file: 'docs/ENTERPRISE.tr.md',
    title: 'AllisWell Enterprise — kendi sunucunuzda servis masası, birimler ve SLA',
    description:
      "Team'ler, subdomain, izinler, birimler, SLA'lı ve sağlık izlemeli ITSM, public talep portalı ve toplantı notu AI'ı — kendi veritabanınızda, çevrimdışı çalışan bir kurulum.",
    lang: 'tr',
    styles: [...BASE_STYLES, '/enterprise.css'],
    alternates: [
      { label: 'English', href: '/enterprise' },
      { label: 'Türkçe', href: '/enterprise/tr' },
    ],
  },
];

/**
 * The subset Apple and Google FETCH during review. They carry obligations the
 * marketing pages do not (a reachable contact address, a named data
 * controller), so the CI gate that asserts those reads this list and not the
 * one above.
 */
export const STORE_REQUIRED_ROUTES = Object.freeze([
  'privacy',
  'privacy/tr',
  'support',
  'support/tr',
]);

/**
 * Rewrites the markdown's repo-relative links so they work on the website.
 *
 * `docs/PRIVACY.md` links to its siblings as `PRIVACY.tr.md` and to the repo
 * root as `../SECURITY.md`. On the site the first must become a route and the
 * second must point at GitHub — otherwise every link in a legal document 404s,
 * which is exactly what a store reviewer clicks.
 *
 * The filename→route map is DERIVED from STATIC_PAGES rather than typed out
 * again, so adding a page cannot leave its inbound links pointing at a raw .md.
 */
const REPO = 'https://github.com/mahirozdin/alliswell/blob/main';
const ROUTE_FOR = new Map(STATIC_PAGES.map((p) => [path.basename(p.file), `/${p.route}`]));

function rewriteLink(href) {
  if (/^(https?:|mailto:|#|\/)/.test(href)) return href;
  const [pathPart, hash = ''] = href.split('#');
  const base = pathPart.replace(/^\.\//, '');
  if (ROUTE_FOR.has(base)) return ROUTE_FOR.get(base) + (hash ? `#${hash}` : '');
  if (base.startsWith('../')) return `${REPO}/${base.slice(3)}${hash ? `#${hash}` : ''}`;
  return `${REPO}/docs/${base}${hash ? `#${hash}` : ''}`;
}

function shell({
  title,
  description,
  lang,
  // OPH-295: optional. Every page here used to come in a pair, so a language
  // pill and an hreflang set were unconditional. The API reference is
  // generated from the server's route schemas and exists in English only —
  // and a switcher offering one language, or an hreflang pointing at a
  // translation that does not exist, would both be lies told to a reader and
  // to a crawler.
  alternates = [],
  route,
  body,
  styles = BASE_STYLES,
}) {
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
${styles.map((s) => `<link rel="stylesheet" href="${s}">`).join('\n')}
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

export function renderStaticPage(page) {
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
 * Vite plugin: emits every static page into the bundle, and serves them from
 * the dev server so `npm run landing:dev` shows the same thing the deploy will.
 */
export function staticPagesPlugin() {
  return {
    name: 'alliswell-static-pages',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const url = (req.url ?? '').split('?')[0].replace(/\/$/, '');
        const page = STATIC_PAGES.find((p) => url === `/${p.route}`);
        if (!page) return next();
        res.setHeader('Content-Type', 'text/html; charset=utf-8');
        res.end(renderStaticPage(page));
      });
    },
    generateBundle() {
      for (const page of STATIC_PAGES) {
        this.emitFile({
          type: 'asset',
          fileName: `${page.route}/index.html`,
          source: renderStaticPage(page),
        });
      }
    },
  };
}
