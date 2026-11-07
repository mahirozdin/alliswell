import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/quick_parse.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/team_origin.dart';
import 'package:alliswell/src/features/ai/ui/ai_fab.dart';
import 'package:alliswell/src/features/onboarding/tour_overlay.dart';
import 'package:alliswell/src/features/onboarding/tour.dart';
import 'package:alliswell/src/i18n/i18n.dart';
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
    // OPH-404 (U-33): four things a person does on day one — not a walk
    // past every tab that never said how to add a task.
    test('the personal script is four steps: quick add, voice, urgent '
        'alarm, search', () {
      expect(kTourSteps, [kTourQuickAdd, kTourVoice, kTourAlarm, kTourSearch]);
      expect(kTourSteps.map((s) => s.target), [
        TourTarget.quickAdd,
        TourTarget.voice,
        null, // nothing on Home to point at: a centred card
        TourTarget.search,
      ]);
      for (final s in kTourSteps) {
        expect(s.title, isNotEmpty);
        expect(s.body, isNotEmpty);
        expect(s.section, isNull, reason: 'no step tours a tab any more');
      }
    });

    test('the quick-add step teaches the syntax with an example the parser '
        'really reads', () {
      for (final locale in const [Locale('en'), Locale('tr')]) {
        AwI18n.instance.setActiveCached(locale);
        final body = kTourQuickAdd.body;
        final example = RegExp('“([^”]+)”').firstMatch(body)!.group(1)!;
        final parse = awParseQuickAdd(
          example,
          AwQuickParseOptions(now: DateTime(2026, 11, 7, 9)),
        );
        expect(parse.dueHasTime, isTrue, reason: '$locale: "$example"');
        expect(parse.dueAt!.hour, 15, reason: '$locale: "$example"');
        expect(parse.tagNames, hasLength(1), reason: '$locale: "$example"');
      }
      AwI18n.instance.setActiveCached(const Locale('en'));
    });

    test('without AI the microphone is not drawn, so its step is left out', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // No session → AiStatus.disabled.
      c.read(tourControllerProvider.notifier).start();
      expect(c.read(tourControllerProvider).steps, [
        kTourQuickAdd,
        kTourAlarm,
        kTourSearch,
      ]);
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
        final steps = c.read(tourControllerProvider).steps;
        for (var i = 0; i < steps.length - 1; i++) {
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

    expect(find.text('Type it fast'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tour-skip')));
    await tester.pumpAndSettle();
    expect(find.text('Type it fast'), findsNothing);
    expect(await localKv.get(kOnboardingSeenKey), 'true');
  });

  testWidgets('Next walks the four steps to Done and persists', (tester) async {
    final api = FakeApi()..aiEnabled = true;
    await tester.pumpWidget(await tourApp(api, tourEnabled: true));
    await tester.pumpAndSettle();

    for (final title in const [
      'Type it fast',
      'Add by voice',
      'Urgent alarm',
      'Search everywhere',
    ]) {
      expect(
        find.descendant(
          of: find.byType(TourOverlay),
          matching: find.text(title),
        ),
        findsOneWidget,
      );
      if (title == 'Search everywhere') break;
      await tester.tap(find.byKey(const Key('tour-next')));
      await tester.pumpAndSettle();
    }
    // The last step: Done, and no Skip beside it.
    expect(find.text('Done'), findsOneWidget);
    expect(find.byKey(const Key('tour-skip')), findsNothing);
    await tester.tap(find.byKey(const Key('tour-next'))); // Done
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tour-next')), findsNothing);
    expect(await localKv.get(kOnboardingSeenKey), 'true');
  });

  // OPH-404: each step points at the thing it names — Home's field, the
  // microphone, the search button beside the bar — and Skip sits in the
  // card, left of a Next that does not move.
  testWidgets('on a phone every step spotlights its own control', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = FakeApi()..aiEnabled = true;
    await tester.pumpWidget(await tourApp(api, tourEnabled: true));
    await tester.pumpAndSettle();

    Rect spot() => tester.getRect(find.byKey(const Key('tour-spotlight')));
    void covers(Finder target) {
      final rect = tester.getRect(target);
      expect(spot().contains(rect.center), isTrue, reason: '$target');
    }

    covers(find.byKey(const Key('home-quick-add')));
    final next = tester.getRect(find.byKey(const Key('tour-next')));
    final skip = tester.getRect(find.byKey(const Key('tour-skip')));
    expect(skip.right, lessThanOrEqualTo(next.left));
    expect((skip.center.dy - next.center.dy).abs(), lessThan(1));
    // The card sits below the field it explains, not off the top.
    expect(next.top, greaterThan(spot().bottom));

    await tester.tap(find.byKey(const Key('tour-next')));
    await tester.pumpAndSettle();
    covers(find.byType(AiFab));
    expect(
      tester.getRect(find.byKey(const Key('tour-next'))).right,
      moreOrLessEquals(next.right, epsilon: 1),
      reason: 'Next stays in one place',
    );

    await tester.tap(find.byKey(const Key('tour-next')));
    await tester.pumpAndSettle();
    expect(find.text('Urgent alarm'), findsOneWidget);
    expect(find.byKey(const Key('tour-spotlight')), findsNothing);

    await tester.tap(find.byKey(const Key('tour-next')));
    await tester.pumpAndSettle();
    covers(find.byKey(const Key('global-search-orb')));
  });

  testWidgets('on a desktop the search step points at the rail entry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(await tourApp(FakeApi(), tourEnabled: true));
    await tester.pumpAndSettle();
    // No AI on this server: three steps, the last one search.
    await tester.tap(find.byKey(const Key('tour-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tour-next')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(TourOverlay),
        matching: find.text('Search everywhere'),
      ),
      findsOneWidget,
    );
    final spot = tester.getRect(find.byKey(const Key('tour-spotlight')));
    final rail = tester.getRect(
      find.byKey(const Key('global-search-rail')).first,
    );
    expect(spot.contains(rail.center), isTrue);
  });

  testWidgets('does NOT auto-start when the device has already seen it', (
    tester,
  ) async {
    await tester.pumpWidget(
      await tourApp(FakeApi(), tourEnabled: true, seen: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Type it fast'), findsNothing);
    expect(find.byKey(const Key('tour-skip')), findsNothing);
  });

  // UI-AUDIT #83 (OPH-356): a member of an organisation walked through seven
  // steps of the personal app — nothing about Requests, the one thing they
  // came for, and Files promising "personal folders" the organisation's own
  // handbook says do not exist.
  group('UI-AUDIT #83: the tour in a team\'s window', () {
    ProviderContainer containerFor({required bool itsm, AwTeamOrigin? team}) {
      final c = ProviderContainer(
        overrides: [
          eeFeatureProvider.overrideWith((ref, name) => itsm),
          teamOriginProvider.overrideWithValue(team),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    final acme = teamOriginOf('https://acme.example.com', 'example.com');

    test('the service desk gets its step, and Files makes no personal '
        'promise', () {
      final c = containerFor(itsm: true, team: acme);
      c.read(tourControllerProvider.notifier).start();
      final steps = c.read(tourControllerProvider).steps;
      // OPH-404: the desk takes the microphone's place; no step promises
      // personal folders, because no step tours Files at all.
      expect(steps, same(kTeamTourSteps));
      expect(steps, hasLength(4));
      expect(steps[1].section, AppSection.tickets);
      expect(steps, isNot(contains(kTourVoice)));
      for (final s in steps) {
        expect(s.body, isNot(contains('personal folders')));
        expect(s.body, isNot(contains('kişisel')));
        expect(s.title, isNotEmpty);
        expect(s.body, isNotEmpty);
      }
    });

    test('the personal app, and a licensed instance off a team\'s address, '
        'keep the personal tour', () {
      for (final c in [
        containerFor(itsm: false, team: acme),
        containerFor(itsm: true, team: null),
      ]) {
        c.read(tourControllerProvider.notifier).start();
        final steps = c.read(tourControllerProvider).steps;
        expect(steps, isNot(contains(kTeamTourSteps[1])));
        expect(steps.first, kTourQuickAdd);
      }
    });

    test('a running tour keeps its script when the window changes', () {
      final c = containerFor(itsm: true, team: acme);
      final ctl = c.read(tourControllerProvider.notifier);
      ctl.start();
      ctl.next();
      expect(c.read(tourControllerProvider).steps, same(kTeamTourSteps));
    });
  });
}
