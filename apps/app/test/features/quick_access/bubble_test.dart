import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/quick_access/ui/bubble_physics.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_bubble.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_panel.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-200 — the phone's floating quick-access button (DESIGN §23 Q4/Q5).
Future<Widget> signedInApp(FakeApi api, {bool bubbleEnabled = true}) async {
  SharedPreferences.setMockInitialValues({});
  // localKv is a process-wide singleton; mock values alone do not reset it.
  await resetQuickAccessPrefs();
  // The real preference path, not an override: the toggle hydrates from
  // localKv, which is exactly what a returning user's launch does.
  if (!bubbleEnabled) {
    await localKv.set('alliswell_quick_bubble_enabled', 'false');
  }
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Finder get bubble => find.byType(QuickAccessBubble);

void main() {
  testWidgets('appears on a phone once there is something to shortcut to', (
    tester,
  ) async {
    final api = FakeApi();
    api.seedQuickLink(
      kind: 'url',
      url: 'https://alliswell.space',
      title: 'Site',
    );

    phone(tester);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    expect(bubble, findsOneWidget);
    // 56 px, the whole time — the idle recede is paint only (Q4a).
    expect(tester.getSize(bubble).width, kBubbleDiameter);
    expect(tester.getSize(bubble).height, kBubbleDiameter);
  });

  testWidgets('an empty rail shows no button — a dead control is worse', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(await signedInApp(FakeApi()));
    await tester.pumpAndSettle();
    expect(bubble, findsNothing);
  });

  testWidgets('tapping it opens the panel, and the button steps aside', (
    tester,
  ) async {
    final api = FakeApi();
    api.seedQuickLink(
      kind: 'url',
      url: 'https://alliswell.space',
      title: 'Site',
    );

    phone(tester);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    await tester.tap(bubble);
    await tester.pumpAndSettle();
    expect(find.byType(QuickAccessPanel), findsOneWidget);
    expect(find.text('Site'), findsOneWidget);
    // A floating control over a modal is two competing surfaces (Q4).
    expect(bubble, findsNothing);

    Navigator.of(tester.element(find.byType(QuickAccessPanel))).pop();
    await tester.pumpAndSettle();
    expect(bubble, findsOneWidget);
  });

  testWidgets('a dialog hides it too — not only this feature\'s own sheet', (
    tester,
  ) async {
    final api = FakeApi();
    api.seedQuickLink(
      kind: 'url',
      url: 'https://alliswell.space',
      title: 'Site',
    );

    phone(tester);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();
    expect(bubble, findsOneWidget);

    // `showDialog` goes to the ROOT navigator while a section's bottom sheet
    // goes to its BRANCH — this is the case that proves one root observer sees
    // both (go_router merges root observers into branch navigators).
    final context = tester.element(find.byType(Scaffold).first);
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => const AlertDialog(content: Text('modal')),
      ),
    );
    await tester.pumpAndSettle();
    expect(bubble, findsNothing);

    Navigator.of(context, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    expect(bubble, findsOneWidget);
  });

  testWidgets('dragging parks it on the other edge, and that sticks', (
    tester,
  ) async {
    final api = FakeApi();
    api.seedQuickLink(
      kind: 'url',
      url: 'https://alliswell.space',
      title: 'Site',
    );

    phone(tester);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    final before = tester.getTopLeft(bubble);
    expect(before.dx, greaterThan(195), reason: 'factory position is right');

    // A real drag, frame by frame: the pan recognizer needs intermediate
    // moves, and a single synthesized fling would not exercise the snap.
    final gesture = await tester.startGesture(tester.getCenter(bubble));
    await gesture.moveBy(const Offset(-120, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(-200, 80));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final after = tester.getTopLeft(bubble);
    expect(after.dx, lessThan(before.dx));
    expect(after.dx, kBubbleEdgeMargin, reason: 'snapped to the left edge');
    final stored = await tester.runAsync(
      () => localKv.get('alliswell_quick_bubble_pos'),
    );
    expect(parseBubblePosition(stored).edge, BubbleEdge.left);
  });

  testWidgets('switched off, the Home app bar carries the entry instead', (
    tester,
  ) async {
    final api = FakeApi();
    api.seedQuickLink(
      kind: 'url',
      url: 'https://alliswell.space',
      title: 'Site',
    );

    phone(tester);
    await tester.pumpWidget(await signedInApp(api, bubbleEnabled: false));
    await tester.pumpAndSettle();

    expect(bubble, findsNothing);
    // The feature is never gesture-only (DESIGN §23 Q5 / §19 D2).
    expect(find.byKey(const Key('quick-appbar-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('quick-appbar-button')));
    await tester.pumpAndSettle();
    expect(find.byType(QuickAccessPanel), findsOneWidget);
  });

  testWidgets('never rides along on the sign-in screens', (tester) async {
    final api = FakeApi();
    api.seedQuickLink(
      kind: 'url',
      url: 'https://alliswell.space',
      title: 'Site',
    );

    phone(tester);
    SharedPreferences.setMockInitialValues({});
    await resetQuickAccessPrefs();
    await tester.pumpWidget(
      ProviderScope(
        retry: awRetry,
        overrides: [
          ...syncTestOverrides(),
          secretStoreProvider.overrideWithValue(InMemorySecretStore()),
          apiClientProvider.overrideWithValue(
            fakeDio(FakeHttpClientAdapter(api.handle)),
          ),
        ],
        child: const AllisWellApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(bubble, findsNothing);
  });
}
