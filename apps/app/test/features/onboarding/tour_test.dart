import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'package:alliswell/src/features/home/home_screen.dart'
    show tourAlarmTaskId;
import 'package:alliswell/src/features/home/task_grouping.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sections.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart'
    show currentUserIdProvider;

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// A script the test can change under a running tour (R-01): the answers
/// that pick it (AI status, the service desk) can arrive after it started.
class _Script extends Notifier<List<TourStep>> {
  @override
  List<TourStep> build() => const [kTourQuickAdd, kTourAlarm, kTourSearch];

  void set(List<TourStep> steps) => state = steps;
}

final _scriptProvider = NotifierProvider<_Script, List<TourStep>>(_Script.new);

/// Grows when told to, from outside the overlay's subtree: what the alarm
/// banner does to Home's field after the tour has measured it (R-01).
class _Grower extends StatefulWidget {
  const _Grower({super.key});

  @override
  State<_Grower> createState() => _GrowerState();
}

class _GrowerState extends State<_Grower> {
  double height = 20;

  void grow() => setState(() => height = 160);

  @override
  Widget build(BuildContext context) => SizedBox(height: height);
}

/// Measures [target] while it builds — the overlay's resolveAnchor runs in
/// build too (initState, didUpdateWidget).
class _Probe extends StatelessWidget {
  // ignore: prefer_const_constructors_in_immutables
  _Probe(this.onRect);

  final void Function(Rect?) onRect;

  @override
  Widget build(BuildContext context) {
    onRect(TourAnchor.rectOf(TourTarget.quickAdd));
    return const SizedBox(height: 10);
  }
}

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
        // Polish 4 T-03: the first task that will ring, else the field.
        TourTarget.alarm,
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
    // Polish 4 T-03: no task that will ring yet — the step points at the
    // field where a time is typed, not a centred card over the calendar.
    covers(find.byKey(const Key('home-quick-add')));

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

  // R-01 (polish 2): the first run showed a red error screen on two devices
  // out of two, step 1 framed the alarm banner instead of the field, a
  // server without a provider lost the voice step although the microphone
  // was drawn, and a member's Requests step came in one run of four.
  group('R-01: the tour on a real first run', () {
    testWidgets('an anchor that has just left the tree is not measured — '
        'no "renderObject of inactive element"', (tester) async {
      var show = true;
      late StateSetter setOuter;
      final rects = <Rect?>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return Column(
                children: [
                  if (show)
                    const TourAnchor(
                      target: TourTarget.quickAdd,
                      child: SizedBox(height: 40, width: 40),
                    )
                  else
                    const SizedBox(height: 40),
                  // Built after the anchor was deactivated, in the same
                  // frame — before it is unmounted.
                  _Probe(rects.add),
                ],
              );
            },
          ),
        ),
      );
      await tester.pump();
      expect(TourAnchor.rectOf(TourTarget.quickAdd), isNotNull);

      setOuter(() => show = false);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(rects.last, isNull);
      expect(TourAnchor.rectOf(TourTarget.quickAdd), isNull);
    });

    testWidgets('the spotlight follows its control when something above it '
        'grows after the tour measured it', (tester) async {
      final grower = GlobalKey<_GrowerState>();
      final state = const TourState(
        running: true,
        steps: [kTourQuickAdd, kTourAlarm, kTourSearch],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Column(
                children: [
                  _Grower(key: grower),
                  const TourAnchor(
                    target: TourTarget.quickAdd,
                    child: SizedBox(key: Key('field'), height: 48, width: 300),
                  ),
                ],
              ),
              Positioned.fill(
                child: TourOverlay(
                  state: state,
                  resolveAnchor: () => TourAnchor.rectOf(TourTarget.quickAdd),
                  onNext: () {},
                  onSkip: () {},
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      Rect spot() => tester.getRect(find.byKey(const Key('tour-spotlight')));
      expect(
        spot().contains(tester.getCenter(find.byKey(const Key('field')))),
        isTrue,
      );

      grower.currentState!.grow();
      await tester.pumpAndSettle();
      final field = tester.getRect(find.byKey(const Key('field')));
      expect(
        spot().contains(field.center),
        isTrue,
        reason: 'spotlight ${spot()} stayed where the field was, not at $field',
      );
      // The card goes below the field, not over it.
      expect(
        tester.getRect(find.byKey(const Key('tour-next'))).top,
        greaterThan(field.bottom),
      );
    });

    test('an answer that arrives on the first step changes the script: the '
        'voice step and the desk step are not lost to a slow start', () {
      final c = ProviderContainer(
        overrides: [
          tourStepsProvider.overrideWith((ref) => ref.watch(_scriptProvider)),
        ],
      );
      addTearDown(c.dispose);
      final ctl = c.read(tourControllerProvider.notifier);
      ctl.start();
      expect(c.read(tourControllerProvider).steps, hasLength(3));

      // AI turns out to be on (a cold start answered "disabled" while the
      // workspace was loading).
      c.read(_scriptProvider.notifier).set(kTourSteps);
      expect(c.read(tourControllerProvider).steps, same(kTourSteps));
      expect(c.read(tourControllerProvider).step, 0);
      expect(c.read(tourControllerProvider).running, isTrue);

      // The organisation's answer arrives later still: the desk's script.
      c.read(_scriptProvider.notifier).set(kTeamTourSteps);
      expect(c.read(tourControllerProvider).steps, same(kTeamTourSteps));

      // Past the first step the numbering is fixed.
      ctl.next();
      c.read(_scriptProvider.notifier).set(kTourSteps);
      expect(c.read(tourControllerProvider).steps, same(kTeamTourSteps));
      expect(c.read(tourControllerProvider).step, 1);

      // A tour that is not running is not started by an answer.
      ctl.skip();
      c.read(_scriptProvider.notifier).set(kTeamTourSteps);
      expect(c.read(tourControllerProvider).running, isFalse);
    });

    testWidgets('auto-start waits for Home\'s field to be laid out', (
      tester,
    ) async {
      final c = ProviderContainer(
        overrides: [
          // Signed out: the status answers come at once, no session timer.
          currentUserIdProvider.overrideWithValue(null),
          tourStepsProvider.overrideWith((ref) => ref.watch(_scriptProvider)),
        ],
      );
      addTearDown(c.dispose);
      var home = false;
      late StateSetter setOuter;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return home
                  ? const TourAnchor(
                      target: TourTarget.quickAdd,
                      child: SizedBox(height: 48),
                    )
                  : const SizedBox();
            },
          ),
        ),
      );
      var started = false;
      unawaited(
        c
            .read(tourControllerProvider.notifier)
            .maybeAutoStart()
            .then((_) => started = true),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        c.read(tourControllerProvider).running,
        isFalse,
        reason: 'Home is not drawn yet',
      );

      setOuter(() => home = true);
      await tester.pump();
      await tester.pump();
      expect(c.read(tourControllerProvider).running, isTrue);
      expect(started, isTrue);
    });

    testWidgets('a window without Home\'s field still gets its tour, after a '
        'bounded wait', (tester) async {
      final c = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue(null),
          tourStepsProvider.overrideWith((ref) => ref.watch(_scriptProvider)),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(const SizedBox());
      unawaited(c.read(tourControllerProvider.notifier).maybeAutoStart());
      await tester.pump(const Duration(seconds: 1));
      expect(c.read(tourControllerProvider).running, isFalse);
      await tester.pump(const Duration(seconds: 3));
      expect(c.read(tourControllerProvider).running, isTrue);
    });
  });

  // Polish 4 T-03 (OPH-404, iOS 06-tour-3/4): step 3 was a centred card
  // over the calendar, pointing at nothing, and step 4 told a phone about
  // Ctrl+K.
  group('T-03: the alarm step points at a row, search speaks to touch', () {
    Future<void> toStep(WidgetTester tester, String title) async {
      while (find
          .descendant(of: find.byType(TourOverlay), matching: find.text(title))
          .evaluate()
          .isEmpty) {
        await tester.tap(find.byKey(const Key('tour-next')));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('step 3 spotlights the first upcoming task that will ring', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      // Both upcoming rows stay inside TODAY whatever the wall clock says:
      // a fixed "+2 h" crossed midnight after 22:00 and sent the ringing row
      // into Tomorrow, below the fold, so the test only failed at night.
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59);
      final left = endOfDay.difference(now);
      final room = left < const Duration(hours: 3)
          ? left
          : const Duration(hours: 3);
      final api = FakeApi()
        // Overdue: it already rang. Not urgent: it will not ring.
        ..seedTask(
          title: 'Rang yesterday',
          isUrgent: true,
          dueAt: now
              .subtract(const Duration(days: 1))
              .toUtc()
              .toIso8601String(),
        )
        ..seedTask(
          title: 'Quiet one',
          dueAt: now.add(room ~/ 4).toUtc().toIso8601String(),
        );
      final ringing = api.seedTask(
        title: 'Dentist',
        isUrgent: true,
        dueAt: now.add(room * 2 ~/ 3).toUtc().toIso8601String(),
      );
      await tester.pumpWidget(await tourApp(api, tourEnabled: true));
      await tester.pumpAndSettle();
      await toStep(tester, 'Urgent alarm');

      final spot = tester.getRect(find.byKey(const Key('tour-spotlight')));
      final row = tester.getRect(find.byKey(Key('task-due-${ringing['id']}')));
      final field = tester.getRect(find.byKey(const Key('home-quick-add')));
      expect(spot.contains(row.center), isTrue);
      expect(spot.contains(field.center), isFalse);
      // The card does not cover the row it explains.
      final card = tester.getRect(find.byKey(const Key('tour-next')));
      expect(spot.overlaps(card), isFalse);
    });

    testWidgets('a ringing task below the screen is not spotlighted', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final api = FakeApi();
      // Below the fold: laid out in the scroll cache, not on screen.
      for (var i = 0; i < 6; i++) {
        api.seedTask(title: 'Undated $i');
      }
      api.seedTask(
        title: 'Far away',
        isUrgent: true,
        dueAt: now.add(const Duration(days: 20)).toUtc().toIso8601String(),
      );
      await tester.pumpWidget(await tourApp(api, tourEnabled: true));
      await tester.pumpAndSettle();
      await toStep(tester, 'Urgent alarm');

      // The row is laid out (in the scroll cache) but below the screen.
      final laidOut = TourAnchor.rectOf(TourTarget.alarm);
      expect(laidOut, isNotNull);
      expect(laidOut!.top, greaterThan(844));
      expect(TourAnchor.visibleRectOf(TourTarget.alarm), isNull);
      final spot = tester.getRect(find.byKey(const Key('tour-spotlight')));
      final screen = tester.getRect(find.byType(TourOverlay));
      expect(screen.contains(spot.center), isTrue);
      final field = tester.getRect(find.byKey(const Key('home-quick-add')));
      expect(spot.contains(field.center), isTrue);
    });

    test('tourAlarmTaskId skips done, muted, overdue and quiet tasks', () {
      expect(kTourAlarm.target, TourTarget.alarm);
      expect(kTourAlarm.fallback, TourTarget.quickAdd);
      final now = DateTime.utc(2026, 11, 8, 12);
      final api = FakeApi();
      String at(int hours) => now.add(Duration(hours: hours)).toIso8601String();
      Task task(String title, {bool urgent = true, int hours = 2}) =>
          Task.fromJson(
            api.seedTask(title: title, isUrgent: urgent, dueAt: at(hours)),
          );
      final done = Task.fromJson({
        ...api.seedTask(title: 'done', isUrgent: true, dueAt: at(1)),
        'status': 'completed',
        'completedAt': now.toIso8601String(),
      });
      final muted = Task.fromJson({
        ...api.seedTask(title: 'muted', isUrgent: true, dueAt: at(1)),
        'alarmsMutedAt': now.toIso8601String(),
      });
      final overdue = task('overdue', hours: -1);
      final quiet = task('quiet', urgent: false);
      final ringing = task('ringing', hours: 3);
      final later = task('later', hours: 5);
      HomeGroup group(List<Task> tasks) => HomeGroup(
        bucket: HomeBucket.today,
        items: [for (final t in tasks) TaskItem(t)],
        dimmed: false,
      );
      expect(
        tourAlarmTaskId([
          group([overdue, done]),
          group([muted, quiet, ringing, later]),
        ], now),
        ringing.id,
      );
      expect(
        tourAlarmTaskId([
          group([overdue, quiet]),
        ], now),
        isNull,
      );
    });

    testWidgets('on a phone the search step names the button, not Ctrl+K', (
      tester,
    ) async {
      await AwI18n.instance.loadForTest(const Locale('en'));
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(kTourSearch.body, isNot(contains('Ctrl')));
      expect(kTourSearch.body, contains('search button'));
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(kTourSearch.body, isNot(contains('⌘K')));
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(kTourSearch.body, contains('Ctrl+K'));
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(kTourSearch.body, contains('Ctrl+K'));
      debugDefaultTargetPlatformOverride = null;

      await AwI18n.instance.loadForTest(const Locale('tr'));
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(kTourSearch.body, isNot(contains('Ctrl')));
      expect(kTourSearch.body, contains('Arama düğmesine dokun'));
      debugDefaultTargetPlatformOverride = null;
      await AwI18n.instance.loadForTest(const Locale('en'));
    });
  });
}
