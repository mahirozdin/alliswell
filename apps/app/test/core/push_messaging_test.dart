import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/firebase/push_messaging.dart';

/// OPH-319 — the mobile token, and the two states in which there is none.
///
/// The important assertion in this file is the one that looks like nothing:
/// with no Firebase config the wrapper never touches the plugin, which is why
/// these tests run at all. A fresh clone is exactly this state, and "the app
/// behaves as it did before" is not a promise here, it is the default.
class _FakeMessaging implements FirebaseMessaging {
  _FakeMessaging({this.throwOnToken = false});

  String? token = 'fcm-token-1';
  bool throwOnToken;
  int deletes = 0;
  final refreshes = StreamController<String>.broadcast();

  @override
  Future<String?> getToken({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) async {
    if (throwOnToken) throw StateError('no play services');
    return token;
  }

  @override
  Stream<String> get onTokenRefresh => refreshes.stream;

  @override
  Future<void> deleteToken() async => deletes += 1;

  /// Nothing else is reached; if something is, the test should say so loudly
  /// rather than quietly returning null.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unexpected ${invocation.memberName}');
}

void main() {
  test(
    'a build with no Firebase config never asks the plugin anything',
    () async {
      // No plugin is handed in at all: if the guard were missing this would
      // reach `FirebaseMessaging.instance` and throw in a VM test.
      final messaging = AwPushMessaging(
        isWeb: false,
        isConfigured: () => false,
      );

      expect(messaging.isAvailable, isFalse);
      expect(await messaging.token(), isNull);
      expect(await messaging.tokenRefreshes.isEmpty, isTrue);
      await messaging.forgetToken(); // must not throw
    },
  );

  test('the web is never asked for a token, configured or not', () async {
    // The browser is reached with VAPID; ADR-0025 §5 keeps "web has no
    // implicit config" true, and a second credential set for a channel the
    // browser already has would be the thing that broke it.
    final plugin = _FakeMessaging();
    final messaging = AwPushMessaging(
      plugin: plugin,
      isWeb: true,
      isConfigured: () => true,
    );

    expect(messaging.isAvailable, isFalse);
    expect(await messaging.token(), isNull);
    expect(plugin.deletes, 0);
  });

  test('a configured mobile build hands over the token it was given', () async {
    final plugin = _FakeMessaging();
    final messaging = AwPushMessaging(
      plugin: plugin,
      isWeb: false,
      isConfigured: () => true,
    );

    expect(messaging.isAvailable, isTrue);
    expect(await messaging.token(), 'fcm-token-1');
  });

  test(
    'a rotated token arrives on the stream, which is the whole point',
    () async {
      final plugin = _FakeMessaging();
      final messaging = AwPushMessaging(
        plugin: plugin,
        isWeb: false,
        isConfigured: () => true,
      );

      final seen = <String>[];
      final sub = messaging.tokenRefreshes.listen(seen.add);
      plugin.refreshes.add('fcm-token-2');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      // A rotation nobody wrote down is a device the server keeps sending to and
      // never reaches again.
      expect(seen, ['fcm-token-2']);
    },
  );

  test('a device that cannot produce a token is not an error', () async {
    // No Play services, a desktop build, a locked-down ROM: this is a device
    // we reach some other way, not a failure to report.
    final messaging = AwPushMessaging(
      plugin: _FakeMessaging(throwOnToken: true),
      isWeb: false,
      isConfigured: () => true,
    );

    expect(await messaging.token(), isNull);
  });

  test('signing out deletes the token, not just the row', () async {
    final plugin = _FakeMessaging();
    final messaging = AwPushMessaging(
      plugin: plugin,
      isWeb: false,
      isConfigured: () => true,
    );

    await messaging.forgetToken();

    // The row may outlive the request; a deleted token cannot be sent to
    // whatever the server still believes.
    expect(plugin.deletes, 1);
  });
}
