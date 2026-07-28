import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/alarm_overlay.dart';
import 'package:alliswell/src/notifications/alarm_sound.dart';

/// A recording stand-in for the audio plugin — the seam OPH-180 exists behind.
class FakeAlarmSound implements AlarmSoundPlayer {
  FakeAlarmSound({this.failLoop = false});

  bool failLoop;
  final List<String> looped = [];
  int stops = 0;
  int disposes = 0;

  @override
  Future<void> loop(String asset) async {
    if (failLoop) throw StateError('autoplay blocked');
    looped.add(asset);
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async => disposes++;
}

/// OPH-180 — the ring screen makes NOISE now (DESIGN §11 A3). Round 9's report
/// had the app open and silent, and on desktop/web there is no OS alarm at all.
void main() {
  test('starting the alarm loops the bundled bed', () async {
    final sound = FakeAlarmSound();
    final feedback = AudioAlarmFeedback(sound);

    feedback.start();
    await pumpEventQueue();

    expect(sound.looped, [kAlarmSoundAsset]);
    expect(feedback.soundBlocked.value, isFalse);
  });

  test('answering the alarm stops it', () async {
    final sound = FakeAlarmSound();
    final feedback = AudioAlarmFeedback(sound);

    feedback.start();
    await pumpEventQueue();
    feedback.stop();
    await pumpEventQueue();

    expect(sound.stops, greaterThanOrEqualTo(1));
  });

  test('a platform that refuses to play is admitted, not hidden', () async {
    final sound = FakeAlarmSound(failLoop: true);
    final feedback = AudioAlarmFeedback(sound);

    feedback.start();
    await pumpEventQueue();

    // The ring screen watches this to offer "start the sound" — the honest
    // alternative to a silent alarm that looks like it is ringing.
    expect(feedback.soundBlocked.value, isTrue);
    expect(sound.looped, isEmpty);

    // And a manual retry can still succeed.
    sound.failLoop = false;
    feedback.start();
    await pumpEventQueue();
    expect(feedback.soundBlocked.value, isFalse);
    expect(sound.looped, [kAlarmSoundAsset]);
    feedback.stop();
  });

  test('disposing releases the player', () async {
    final sound = FakeAlarmSound();
    final feedback = AudioAlarmFeedback(sound);
    feedback.start();
    await pumpEventQueue();
    await feedback.dispose();
    expect(sound.disposes, 1);
  });

  test('the silent implementation stays silent and never blocks', () {
    const feedback = SilentAlarmFeedback();
    feedback.start();
    feedback.stop();
    expect(feedback.soundBlocked, isA<ValueListenable<bool>>());
    expect(feedback.soundBlocked.value, isFalse);
  });
}
