import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/settings/sound_picker_sheet.dart';
import 'package:alliswell/src/notifications/alarm_sound.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-190 — a preview you can stop (DESIGN §18 N6).
///
/// Round 10 #5, in the user's words: the stop button does not stop, tapping
/// another sound waits for the first to finish, and closing the sheet leaves
/// the sound playing. All three came from one shape — the player was built
/// inside the method that started it, so nothing else could reach it. These
/// tests assert the CALL ORDER on a fake player, which is where that shape
/// is visible.
class _FakePlayer implements AlarmSoundPlayer {
  _FakePlayer(this.log, this.index);

  final List<String> log;
  final int index;

  @override
  Future<void> loop(String asset) async => log.add('loop$index:$asset');

  @override
  Future<void> stop() async => log.add('stop$index');

  @override
  Future<void> dispose() async => log.add('dispose$index');
}

class _ThrowingPlayer implements AlarmSoundPlayer {
  @override
  Future<void> loop(String asset) async => throw StateError('no audio');

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// Opens the picker inside a SIGNED-IN scope: the sheet watches the workspace
/// (for the ringtone folder), so a bare `ProviderScope` leaves the auth
/// controller's restore timer pending and teardown fails for the wrong reason.
Future<void> pumpPicker(
  WidgetTester tester, {
  required AlarmSoundPlayer Function() player,
}) async {
  SharedPreferences.setMockInitialValues({});
  final secrets = InMemorySecretStore();
  await TokenStorage(secrets).save(fakeSession());
  final api = FakeApi();

  await tester.pumpWidget(
    ProviderScope(
      retry: awRetry,
      overrides: [
        ...syncTestOverrides(),
        secretStoreProvider.overrideWithValue(secrets),
        apiClientProvider.overrideWithValue(
          fakeDio(FakeHttpClientAdapter(api.handle)),
        ),
        soundPreviewPlayerProvider.overrideWithValue(player),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSoundPicker(context, SoundLane.alarm),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the stop button actually stops', (tester) async {
    final log = <String>[];
    var made = 0;
    await pumpPicker(tester, player: () => _FakePlayer(log, made++));

    await tester.tap(find.byKey(const Key('sound-preview-chime')));
    await tester.pump();
    expect(log.where((e) => e.startsWith('loop')), hasLength(1));
    // The icon flipped to stop — and so must the behaviour.
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

    await tester.tap(find.byKey(const Key('sound-preview-chime')));
    await tester.pumpAndSettle();

    expect(log, contains('stop0'));
    expect(log, contains('dispose0'));
    expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);
    // Nothing left ticking either: the auto-stop is a cancellable Timer, so
    // stopping by hand cancels it. flutter_test fails teardown on a surviving
    // timer — exactly the leak an awaited `Future.delayed` used to hide.
  });

  testWidgets('a second sound interrupts the first instead of queueing', (
    tester,
  ) async {
    final log = <String>[];
    var made = 0;
    await pumpPicker(tester, player: () => _FakePlayer(log, made++));

    await tester.tap(find.byKey(const Key('sound-preview-chime')));
    await tester.pump();
    // The old code disabled EVERY preview button while one played, so this tap
    // did nothing at all until the first sound ran out.
    await tester.tap(find.byKey(const Key('sound-preview-ping')));
    await tester.pump();

    final firstStop = log.indexOf('stop0');
    final secondLoop = log.indexWhere((e) => e.startsWith('loop1'));
    expect(firstStop, isNonNegative, reason: 'the first sound must be stopped');
    expect(secondLoop, isNonNegative, reason: 'the second must start');
    expect(
      firstStop,
      lessThan(secondLoop),
      reason: 'stop the old one BEFORE starting the new one',
    );

    // Let the surviving preview's auto-stop fire so no timer outlives the test.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('closing the sheet silences the preview', (tester) async {
    final log = <String>[];
    var made = 0;
    await pumpPicker(tester, player: () => _FakePlayer(log, made++));

    await tester.tap(find.byKey(const Key('sound-preview-chime')));
    await tester.pump();
    expect(log.any((e) => e.startsWith('loop')), isTrue);

    // Dismiss the modal the way a user does.
    Navigator.of(tester.element(find.byKey(const Key('sound-os')))).pop();
    await tester.pumpAndSettle();

    expect(
      log,
      contains('stop0'),
      reason: 'audio must not outlive the surface that started it',
    );
    expect(log, contains('dispose0'));
  });

  testWidgets('a preview that cannot start does not pretend to play', (
    tester,
  ) async {
    await pumpPicker(tester, player: _ThrowingPlayer.new);

    await tester.tap(find.byKey(const Key('sound-preview-chime')));
    await tester.pumpAndSettle();

    // No stuck "stop" icon on a platform that refused to play.
    expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);
    expect(find.byIcon(Icons.play_circle_outline), findsWidgets);
  });
}
