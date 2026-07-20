import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/onboarding/tour.dart';
import 'package:alliswell/src/sections.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

Future<Widget> tourApp(
  FakeApi api, {
  required bool tourEnabled,
  bool seen = false,
}) async {
  // localKv caches its SharedPreferences instance globally, so the flag must be
  // forced through localKv (not setMockInitialValues) to survive cross-test
  // pollution. setUp already cleared it; only the "seen" case needs a write.
  if (seen) await localKv.set(kOnboardingSeenKey, 'true');
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(tourAutoStart: tourEnabled),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
    ],
    child: const AllisWellApp(),
  );
}

void main() {
  // localKv is a global singleton that caches SharedPreferences — reset the
  // seen flag through it (not just the mock) before every test.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await localKv.remove(kOnboardingSeenKey);
  });

  group('TourController (OPH-111)', () {
    test('the script is welcome + one step per section + farewell (≤7)', () {
      expect(kTourSteps.length, 7); // welcome + 5 sections + done (OPH-162/170)
      expect(kTourSteps.first.section, isNull);
      expect(kTourSteps.last.section, isNull);
      for (final s in kTourSteps) {
        expect(s.title, isNotEmpty);
        expect(s.body, isNotEmpty);
      }
      final sections = kTourSteps
          .map((s) => s.section)
          .whereType<AppSection>()
          .toSet();
      expect(sections, AppSection.values.toSet());
    });

    test(
      'next advances; finishing on the last step persists the seen flag',
      () async {
        SharedPreferences.setMockInitialValues({});
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final ctl = c.read(tourControllerProvider.notifier);
        ctl.start();
        expect(c.read(tourControllerProvider).running, isTrue);
        for (var i = 0; i < kTourSteps.length - 1; i++) {
          ctl.next();
        }
        expect(c.read(tourControllerProvider).isLast, isTrue);
        ctl.next(); // Done
        expect(c.read(tourControllerProvider).running, isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(await localKv.get(kOnboardingSeenKey), 'true');
      },
    );

    test('skip ends the tour and persists the flag', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final ctl = c.read(tourControllerProvider.notifier);
      ctl.start();
      ctl.skip();
      expect(c.read(tourControllerProvider).running, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(await localKv.get(kOnboardingSeenKey), 'true');
    });

    test('maybeAutoStart is a no-op when auto-start is disabled', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer(
        overrides: [tourAutoStartProvider.overrideWithValue(false)],
      );
      addTearDown(c.dispose);
      await c.read(tourControllerProvider.notifier).maybeAutoStart();
      expect(c.read(tourControllerProvider).running, isFalse);
    });

    test('maybeAutoStart is a no-op when already seen', () async {
      await localKv.set(kOnboardingSeenKey, 'true');
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(tourControllerProvider.notifier).maybeAutoStart();
      expect(c.read(tourControllerProvider).running, isFalse);
    });
  });

  testWidgets('auto-starts for a new device; Skip dismisses and persists', (
    tester,
  ) async {
    await tester.pumpWidget(await tourApp(FakeApi(), tourEnabled: true));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to AllisWell'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tour-skip')));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to AllisWell'), findsNothing);
    expect(await localKv.get(kOnboardingSeenKey), 'true');
  });

  testWidgets('Next walks the whole tour to Done and persists', (tester) async {
    await tester.pumpWidget(await tourApp(FakeApi(), tourEnabled: true));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to AllisWell'), findsOneWidget);

    for (var i = 0; i < kTourSteps.length - 1; i++) {
      await tester.tap(find.byKey(const Key('tour-next')));
      await tester.pumpAndSettle();
    }
    expect(find.text('You’re all set'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tour-next'))); // Done
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tour-next')), findsNothing);
    expect(await localKv.get(kOnboardingSeenKey), 'true');
  });

  testWidgets('runs on a phone with bottom-bar anchors too', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(await tourApp(FakeApi(), tourEnabled: true));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to AllisWell'), findsOneWidget);

    // Advance to the Home step — it spotlights a bottom-bar destination slice.
    await tester.tap(find.byKey(const Key('tour-next')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Your day in one chronological list'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('tour-skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tour-skip')), findsNothing);
    expect(await localKv.get(kOnboardingSeenKey), 'true');
  });

  testWidgets('does NOT auto-start when the device has already seen it', (
    tester,
  ) async {
    await tester.pumpWidget(
      await tourApp(FakeApi(), tourEnabled: true, seen: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome to AllisWell'), findsNothing);
    expect(find.byKey(const Key('tour-skip')), findsNothing);
  });
}
