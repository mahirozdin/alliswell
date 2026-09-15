import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'push_host.dart';

/// The browser half of the web notification gateway (OPH-313, ADR-0039).
///
/// `package:web` only — the same interop this repo already uses for
/// localStorage and `<html lang>`. No `dart:html`, no `package:js`.
///
/// Every call is wrapped: a browser that has the objects but refuses the
/// operation (private mode, a policy, an iOS Safari tab rather than an
/// installed web app) must come back as "no", never as an exception the
/// scheduler turns into a `degraded` row.
const String kAwPushServiceWorkerUrl = 'aw_push_sw.js';

class _BrowserPushHost implements WebPushHost {
  _BrowserPushHost() {
    try {
      web.window.navigator.serviceWorker.onmessage = (web.MessageEvent event) {
        final message = event.data.dartify();
        if (message is! Map) return;
        if (message['type'] != 'aw-notification-click') return;
        final payload = message['payload'];
        if (payload is String) _clicks.add(payload);
      }.toJS;
    } on Object {
      // No service worker here; the stream simply never emits.
    }
  }

  final StreamController<String> _clicks = StreamController<String>.broadcast();

  @override
  Stream<String> get notificationClicks => _clicks.stream;

  web.ServiceWorkerRegistration? _registration;

  @override
  bool get isSupported {
    try {
      // On iOS, Safari has none of this in a plain tab — only a web app added
      // to the Home Screen does (WebKit, iOS/iPadOS 16.4+). Feature detection
      // says so without having to know which browser this is.
      return globalContext.has('Notification') &&
          globalContext.has('PushManager') &&
          (web.window.navigator as JSObject).has('serviceWorker');
    } on Object {
      return false;
    }
  }

  @override
  bool get ignoresSilence {
    try {
      // The one place in this file that asks WHICH browser rather than what it
      // can do, and deliberately: `silent` is not feature-detectable. A
      // Notification constructed with `silent: true` reports `silent === true`
      // in Firefox too — it simply plays the sound anyway (bugzilla 1671255).
      // Sniffing a user agent is the lesser evil against a setting that
      // promises a silence the browser will not keep.
      return web.window.navigator.userAgent.contains('Firefox');
    } on Object {
      return false;
    }
  }

  WebPushPermission _read(String value) => switch (value) {
    'granted' => WebPushPermission.granted,
    'denied' => WebPushPermission.denied,
    _ => WebPushPermission.prompt,
  };

  @override
  Future<WebPushPermission> permission() async {
    if (!isSupported) return WebPushPermission.denied;
    try {
      return _read(web.Notification.permission);
    } on Object {
      return WebPushPermission.denied;
    }
  }

  @override
  Future<WebPushPermission> requestPermission() async {
    if (!isSupported) return WebPushPermission.denied;
    try {
      final result = await web.Notification.requestPermission().toDart;
      return _read(result.toDart);
    } on Object {
      return WebPushPermission.denied;
    }
  }

  /// One registration per session. Registering twice is harmless but the
  /// promise is what we actually need, and holding it keeps every later call
  /// from racing a second `register()`.
  Future<web.ServiceWorkerRegistration?> _ready() async {
    if (_registration != null) return _registration;
    if (!isSupported) return null;
    try {
      _registration = await web.window.navigator.serviceWorker
          .register(kAwPushServiceWorkerUrl.toJS)
          .toDart;
      return _registration;
    } on Object {
      return null;
    }
  }

  WebPushSubscription? _describe(web.PushSubscription? subscription) {
    if (subscription == null) return null;
    final p256dh = subscription.getKey('p256dh');
    final auth = subscription.getKey('auth');
    if (p256dh == null || auth == null) return null;
    return WebPushSubscription(
      endpoint: subscription.endpoint,
      p256dh: _base64Url(p256dh.toDart.asUint8List()),
      auth: _base64Url(auth.toDart.asUint8List()),
    );
  }

  @override
  Future<WebPushSubscription?> currentSubscription() async {
    final registration = await _ready();
    if (registration == null) return null;
    try {
      return _describe(await registration.pushManager.getSubscription().toDart);
    } on Object {
      return null;
    }
  }

  @override
  Future<WebPushSubscription?> subscribe(String applicationServerKey) async {
    final registration = await _ready();
    if (registration == null) return null;
    try {
      final subscription = await registration.pushManager
          .subscribe(
            web.PushSubscriptionOptionsInit(
              // Required by Chrome, and a promise we keep: every push this
              // server sends results in a notification (ADR-0038).
              userVisibleOnly: true,
              applicationServerKey: _decodeBase64Url(applicationServerKey).toJS,
            ),
          )
          .toDart;
      return _describe(subscription);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> unsubscribe() async {
    try {
      final registration = await _ready();
      final manager = registration?.pushManager;
      final subscription = await manager?.getSubscription().toDart;
      await subscription?.unsubscribe().toDart;
    } on Object {
      // Already gone, or a browser that will not say. Either way there is
      // nothing left to do here.
    }
  }

  @override
  Future<void> showNotification(
    String title, {
    String? body,
    bool silent = true,
  }) async {
    final registration = await _ready();
    if (registration == null) return;
    try {
      await registration
          .showNotification(
            title,
            web.NotificationOptions(body: body ?? '', silent: silent),
          )
          .toDart;
    } on Object {
      // Nothing to recover: the caller already treats this as best effort.
    }
  }
}

String _base64Url(Uint8List bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _decodeBase64Url(String value) =>
    base64Url.decode(value.padRight((value.length + 3) & ~3, '='));

WebPushHost createWebPushHost() => _BrowserPushHost();
