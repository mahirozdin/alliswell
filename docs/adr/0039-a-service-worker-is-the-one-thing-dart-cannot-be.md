# ADR-0039 — A service worker is the one thing Dart cannot be

- **Status:** Accepted
- **Date:** 2026-09-15
- **Related task:** OPH-313 (Epic 30, request round 22)

## Context

[AGENTS.md](../../AGENTS.md) rule 3 says it plainly: *"All client platforms are
one Flutter codebase (`apps/app`). No secondary web framework unless a task
explicitly justifies it with an ADR."* This is that justification, and it is
narrow.

A user asked for a reminder that appears on screen without ringing, while they
are working in another window. On the web that is only possible one way:

- **No browser can schedule a local notification.** Notification Triggers went
  through two Chrome origin trials and its
  [development stopped](https://developer.chrome.com/docs/web-platform/notification-triggers).
  Nothing replaced it.
- **A page cannot be the clock either.** Background tabs have their timers
  throttled, and a closed tab has none. AllisWell's only alerting surface on the
  web today is an in-app overlay driven by a foreground timer — it needs the tab
  open *and* focused, which is exactly the situation the report is not about.
- So the alert has to come from the server, as a Web Push message. And a browser
  will not hand out a push subscription at all without a **registered service
  worker** — `PushManager` lives on `ServiceWorkerRegistration` and nowhere else.

A service worker runs when the page does not. That is its whole purpose, and it
is why Dart cannot be one: there is no Flutter engine in that execution context,
so there is nothing to compile into.

## Decision

**One hand-written JavaScript file, `apps/app/web/aw_push_sw.js`, and a Dart
seam in front of everything else.**

The rule that keeps this from growing: **the service worker holds no logic.** It
registers, it receives a push, it reads the text out of this device's own store,
it shows a notification, and it forwards a click. Every decision — whether to
ask for permission, what to do when it is refused, whether this browser can be
reached at all, what the user sees when it cannot — is Dart, in
`notifications/web/gateway_web.dart`, behind an interface
(`notifications/web/push_host.dart`) that a VM test drives with a fake.

That split is not new. `web/alliswell-config.js` is already a small hand-written
script in this folder, `sound_store.dart` already splits an interface from its
web implementation, and the conditional-import idiom has six instances in
`lib/`. What is new is only that this particular file must run outside the
engine.

**Nothing about the app's UI, state or routing may move into it.** If a second
service-worker responsibility ever appears, it goes in this same file with its
own paragraph here — not into a framework, a bundler, or a second entry point.

## Alternatives considered

- **Use the service worker Flutter already generates.** It is for offline asset
  caching, is regenerated on every build, and is not ours to edit. Registering
  our own at the same scope would mean two workers fighting over one page.
- **Skip push and keep the in-app overlay.** That is today's behaviour and it is
  what the report is about: it needs the tab open and focused, and it rings.
- **Poll from the page.** Only works while the tab is open, which is the case
  that already works, and burns a request every minute for the case that does
  not.
- **Ask the user to install the app instead.** A real answer for some people and
  no answer at all for somebody whose work computer is a browser. The web is a
  first-class target in [BLUEPRINT.md](../BLUEPRINT.md) §1.

## Consequences

- One JavaScript file in the repository that no Dart test can cover. Its
  behaviour is kept small enough to read in one sitting, and everything it would
  otherwise decide is tested in Dart instead.
- Web push on iPhones works **only for AllisWell added to the Home Screen**, not
  in a Safari tab — Apple's rule, not ours
  ([WebKit](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/)).
  The app says so rather than appearing broken.
- `web/manifest.json` already declares `display: standalone`, which is what that
  path requires; nothing had to change for it.
- The worker ships with no `push` handler yet. The text a notification shows must
  come from this device's own copy of the data — the payload carries identifiers
  and never a task's title ([ADR-0038](0038-server-to-device-delivery.md)) — and
  that cache is OPH-314. Nothing sends a push until OPH-315, so the handler is in
  place before anything can arrive.
