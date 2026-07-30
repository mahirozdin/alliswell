# ADR-0024 — PolyForm Noncommercial replaces AGPL-3.0

- **Status:** Accepted — **supersedes [ADR-0002](0002-license-agpl-3.0.md)**
- **Date:** 2026-07-31
- **Related task:** owner decision (not a TASKS.md item)

## Context

ADR-0002 chose AGPL-3.0 in July 2026 on the premise that the project "must be
genuinely open source". That premise has changed: AllisWell is being
**productised**. It will be sold as a hosted service on `alliswell.space` and
published as a paid/freemium app on the App Store and Google Play by
**BUBIAPSS BILGI TEKNOLOJILERI ARGE LIMITED SIRKETI** (trading as BubiApps).

AGPL does not stop that — the copyright holder is not bound by their own licence
— but it also does not stop anyone else. Under AGPL a competitor may take the
whole product, host it commercially, sell it, and satisfy the licence merely by
publishing their changes. For a single-maintainer product whose entire revenue
model is hosting and store sales, that is the failure mode the licence exists to
prevent, and AGPL does not prevent it.

Three facts made the change practical rather than theoretical:

1. **The copyright is undivided.** All 195 commits are by one author
   (`Mahir Taha Özdin <mahirozdin@bubiapps.com>`). There are no third-party
   contributions whose consent would be needed to relicense.
2. **No dependency blocks it.** 365 npm packages and 185 Dart packages were
   scanned: no GPL, AGPL, LGPL or SSPL anywhere. The only weak-copyleft hit is
   `dbus` (MPL-2.0, Linux secret storage), and MPL's copyleft is file-level — it
   reaches modifications to *those files*, not to AllisWell's own source.
3. **AGPL was a live risk for the store plan.** The GPL family's anti-DRM and
   redistribution terms conflict with the App Store's ToS. Shipping our own build
   is legal (we own the copyright), but every AGPL dependency question in a
   review becomes ours to answer. Removing the family removes the question.

## Decision

License the repository under **PolyForm Noncommercial 1.0.0** from **v1.0.0**
onward, with a Required Notice naming the company as copyright holder.

Under it, **free** covers: personal use, hobby projects, private study,
self-hosting your own instance, plus charities, schools, universities, public
research and government bodies. **Not free** covers: use inside a business,
resale, and offering the software as a service. Those need a commercial licence
from `info@bubiapps.com`.

Releases up to and including **v0.9.0** stay AGPL-3.0 for anyone who received
them; a granted licence cannot be withdrawn. This is stated in `LICENSE` rather
than left implicit.

## Alternatives considered

Each was rejected for a specific reason, not on feel:

- **FSL-1.1-ALv2** (free except competing use; auto-converts to Apache-2.0 after
  two years). The best fit for keeping the self-hosting story true for
  *companies*, and the recommendation put to the owner. Rejected deliberately:
  self-hosting is positioned as an individual's feature, and enterprises are
  expected to make contact rather than help themselves.
- **Elastic License 2.0** (free including internal business use; forbids
  offering it as a managed service). Same objection, one step further — it hands
  a company unlimited internal use for free.
- **Keep AGPL-3.0 + sell a commercial exception** (MongoDB/Grafana model). Keeps
  OSI open-source status and its goodwill, but leaves a compliant competitor free
  to host and sell the product — exactly the risk being closed.
- **BSL 1.1.** Equivalent protection with a Change Date, but its "Additional Use
  Grant" is a bespoke clause every reader must interpret. PolyForm says the same
  thing in one sentence.

## Consequences

**The repository is no longer "open source" in the OSI sense.** PolyForm
Noncommercial discriminates against a field of endeavour (OSD §6), and that is
the point. Every surface that said "open source" now says **source-available**:
README, `apps/landing`, `docs/COMPARISON.md`, `docs/STORE-LISTING.md`,
`ROADMAP.md`, `package.json`, `apps/api/package.json`, `apps/app/pubspec.yaml`.
The comparison table's "Open source" row became "Source available" — the honest
claim, and still a row no competitor on that table can tick.

- **Easier:** store submission (no GPL-family question), a commercial licence to
  sell, and a defensible position if the product is copied.
- **Harder:** contribution appeal. Some contributors will not sign work over to a
  non-open licence; some package registries and distro repositories will not
  carry it. `CONTRIBUTING.md` now states plainly that contributions are accepted
  under these terms.
- **Follow-up:** GitHub will stop displaying a recognised licence badge and shows
  the repo as having a custom licence — expected, not a misconfiguration.
- **Unaffected:** the product itself. Nothing about self-hosting, the API, the
  data model or the docs changes; only who may use it commercially.
