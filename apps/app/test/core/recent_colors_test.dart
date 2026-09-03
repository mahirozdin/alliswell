import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/recent_colors.dart';

/// OPH-259 — one colour memory, shared by every picker (DESIGN §33 R2).
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await localKv.remove(kAwRecentColorsKey);
  });

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('picks are remembered newest-first', () async {
    final c = container();
    final recents = c.read(recentColorsProvider.notifier);

    await recents.remember('#2563EB');
    await recents.remember('#EF4444');

    expect(c.read(recentColorsProvider), ['#EF4444', '#2563EB']);
  });

  test('re-picking moves a colour up instead of duplicating it', () async {
    final c = container();
    final recents = c.read(recentColorsProvider.notifier);

    await recents.remember('#2563EB');
    await recents.remember('#EF4444');
    await recents.remember('#2563EB');

    expect(
      c.read(recentColorsProvider),
      ['#2563EB', '#EF4444'],
      reason: 'the same colour five times is not a memory',
    );
  });

  test('the list is capped, and survives a restart', () async {
    final c = container();
    final recents = c.read(recentColorsProvider.notifier);
    for (var i = 0; i < kAwRecentColorsKept + 3; i++) {
      await recents.remember('#00000$i');
    }
    expect(c.read(recentColorsProvider), hasLength(kAwRecentColorsKept));

    // A fresh container is what a restart looks like from here.
    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    restarted.read(recentColorsProvider);
    await Future<void>.delayed(Duration.zero);
    expect(
      restarted.read(recentColorsProvider),
      hasLength(kAwRecentColorsKept),
    );
  });

  test('a junk preference is no memory, not a crash', () async {
    await localKv.set(kAwRecentColorsKey, 'not json at all');
    final c = container();
    c.read(recentColorsProvider);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(recentColorsProvider), isEmpty);

    await localKv.set(kAwRecentColorsKey, jsonEncode([1, 2, 3]));
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(recentColorsProvider);
    await Future<void>.delayed(Duration.zero);
    expect(c2.read(recentColorsProvider), isEmpty);
  });

  group('what a surface may offer', () {
    test('only its own palette, newest first, capped at five', () {
      const palette = ['#2563EB', '#EF4444', '#10B981'];
      const recents = [
        '#111111', // another surface's colour — must not leak in
        '#EF4444',
        '#10B981',
        '#2563EB',
      ];

      expect(awRecentColorsFor(recents, palette), [
        '#EF4444',
        '#10B981',
        '#2563EB',
      ]);
    });

    test('an empty intersection means no row at all', () {
      expect(awRecentColorsFor(const ['#111111'], const ['#2563EB']), isEmpty);
    });

    test('case does not decide membership', () {
      expect(
        awRecentColorsFor(const ['#2563eb'], const ['#2563EB']),
        isNotEmpty,
      );
    });
  });
}
