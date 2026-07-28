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
import 'package:alliswell/src/notifications/providers.dart';
import 'package:alliswell/src/notifications/alarm_sound.dart';
import 'package:alliswell/src/notifications/reminder_profile.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-179 — "Hatırlatıcı Sistemi Ayarları" (DESIGN §18): presets first, the
/// step editor as the escape hatch, limits stated, and drag only where order is
/// the user's to choose.
Future<Widget> signedInApp(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
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

void main() {
  setUp(() async {
    // localKv is a global singleton whose cache outlives a test.
    await localKv.remove('alliswell_reminder_profile');
    await localKv.remove('alliswell_snooze_presets');
    await localKv.remove('alliswell_alarm_sound');
    await localKv.remove('alliswell_reminder_sound');
  });

  Future<ProviderContainer> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await signedInApp(FakeApi()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle();

    final row = find.byKey(const Key('settings-reminder-system'));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(AllisWellApp)));
  }

  testWidgets('a preset sets the chain, and the timeline shows when it rings', (
    tester,
  ) async {
    final container = await open(tester);
    expect(
      container.read(reminderProfileProvider).slots,
      ReminderProfile.factory.slots,
    );

    // The timeline answers "when will these actually ring?" up front.
    expect(find.byKey(const Key('reminder-timeline')), findsOneWidget);
    final timeline = tester
        .widget<Text>(find.byKey(const Key('reminder-timeline')))
        .data!;
    expect(timeline.split('→'), hasLength(5)); // the standard chain

    await tester.tap(find.text('Calm'));
    await tester.pumpAndSettle();
    expect(container.read(reminderProfileProvider).slots, [0]);
    expect(
      tester.widget<Text>(find.byKey(const Key('reminder-timeline'))).data,
      isNot(contains('→')),
      reason: 'one alert, one instant',
    );
  });

  testWidgets('the step editor adds, shifts and removes alerts', (
    tester,
  ) async {
    final container = await open(tester);
    final before = container.read(reminderProfileProvider).slots.length;

    await tester.tap(find.byKey(const Key('reminder-add-step')));
    await tester.pumpAndSettle();
    expect(
      container.read(reminderProfileProvider).slots,
      hasLength(before + 1),
    );

    // The stepper keeps the 1-minute rule while editing: the second alert can
    // never step below the first + 1.
    await tester.tap(find.byKey(const Key('reminder-step-1-minus')));
    await tester.pumpAndSettle();
    var slots = container.read(reminderProfileProvider).slots;
    expect(slots[1], greaterThan(slots[0]));

    await tester.tap(find.byKey(const Key('reminder-step-1-remove')));
    await tester.pumpAndSettle();
    slots = container.read(reminderProfileProvider).slots;
    expect(slots, hasLength(before));

    await tester.tap(find.byKey(const Key('reminder-reset')));
    await tester.pumpAndSettle();
    expect(
      container.read(reminderProfileProvider).slots,
      ReminderProfile.factory.slots,
    );
  });

  testWidgets('the OS budget is stated, and long chains are warned about', (
    tester,
  ) async {
    final container = await open(tester);

    // Standard: 40 window / 5 alerts.
    expect(find.textContaining('about 8 alarms'), findsOneWidget);
    expect(find.byKey(const Key('reminder-capacity-warning')), findsNothing);

    await tester.tap(find.text('Insistent'));
    await tester.pumpAndSettle();
    expect(container.read(reminderProfileProvider).slots, hasLength(10));

    // 11 alerts is where the honest warning appears — never a silent trim.
    await tester.tap(find.byKey(const Key('reminder-add-step')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reminder-capacity-warning')), findsOneWidget);
  });

  testWidgets('snooze buttons can be reordered — the one list where order is '
      'the data (N4)', (tester) async {
    final container = await open(tester);
    expect(container.read(snoozePresetOrderProvider).first, '5_min');

    final list = find.byKey(const Key('snooze-order-list'));
    await tester.scrollUntilVisible(
      list,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // The default handles use a DELAYED drag listener on mobile targets (which
    // is what a widget test is), so this is a long-press lift, not a plain drag.
    final handles = find.byIcon(Icons.drag_handle);
    final gesture = await tester.startGesture(tester.getCenter(handles.at(1)));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(handles.at(0)));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      container.read(snoozePresetOrderProvider).first,
      '30_min',
      reason: 'the ringing alarm shows them in this order',
    );
  });

  testWidgets('turning off repeat-after-snooze is remembered', (tester) async {
    final container = await open(tester);
    expect(container.read(reminderProfileProvider).repeatAfterSnooze, isTrue);

    final toggle = find.byKey(const Key('reminder-repeat-after-snooze'));
    await tester.scrollUntilVisible(
      toggle,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(container.read(reminderProfileProvider).repeatAfterSnooze, isFalse);
  });

  // ── OPH-181: sounds are chosen by hearing them (N6) ────────────────────────

  testWidgets('the sound rows open a picker with the OS sound and the bundled '
      'ones, and remember the choice', (tester) async {
    final container = await open(tester);
    expect(
      container.read(alarmSoundChoiceProvider).bundledId,
      'aw_alarm',
      reason: 'the alarm bed is the factory alarm sound',
    );
    expect(
      container.read(reminderSoundChoiceProvider).isOsDefault,
      isTrue,
      reason: 'ordinary reminders keep the OS sound until asked otherwise',
    );

    final row = find.byKey(const Key('sound-row-alarm'));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();

    // Every shipped option is offered, and so is the OS's own sound.
    expect(find.byKey(const Key('sound-os')), findsOneWidget);
    for (final sound in kBundledSounds) {
      expect(find.byKey(Key('sound-bundled-${sound.id}')), findsOneWidget);
    }
    // …with a play button each: you pick a sound by hearing it.
    expect(find.byKey(const Key('sound-preview-chime')), findsOneWidget);
    // The platform truth is stated where the decision is made.
    expect(find.textContaining('under 30 seconds'), findsOneWidget);
    expect(find.byKey(const Key('sound-upload')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sound-bundled-chime')));
    await tester.pumpAndSettle();
    expect(container.read(alarmSoundChoiceProvider).bundledId, 'chime');
  });

  testWidgets('picking the OS sound is a real choice, not an empty one', (
    tester,
  ) async {
    final container = await open(tester);
    final row = find.byKey(const Key('sound-row-alarm'));
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sound-os')));
    await tester.pumpAndSettle();
    expect(container.read(alarmSoundChoiceProvider).isOsDefault, isTrue);
  });
}
