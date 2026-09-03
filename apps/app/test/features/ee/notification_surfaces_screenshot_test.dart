// E08's notification surfaces, shot in both themes (EE-077).
//
//   flutter test --update-goldens --dart-define=screenshots=true \
//       test/features/ee/notification_surfaces_screenshot_test.dart
//
// Inert without the dart-define, and the images are NOT committed — the house
// rule set at EE-026: shots are generated, looked at, and thrown away.
//
// What these are FOR, since the widget tests already prove the behaviour: the
// questions a test cannot ask. Does the centre read as "what happened to you"
// rather than as a log? Does an unread row look unread without shouting? Does a
// locked preference switch look deliberately locked rather than broken? EE-071
// found a real defect this way — a history row that never said WHICH subtask —
// with every test green, so the looking is not ceremony.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/notification_prefs_api.dart';
import 'package:alliswell/src/features/ee/notification_prefs_providers.dart';
import 'package:alliswell/src/features/ee/notifications_providers.dart';
import 'package:alliswell/src/features/ee/ui/notification_center_screen.dart';
import 'package:alliswell/src/features/ee/ui/notification_prefs_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/glass.dart';

import '../../design_screenshots_test.dart' show loadRealFontsForStore;

const bool _enabled = bool.fromEnvironment('screenshots');
const String _screenshotFamily = 'ScreenshotSans';

NotificationItem _item(
  String id,
  String titleKey,
  Map<String, dynamic> params, {
  bool unread = true,
  int minutesAgo = 5,
  String? bodyKey,
}) => NotificationItem(
  id: id,
  eventClass: titleKey.split('.').skip(1).take(2).join('.'),
  titleKey: titleKey,
  bodyKey: bodyKey,
  params: params,
  entityType: 'task',
  entityId: 'T1',
  readAt: unread ? null : DateTime.now().toUtc(),
  createdAt: DateTime.now().toUtc().subtract(Duration(minutes: minutesAgo)),
);

/// A realistic inbox: two unread on top, older read ones under them, and the
/// classes a factory actually sees mixed together.
final _inbox = [
  _item('N1', 'ee.notif.task.assigned.title', {
    'taskTitle': 'Kompresör bakımı',
    'actorName': 'Ayla Yönetici',
  }, bodyKey: 'ee.notif.task.assigned.body'),
  _item(
    'N2',
    'ee.notif.sla.breached.title',
    {'ticketRef': 'INC-42', 'serviceName': 'ERP'},
    bodyKey: 'ee.notif.sla.breached.body',
    minutesAgo: 40,
  ),
  _item(
    'N3',
    'ee.notif.sla.warned.title',
    {'ticketRef': 'INC-51', 'dueAt': '14:00'},
    bodyKey: 'ee.notif.sla.warned.body',
    unread: false,
    minutesAgo: 200,
  ),
  _item(
    'N4',
    'ee.notif.share.received.title',
    {'itemTitle': 'Bakım planı', 'fromUnitName': 'Saha Servis'},
    bodyKey: 'ee.notif.share.received.body',
    unread: false,
    minutesAgo: 900,
  ),
  _item(
    'N5',
    'ee.notif.ticket.routed.title',
    {
      'unitName': 'Saha Servis',
      'ticketRef': 'INC-53',
      'subject': 'Hat 3 duruyor',
    },
    bodyKey: 'ee.notif.ticket.routed.body',
    unread: false,
    minutesAgo: 2600,
  ),
];

const _prefs = EeNotificationPrefs(
  timezone: 'Europe/Istanbul',
  quietFrom: 22 * 60,
  quietTo: 7 * 60,
  matrix: [
    EeNotificationPrefRow(
      eventClass: 'task.assigned',
      channels: ['email'],
      muted: [],
      silenceable: true,
    ),
    EeNotificationPrefRow(
      eventClass: 'sla.warned',
      channels: ['email'],
      muted: ['email'],
      silenceable: true,
    ),
    // The locked one — the whole reason this screen is worth looking at.
    EeNotificationPrefRow(
      eventClass: 'sla.breached',
      channels: ['email', 'push'],
      muted: [],
      silenceable: false,
    ),
  ],
);

void main() {
  if (!_enabled) return;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  Future<void> shoot(
    WidgetTester tester,
    Brightness brightness,
    String name,
    List<Override> overrides,
    Widget screen,
  ) async {
    await loadRealFontsForStore();
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    debugDisableShadows = false;
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAwTheme(
              brightness,
              fontFamilyOverride: _screenshotFamily,
            ),
            home: AwPageBackground(child: screen),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/$name-${brightness.name}.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets('the notification centre — ${brightness.name}', (tester) async {
      await shoot(tester, brightness, 'ee-notification-center', [
        notificationCenterProvider.overrideWith((ref) => Stream.value(_inbox)),
        unreadNotificationCountProvider.overrideWith((ref) => Stream.value(2)),
      ], const EeNotificationCenterScreen());
    });

    testWidgets('the centre with nothing in it — ${brightness.name}', (
      tester,
    ) async {
      await shoot(tester, brightness, 'ee-notification-center-empty', [
        notificationCenterProvider.overrideWith(
          (ref) => Stream.value(const <NotificationItem>[]),
        ),
        unreadNotificationCountProvider.overrideWith((ref) => Stream.value(0)),
      ], const EeNotificationCenterScreen());
    });

    testWidgets('notification preferences — ${brightness.name}', (
      tester,
    ) async {
      await shoot(tester, brightness, 'ee-notification-prefs', [
        eeNotificationPrefsProvider.overrideWith(
          () => _StubPrefsController(_prefs),
        ),
      ], const EeNotificationPrefsScreen());
    });
  }
}

class _StubPrefsController extends EeNotificationPrefsController {
  _StubPrefsController(this._value);
  final EeNotificationPrefs _value;

  @override
  Future<EeNotificationPrefs> build() async => _value;
}
