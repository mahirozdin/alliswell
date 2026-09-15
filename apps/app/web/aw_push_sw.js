/**
 * AllisWell's push service worker (OPH-313, ADR-0039).
 *
 * WHY THIS FILE IS JAVASCRIPT AND NOT DART
 *
 * A browser will not hand out a push subscription without a registered service
 * worker, and a service worker runs when the page does not — it is the only
 * thing in AllisWell that executes with no Flutter engine around it. Dart
 * cannot be that; this is the one place the rule about a single Flutter
 * codebase has to bend, and ADR-0039 is where it is written down.
 *
 * WHAT IT DOES TODAY
 *
 * Registers, and takes control. That is the whole of what a subscription
 * needs. There is deliberately NO `push` handler yet: the text a notification
 * shows has to come from this device's own copy of the data — the payload
 * carries identifiers and never a task's title (ADR-0038) — and that cache is
 * OPH-314's half. Nothing sends a push until OPH-315, so the order is safe:
 * by the time anything arrives, the handler that renders it honestly is here.
 *
 * Adding one before then would mean choosing between an English string shown to
 * somebody using AllisWell in Turkish, and a notification with nothing in it.
 */

self.addEventListener('install', () => {
  // No cache to warm: this worker exists for push, not for offline. Skipping
  // the wait means a reload picks up a new version immediately instead of
  // leaving the old one in charge until every tab is closed.
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  // Take over the pages that are already open, so the tab that just subscribed
  // is the one this worker is talking to.
  event.waitUntil(self.clients.claim());
});
