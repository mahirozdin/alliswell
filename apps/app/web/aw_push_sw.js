/**
 * AllisWell's push service worker (OPH-313/314, ADR-0039).
 *
 * WHY THIS FILE IS JAVASCRIPT AND NOT DART
 *
 * A browser will not hand out a push subscription without a registered service
 * worker, and a service worker runs when the page does not — it is the only
 * thing in AllisWell that executes with no Flutter engine around it. Dart
 * cannot be that; this is the one place the rule about a single Flutter
 * codebase has to bend, and ADR-0039 is where it is written down.
 *
 * AND WHY IT DECIDES NOTHING
 *
 * The push payload carries identifiers and never a task's title: what crosses
 * Google's, Apple's or Mozilla's servers must not be somebody's work
 * (ADR-0038). So the words come from this device's own store, where the app
 * wrote them already translated, already privacy-resolved, and already told
 * whether they should make a sound. This worker looks them up and shows them.
 * It does not translate, does not choose, and does not read the database.
 *
 * Every path ends in a notification. `userVisibleOnly: true` is a promise the
 * subscription made, and a push handler that finishes without showing anything
 * gets Chrome's own "this site has been updated in the background" card
 * instead — which says less than the fallback does.
 */

const AW_DB = 'alliswell_alerts';
const AW_STORE = 'alerts';
const AW_FALLBACK_KEY = '__fallback';

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

/** Opens the store the app writes into. Never creates it: if the app has not
 * run yet there is nothing to read, and the fallback covers that. */
function awOpenDb() {
  return new Promise((resolve) => {
    let request;
    try {
      request = indexedDB.open(AW_DB, 1);
    } catch (_) {
      resolve(null);
      return;
    }
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(AW_STORE)) {
        db.createObjectStore(AW_STORE);
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => resolve(null);
  });
}

function awRead(db, key) {
  return new Promise((resolve) => {
    if (!db) {
      resolve(null);
      return;
    }
    try {
      const store = db.transaction(AW_STORE, 'readonly').objectStore(AW_STORE);
      const request = store.get(key);
      request.onsuccess = () => resolve(request.result || null);
      request.onerror = () => resolve(null);
    } catch (_) {
      resolve(null);
    }
  });
}

/** The words for one reminder, or the fallback, or something rather than
 * nothing. Three levels because each can be missing for an honest reason: a
 * reminder scheduled before this browser last synced, a store the app has
 * never written to, a browser that refuses storage entirely. */
async function awTextFor(reminderId) {
  const db = await awOpenDb();
  const entry = reminderId ? await awRead(db, reminderId) : null;
  if (entry && entry.title) return entry;
  const fallback = await awRead(db, AW_FALLBACK_KEY);
  if (fallback && fallback.title) return fallback;
  return { title: 'AllisWell', body: '', silent: true };
}

self.addEventListener('push', (event) => {
  event.waitUntil(awOnPush(event));
});

async function awOnPush(event) {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    // Not ours, or not JSON. Still has to end in a notification.
  }

  const text = await awTextFor(data.reminderId);
  await self.registration.showNotification(text.title, {
    body: text.body || '',
    // One reminder replaces its own earlier notification rather than stacking.
    tag: data.reminderId || 'alliswell',
    // Written by the app, not decided here: the whole point of the setting is
    // that somebody working next to colleagues can be reached without a sound.
    silent: text.silent !== false,
    data: { taskId: data.taskId || null, reminderId: data.reminderId || null },
  });

  // Tell any open tab, so the app can sync and does not have to guess that
  // something arrived.
  const windows = await self.clients.matchAll({
    type: 'window',
    includeUncontrolled: true,
  });
  for (const client of windows) {
    client.postMessage({
      type: 'aw-push',
      reminderId: data.reminderId || null,
    });
  }
}

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(awOnClick(event.notification.data || {}));
});

async function awOnClick(data) {
  // The shape `handleNotificationEvent` already parses (taskId, reminderId).
  const payload = JSON.stringify({
    taskId: data.taskId,
    reminderId: data.reminderId,
  });
  const windows = await self.clients.matchAll({
    type: 'window',
    includeUncontrolled: true,
  });

  for (const client of windows) {
    if ('focus' in client) {
      await client.focus();
      client.postMessage({ type: 'aw-notification-click', payload });
      return;
    }
  }

  // Nothing open. Flutter web uses the hash strategy here, and the route is
  // the same one an in-app tap goes to (ADR-0016). Relative, so an instance
  // served from a sub-path still lands in the right place.
  const target = data.taskId ? `./#/tasks/${data.taskId}` : './';
  await self.clients.openWindow(target);
}
