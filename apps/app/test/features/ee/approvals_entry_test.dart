import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/ee/approvals_providers.dart';
import 'package:alliswell/src/features/ee/data/approvals_api.dart';
import 'package:alliswell/src/features/ee/data/approvals_models.dart';
import 'package:alliswell/src/features/ee/ui/approvals_screen.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_bubble.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_panel.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/router.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// EE-294 — Approvals in the navigation, for whoever has approval authority.
///
/// The owner (2026-09-30): the screen sat in Settings, drawn for the team's
/// admins only, and a person who is asked to decide could miss it. Now:
///
///   1. ON A WIDE SCREEN it is in the rail, directly under Requests, with a
///      red count; in the narrow rail too.
///   2. ON A PHONE it is pinned at the top of Quick Access — fixed, no menu —
///      and the floating button carries the count, even for somebody with no
///      shortcuts of their own (the pin is what they have to open); with the
///      button switched off, the ⚡ in Home's bar carries it.
///   3. NOBODY ELSE SEES A DOOR: no authority, a plain server, a personal
///      account.
///   4. THE OLD ADDRESS STILL WORKS (DESIGN §32 S3).
class _Fixed extends EeApprovalsController {
  _Fixed(this._items);
  final List<EeApproval> _items;
  @override
  Future<List<EeApproval>> build() async => _items;
}

/// OPH-357 (UI-AUDIT #26): a summary endpoint that answers, then is refused
/// the way a busy server refuses (a 429), while the device is online.
class _FlakySummary extends EeApprovalsApi {
  _FlakySummary() : super(Dio());
  bool refuse = false;
  int asked = 0;

  @override
  Future<EeApprovalsSummary> summary() async {
    asked += 1;
    if (refuse) {
      throw const ApiException(
        'RATE_LIMITED',
        'Rate limit exceeded, retry in 30 seconds',
        statusCode: 429,
        retryAfter: 30,
      );
    }
    return _waiting;
  }
}

FakeApi _team() => FakeApi()
  ..eeState = 'active'
  ..eeFeatures = ['teams', 'itsm']
  ..eeBaseDomain = 'example.com';

const _waiting = EeApprovalsSummary(
  authority: true,
  answersForRole: true,
  personal: 2,
  role: 1,
);

Future<Widget> _app(
  FakeApi api, {
  EeApprovalsSummary? summary = _waiting,
  bool bubbleEnabled = true,
  String serverUrl = 'https://acme.example.com',
  List<Override> more = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  await resetQuickAccessPrefs();
  // The status cache is a process-wide singleton (see desk_tab_test).
  await localKv.remove('alliswell_ee_status::user-1');
  if (!bubbleEnabled) {
    await localKv.set('alliswell_quick_bubble_enabled', 'false');
  }
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  final extra = <Override>[
    apiBaseUrlProvider.overrideWithValue(serverUrl),
    eeApprovalsProvider.overrideWith(() => _Fixed(const [])),
    if (summary != null)
      eeApprovalsSummaryProvider.overrideWith((ref) async => summary),
    ...more,
  ];
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
      ...extra,
    ],
    child: const AllisWellApp(),
  );
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder get _entry => find.byKey(const Key('nav-approvals'));

String _badgeText(WidgetTester tester, String key) => tester
    .widget<Text>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
    )
    .data!;

void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  testWidgets('wide: in the rail directly under Requests, with the sum of '
      'both tabs', (tester) async {
    _size(tester, const Size(1280, 1000));
    await tester.pumpWidget(await _app(_team()));
    await tester.pumpAndSettle();

    expect(_entry, findsOneWidget);
    expect(_badgeText(tester, 'nav-approvals-badge'), '3');
    // Under Requests: the rail's last destination, then this.
    final requests = find.text('nav.tickets'.tr());
    expect(requests, findsWidgets);
    expect(
      tester.getTopLeft(_entry).dy,
      greaterThan(tester.getBottomLeft(requests.first).dy),
    );

    await tester.tap(_entry);
    await tester.pumpAndSettle();
    expect(find.byType(EeApprovalsScreen), findsOneWidget);
  });

  testWidgets('narrow rail: the same entry, the count on its icon', (
    tester,
  ) async {
    _size(tester, const Size(1000, 900));
    await tester.pumpWidget(await _app(_team()));
    await tester.pumpAndSettle();
    expect(_entry, findsOneWidget);
    expect(_badgeText(tester, 'nav-approvals-badge'), '3');
  });

  testWidgets('phone: pinned in Quick Access, and the button carries the '
      'count although there is not one shortcut', (tester) async {
    _size(tester, const Size(390, 844));
    await tester.pumpWidget(await _app(_team()));
    await tester.pumpAndSettle();

    // No bottom-bar entry: the bar has no room, which is why this exists.
    expect(_entry, findsNothing);
    final bubble = find.byType(QuickAccessBubble);
    expect(bubble, findsOneWidget);
    expect(_badgeText(tester, 'quick-bubble-badge'), '3');

    await tester.tap(bubble);
    await tester.pumpAndSettle();
    expect(find.byType(QuickAccessPanel), findsOneWidget);
    final pin = find.byKey(const Key('quick-pin-approvals'));
    expect(pin, findsOneWidget);
    expect(_badgeText(tester, 'quick-pin-approvals-badge'), '3');
    // Fixed: no menu to rename, move or remove it.
    expect(
      find.descendant(of: pin, matching: find.byIcon(Icons.more_vert)),
      findsNothing,
    );

    await tester.tap(pin);
    await tester.pumpAndSettle();
    expect(find.byType(EeApprovalsScreen), findsOneWidget);
  });

  testWidgets('phone with the button off: the ⚡ in Home carries the count', (
    tester,
  ) async {
    _size(tester, const Size(390, 844));
    await tester.pumpWidget(await _app(_team(), bubbleEnabled: false));
    await tester.pumpAndSettle();
    expect(find.byType(QuickAccessBubble), findsNothing);
    expect(_badgeText(tester, 'quick-appbar-badge'), '3');
  });

  testWidgets('nothing waiting: the door is there, the badge is not', (
    tester,
  ) async {
    _size(tester, const Size(1280, 1000));
    await tester.pumpWidget(
      await _app(
        _team(),
        summary: const EeApprovalsSummary(
          authority: true,
          answersForRole: false,
          personal: 0,
          role: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_entry, findsOneWidget);
    expect(find.byKey(const Key('nav-approvals-badge')), findsNothing);
  });

  testWidgets('no approval authority: no door anywhere', (tester) async {
    _size(tester, const Size(1280, 1000));
    await tester.pumpWidget(
      await _app(_team(), summary: EeApprovalsSummary.none),
    );
    await tester.pumpAndSettle();
    expect(_entry, findsNothing);
  });

  testWidgets('no approval authority on a phone: no pin, and no button for '
      'somebody with no shortcuts', (tester) async {
    _size(tester, const Size(390, 844));
    await tester.pumpWidget(
      await _app(_team(), summary: EeApprovalsSummary.none),
    );
    await tester.pumpAndSettle();
    expect(find.byType(QuickAccessBubble), findsNothing);
  });

  testWidgets('a plain server draws no door, and asks nobody', (tester) async {
    _size(tester, const Size(1280, 1000));
    // Nothing overridden: the real summary provider on a CE server.
    await tester.pumpWidget(await _app(FakeApi(), summary: null));
    await tester.pumpAndSettle();
    expect(_entry, findsNothing);
  });

  testWidgets('a personal window on a licensed server draws no door', (
    tester,
  ) async {
    _size(tester, const Size(1280, 1000));
    // The service's own address: somebody on their own, no team to ask.
    await tester.pumpWidget(
      await _app(_team(), summary: null, serverUrl: 'https://api.example.com'),
    );
    await tester.pumpAndSettle();
    expect(_entry, findsNothing);
  });

  testWidgets('the old Settings address still lands on the screen', (
    tester,
  ) async {
    _size(tester, const Size(1280, 1000));
    await tester.pumpWidget(await _app(_team()));
    await tester.pumpAndSettle();
    final router = GoRouter.of(awRootNavigatorKey.currentContext!);
    router.go('/settings/team/approvals');
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/approvals');
    expect(find.byType(EeApprovalsScreen), findsOneWidget);
  });

  testWidgets('UI-AUDIT #26: a refused summary keeps the entry and its count '
      '— the last answer, not "nothing to decide"', (tester) async {
    _size(tester, const Size(1280, 1000));
    final api = _FlakySummary();
    await tester.pumpWidget(
      await _app(
        _team(),
        summary: null,
        more: [eeApprovalsApiProvider.overrideWithValue(api)],
      ),
    );
    await tester.pumpAndSettle();
    expect(_entry, findsOneWidget);
    expect(_badgeText(tester, 'nav-approvals-badge'), '3');

    // The next heartbeat is refused.
    api.refuse = true;
    final asked = api.asked;
    ProviderScope.containerOf(
      tester.element(find.byType(AllisWellApp)),
    ).invalidate(eeApprovalsSummaryProvider);
    await tester.pumpAndSettle();
    expect(api.asked, asked + 1);

    expect(_entry, findsOneWidget);
    expect(_badgeText(tester, 'nav-approvals-badge'), '3');
  });
}
