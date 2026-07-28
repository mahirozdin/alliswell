import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/alarm_sound.dart';
import 'package:alliswell/src/notifications/gateway.dart';
import 'package:alliswell/src/notifications/planner.dart';
import 'package:alliswell/src/notifications/sound_store.dart';

/// A sound store that records instead of touching a filesystem.
class FakeSoundStore implements SoundStore {
  FakeSoundStore({this.failInstall = false});

  bool failInstall;
  final Map<String, List<int>> files = {};
  final List<String> installedAssets = [];

  @override
  Future<String?> installAsset(String assetPath) async {
    if (failInstall) return null;
    final name = assetPath.split('/').last;
    installedAssets.add(assetPath);
    files[name] = const [];
    return name;
  }

  @override
  Future<String?> installBytes(String name, List<int> bytes) async {
    if (failInstall) return null;
    files[name] = bytes;
    return name;
  }

  @override
  Future<bool> isInstalled(String name) async => files.containsKey(name);

  @override
  Future<List<String>> installed() async => files.keys.toList();

  @override
  Future<void> remove(String name) async => files.remove(name);
}

/// OPH-181 — the ringtone catalogue, the format truth, and what each platform
/// can actually be told to play (NOTIFICATIONS §2c).
void main() {
  group('choices survive storage and junk', () {
    test('round-trips every shape', () {
      for (final choice in [
        const AwSoundChoice.os(),
        const AwSoundChoice.bundled('chime'),
        const AwSoundChoice.file('01FILE'),
      ]) {
        final parsed = AwSoundChoice.parse(choice.encode());
        expect(parsed.encode(), choice.encode());
      }
    });

    test(
      'junk, empties and retired ids resolve to the OS sound, never silence',
      () {
        for (final raw in [
          null,
          '',
          'nope',
          'bundled:',
          'bundled:gone',
          'file:',
        ]) {
          expect(
            AwSoundChoice.parse(raw).isOsDefault,
            isTrue,
            reason:
                'a broken preference must not cost the user an audible alarm',
          );
        }
      },
    );
  });

  group('format honesty (N6)', () {
    test('only iOS-playable containers can be a notification sound', () {
      expect(soundUsability('zil.caf'), AwSoundUsability.everywhere);
      expect(soundUsability('zil.WAV'), AwSoundUsability.everywhere);
      expect(soundUsability('zil.aiff'), AwSoundUsability.everywhere);
      // The formats people actually have — and the reason we say so at upload
      // time instead of at 03:00.
      expect(soundUsability('zil.mp3'), AwSoundUsability.inAppOnly);
      expect(soundUsability('zil.m4a'), AwSoundUsability.inAppOnly);
      expect(soundUsability('zil'), AwSoundUsability.inAppOnly);
    });
  });

  group('resolving a choice per platform', () {
    test(
      'iOS: the bundled bed is in the app, the tones install themselves',
      () async {
        final store = FakeSoundStore();
        final resolver = AlarmSoundResolver(
          store: store,
          isIos: true,
          isAndroid: false,
        );

        final bed = await resolver.resolve(
          const AwSoundChoice.bundled('aw_alarm'),
        );
        expect(bed.name, 'aw_alarm.caf');
        expect(store.installedAssets, isEmpty); // already in the bundle

        final chime = await resolver.resolve(
          const AwSoundChoice.bundled('chime'),
        );
        expect(chime.name, 'aw_chime.caf');
        expect(store.installedAssets, ['assets/audio/aw_chime.caf']);
        expect(chime.degradedReason, isNull);
      },
    );

    test(
      'iOS: a failed install is admitted, not passed off as a sound',
      () async {
        final resolver = AlarmSoundResolver(
          store: FakeSoundStore(failInstall: true),
          isIos: true,
          isAndroid: false,
        );
        final resolved = await resolver.resolve(
          const AwSoundChoice.bundled('ping'),
        );
        expect(resolved.name, isNull);
        expect(resolved.degradedReason, isNotNull);
      },
    );

    test(
      'iOS: a custom sound resolves ONLY when it is really installed',
      () async {
        final store = FakeSoundStore();
        final resolver = AlarmSoundResolver(
          store: store,
          isIos: true,
          isAndroid: false,
        );

        // Not installed yet: this is the guard OPH-176 deferred here — iOS would
        // silently substitute the default ding, so we say so instead.
        var resolved = await resolver.resolve(
          const AwSoundChoice.file('01FILE'),
        );
        expect(resolved.name, isNull);
        expect(resolved.degradedReason, 'custom-sound-missing');

        await store.installBytes('01FILE.caf', const [1, 2, 3]);
        resolved = await resolver.resolve(const AwSoundChoice.file('01FILE'));
        expect(resolved.name, '01FILE.caf');
        expect(resolved.degradedReason, isNull);
      },
    );

    test('Android: bundled sounds are raw resources; custom ones are stated as '
        'unsupported for channels', () async {
      final resolver = AlarmSoundResolver(
        store: FakeSoundStore(),
        isIos: false,
        isAndroid: true,
      );
      expect(
        (await resolver.resolve(const AwSoundChoice.bundled('chime'))).name,
        'aw_chime',
      );
      final custom = await resolver.resolve(const AwSoundChoice.file('01FILE'));
      expect(custom.name, isNull);
      expect(custom.degradedReason, 'android-custom-sound-unsupported');
    });

    test('the OS default asks for no file at all', () async {
      final resolver = AlarmSoundResolver(
        store: FakeSoundStore(),
        isIos: true,
        isAndroid: false,
      );
      final resolved = await resolver.resolve(const AwSoundChoice.os());
      expect(resolved.name, isNull);
      expect(resolved.degradedReason, isNull);
    });
  });

  group('the planner carries the chosen sound', () {
    final now = DateTime.utc(2026, 7, 15, 12);
    AlarmInput alarm({bool urgent = false}) => AlarmInput(
      reminderId: 'R1'.padRight(26, '0'),
      taskId: 'T1'.padRight(26, '0'),
      taskTitle: 'Görev',
      remindAt: now.add(const Duration(hours: 1)),
      status: 'scheduled',
      urgent: urgent,
      requiresAcknowledgement: false,
    );

    test('each lane gets its own sound', () {
      final plan = planNotifications(
        alarms: [alarm(urgent: true), alarm(urgent: false)],
        now: now,
        privacyMode: false,
        alarmSoundName: 'aw_alarm.caf',
        reminderSoundName: 'aw_chime.caf',
      );
      final urgent = plan.firstWhere((n) => n.urgent);
      final normal = plan.firstWhere((n) => !n.urgent);
      expect(urgent.soundName, 'aw_alarm.caf');
      expect(normal.soundName, 'aw_chime.caf');
    });

    test('changing the sound changes the id, so it RESCHEDULES', () {
      List<int> idsWith(String? sound) => planNotifications(
        alarms: [alarm(urgent: true)],
        now: now,
        privacyMode: false,
        alarmSoundName: sound,
      ).map((n) => n.id).toList();

      expect(idsWith('aw_alarm.caf'), isNot(idsWith('aw_chime.caf')));
      // …and an unchanged sound must NOT churn the schedule.
      expect(idsWith('aw_alarm.caf'), idsWith('aw_alarm.caf'));
    });

    test('the delivery description reports the sound the log will show', () {
      final delivery = awDeliveryFor(
        urgent: true,
        criticalEnabled: false,
        soundName: '01FILE.caf',
      );
      expect(delivery.sound, '01FILE.caf');
      // No choice → the lane's default name, as before.
      expect(
        awDeliveryFor(urgent: true, criticalEnabled: false).sound,
        kAwAlarmSoundName,
      );
    });
  });
}
