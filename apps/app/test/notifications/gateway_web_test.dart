import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/web/gateway_web.dart';
import 'package:alliswell/src/notifications/web/push_host.dart';

/// OPH-313 — until now `notificationsGatewayProvider` handed web the same
/// `LocalNotificationsGateway` as a phone, and every call died in a
/// `MissingPluginException` the scheduler swallowed into a `degraded` row. The
/// browser cannot schedule anything locally, and saying so is the feature.
class _FakeHost implements WebPushHost {
  _FakeHost({
    this.isSupported = true,
    this.granted = WebPushPermission.prompt,
    this.subscribeFails = false,
  });

  @override
  bool isSupported;
  WebPushPermission granted;
  bool subscribeFails;

  WebPushSubscription? _subscription;
  final List<String> shown = [];
  String? subscribedWithKey;
  int unsubscribes = 0;

  @override
  Future<WebPushPermission> permission() async => granted;

  @override
  Future<WebPushPermission> requestPermission() async {
    if (granted == WebPushPermission.prompt) {
      granted = WebPushPermission.granted;
    }
    return granted;
  }

  @override
  Future<WebPushSubscription?> currentSubscription() async => _subscription;

  @override
  Future<WebPushSubscription?> subscribe(String applicationServerKey) async {
    subscribedWithKey = applicationServerKey;
    if (subscribeFails) return null;
    _subscription = const WebPushSubscription(
      endpoint: 'https://push.example/one',
      p256dh: 'p256dh-value',
      auth: 'auth-value',
    );
    return _subscription;
  }

  @override
  Future<void> unsubscribe() async {
    unsubscribes += 1;
    _subscription = null;
  }

  @override
  Future<void> showNotification(
    String title, {
    String? body,
    bool silent = true,
  }) async {
    shown.add(title);
  }
}

WebNotificationsGateway _gatewayFor(
  _FakeHost host, {
  String? vapidKey = 'server-vapid-key',
  void Function()? onChanged,
}) => WebNotificationsGateway(
  host: host,
  readVapidKey: () async => vapidKey,
  onSubscriptionChanged: onChanged,
);

final _planned = PlannedNotification(
  id: 11,
  title: 'Pay the invoice',
  body: 'in 10 minutes',
  fireAt: DateTime.utc(2026, 9, 20, 7, 30),
  urgent: false,
  payload: '{}',
);

void main() {
  group('asking the browser', () {
    test('a granted prompt subscribes and says who to tell', () async {
      final host = _FakeHost();
      var told = 0;
      final gateway = _gatewayFor(host, onChanged: () => told += 1);

      expect(await gateway.requestPermissions(), isTrue);
      expect(host.subscribedWithKey, 'server-vapid-key');
      expect(told, 1);
      expect(await gateway.subscription(), isNotNull);
    });

    test('a refusal is a false, not an exception', () async {
      final host = _FakeHost(granted: WebPushPermission.denied);
      expect(await _gatewayFor(host).requestPermissions(), isFalse);
      expect(host.subscribedWithKey, isNull);
    });

    test('a browser that cannot do this is not asked', () async {
      final host = _FakeHost(isSupported: false);
      expect(await _gatewayFor(host).requestPermissions(), isFalse);
      expect(host.subscribedWithKey, isNull);
    });

    test('a server with no push configured is not asked either', () async {
      // `/push/public-key` 404s on an instance with no VAPID keys (OPH-310).
      // Subscribing without one is not possible, and pretending otherwise
      // would leave a browser that thinks it is covered.
      final host = _FakeHost();
      final gateway = _gatewayFor(host, vapidKey: null);
      expect(await gateway.requestPermissions(), isFalse);
      expect(host.subscribedWithKey, isNull);
    });
  });

  group('what it admits about itself', () {
    test('no permission reads as notifications off', () async {
      final host = _FakeHost(granted: WebPushPermission.denied);
      final support = await _gatewayFor(host).alarmSupport();
      expect(support.notificationsEnabled, isFalse);
      expect(support.worstProblem, AlarmProblem.notificationsOff);
    });

    test('permission without a subscription is its OWN problem', () async {
      // The dishonest outcome this guards against: permission is granted, the
      // banner is therefore quiet, and nothing can reach the browser anyway
      // because the server has no keys. NOTIFICATIONS §3 forbids exactly that.
      final host = _FakeHost(granted: WebPushPermission.granted);
      final support = await _gatewayFor(host, vapidKey: null).alarmSupport();

      expect(support.notificationsEnabled, isTrue);
      expect(support.worstProblem, AlarmProblem.webPushOff);
    });

    test('a subscription the browser refused reads the same way', () async {
      final host = _FakeHost(
        granted: WebPushPermission.granted,
        subscribeFails: true,
      );
      final gateway = _gatewayFor(host);
      await gateway.requestPermissions();

      final support = await gateway.alarmSupport();
      expect(support.worstProblem, AlarmProblem.webPushOff);
    });

    test('subscribed and permitted has nothing to warn about', () async {
      final gateway = _gatewayFor(_FakeHost());
      await gateway.requestPermissions();

      final support = await gateway.alarmSupport();
      expect(support.worstProblem, isNull);
      expect(support.criticalAlertsEnabled, isFalse);
      // Web cannot answer any of the Darwin questions, and guessing would put
      // a wrong sentence in the Settings row.
      expect(support.soundEnabled, isNull);
      expect(support.timeSensitiveEnabled, isNull);
    });
  });

  group('the scheduler can drive it without falling over', () {
    test('accepts a plan and remembers the id, without an OS call', () async {
      // A `degraded` alarm-log row is written when a gateway call THROWS
      // (scheduler.dart:248-274). The web gateway schedules nothing locally —
      // the server is the clock here (ADR-0038) — so the thing that matters is
      // that the set arithmetic still converges and nothing throws.
      final gateway = _gatewayFor(_FakeHost());

      expect(await gateway.pendingIds(), isEmpty);
      await gateway.schedule(_planned);
      expect(await gateway.pendingIds(), {11});

      await gateway.cancel(11);
      expect(await gateway.pendingIds(), isEmpty);
    });

    test('every method answers instead of throwing', () async {
      // The unsupported browser is the harshest case: no Notification, no
      // service worker, nothing. It must still be drivable.
      final gateway = _gatewayFor(_FakeHost(isSupported: false));

      await expectLater(gateway.initialize(), completes);
      await expectLater(gateway.schedule(_planned), completes);
      await expectLater(gateway.cancel(11), completes);
      await expectLater(gateway.pendingIds(), completes);
      await expectLater(gateway.alarmSupport(), completes);
    });
  });

  test('a rehearsal actually shows something (OPH-277 on the web)', () async {
    final host = _FakeHost();
    final gateway = _gatewayFor(host);
    await gateway.requestPermissions();

    await gateway.scheduleTestAlarm(
      title: 'Rehearsal',
      body: 'this is what it looks like',
      after: Duration.zero,
    );
    await Future<void>.delayed(Duration.zero);

    expect(host.shown, ['Rehearsal']);
  });
}
