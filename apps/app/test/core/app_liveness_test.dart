import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/app_liveness.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';

/// OPH-318 — what a background turn asks before it touches the replica the
/// running app may already be syncing.
class _MemoryKv implements LocalKv {
  final Map<String, String> values = {};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

void main() {
  late _MemoryKv kv;
  late AppLiveness liveness;

  final now = DateTime.utc(2026, 9, 16, 9, 0);

  setUp(() {
    kv = _MemoryKv();
    liveness = AppLiveness(kv);
  });

  test('says nothing is running before anything has said so', () async {
    expect(await liveness.isForeground(now), isFalse);
  });

  test('a fresh stamp means the app is in front of the user', () async {
    await liveness.markForeground(now);
    expect(await liveness.isForeground(now), isTrue);
    expect(
      await liveness.isForeground(now.add(const Duration(minutes: 30))),
      isTrue,
    );
  });

  test(
    'leaving the foreground removes the stamp rather than ageing it',
    () async {
      await liveness.markForeground(now);
      await liveness.markBackground();

      expect(kv.values, isEmpty);
      expect(await liveness.isForeground(now), isFalse);
    },
  );

  test(
    'a stamp nobody renewed expires, so a kill cannot disable refresh',
    () async {
      // The case this bound exists for: the OS kills a foregrounded app, so
      // nothing ever runs `markBackground`. Without expiry that device would
      // skip every background refresh from then on — silently, forever.
      await liveness.markForeground(now);
      expect(
        await liveness.isForeground(now.add(AppLiveness.staleAfter)),
        isFalse,
      );
      expect(
        await liveness.isForeground(
          now.add(AppLiveness.staleAfter - const Duration(minutes: 1)),
        ),
        isTrue,
      );
    },
  );

  test('a stamp we cannot read is not a yes', () async {
    // The safe direction is to let the refresh run: a redundant sync is
    // idempotent, a skipped one leaves a phone with a stale alarm.
    kv.values['alliswell_foreground_since'] = 'once upon a time';
    expect(await liveness.isForeground(now), isFalse);
  });

  test('a stamp from the future is not a yes either', () async {
    // A clock change, or a stamp written on a device whose time was wrong.
    await liveness.markForeground(now.add(const Duration(days: 1)));
    expect(await liveness.isForeground(now), isFalse);
  });

  test('the stamp survives a timezone, because it is stored in UTC', () async {
    await liveness.markForeground(DateTime.utc(2026, 9, 16, 9).toLocal());
    expect(kv.values.values.single, endsWith('Z'));
    expect(await liveness.isForeground(now), isTrue);
  });
}
