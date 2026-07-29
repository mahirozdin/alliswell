import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/quick_access/emoji_input.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_bubble.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-202 — emoji, colour and name (DESIGN §23 Q7/Q8a).
Future<Widget> signedInApp(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
  await resetQuickAccessPrefs();
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

void wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Map<String, dynamic> lastPatch(FakeApi api) =>
    (api.pushedMutations.lastWhere(
              (m) => m['entityType'] == 'quick_link',
            )['patch']
            as Map)
        .cast<String, dynamic>();

void main() {
  group('normalizeEmojiInput (pure)', () {
    test('one grapheme in, one grapheme out — ZWJ sequences included', () {
      expect(normalizeEmojiInput('👍'), '👍');
      // Seven code points, 25 bytes, ONE grapheme: refusing it would be
      // refusing an emoji for being complicated.
      expect(normalizeEmojiInput('👨‍👩‍👧‍👦'), '👨‍👩‍👧‍👦');
      expect(normalizeEmojiInput('  ⭐  '), '⭐');
      expect(normalizeEmojiInput('🏷️'), '🏷️');
    });

    test('refuses anything longer than one grapheme, and emptiness', () {
      for (final input in ['👍👍', 'ab', '', '   ', '⭐🔥']) {
        expect(normalizeEmojiInput(input), isNull, reason: 'refuse "$input"');
      }
      // A single letter passes ON PURPOSE: the rule is "one grapheme"
      // (DESIGN §23 Q7), and deciding what counts as an emoji without a
      // package is guesswork that would reject real ones.
      expect(normalizeEmojiInput('A'), 'A');
    });
  });

  group('recents (pure)', () {
    test('most recent first, deduplicated, capped', () {
      var recents = <String>[];
      for (final emoji in ['⭐', '🔥', '⭐']) {
        recents = pushEmojiRecent(recents, emoji);
      }
      expect(recents, ['⭐', '🔥']);

      for (var i = 0; i < kQuickEmojiGrid.length; i++) {
        recents = pushEmojiRecent(recents, kQuickEmojiGrid[i]);
      }
      expect(recents, hasLength(kQuickEmojiRecentsLimit));
    });

    test('round-trips, and junk in storage is dropped rather than thrown', () {
      final recents = pushEmojiRecent(const ['🔥'], '⭐');
      expect(parseEmojiRecents(encodeEmojiRecents(recents)), ['⭐', '🔥']);
      expect(parseEmojiRecents(null), isEmpty);
      expect(parseEmojiRecents('abc,,👍,xy'), ['👍']);
    });
  });

  testWidgets('the emoji sheet sets one, remembers it, and can clear it', (
    tester,
  ) async {
    final api = FakeApi();
    final link = api.seedQuickLink(
      kind: 'url',
      url: 'https://x.dev',
      title: 'Site',
    );

    wide(tester);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    Future<void> openEmoji() async {
      await tester.tap(find.byKey(Key('quick-menu-${link['id']}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Emoji'));
      await tester.pumpAndSettle();
    }

    await openEmoji();
    await tester.tap(find.byKey(const Key('quick-emoji-🚀')));
    await tester.pumpAndSettle();
    expect(lastPatch(api)['emoji'], '🚀');

    // It comes back as a recent the next time the sheet opens.
    await openEmoji();
    expect(find.text('Recently used'), findsOneWidget);

    // Typing something that is not a single emoji is refused, not stored.
    await tester.enterText(find.byKey(const Key('quick-emoji-field')), 'ab');
    await tester.tap(find.byKey(const Key('quick-emoji-submit')));
    await tester.pumpAndSettle();
    expect(find.text('One emoji, please'), findsOneWidget);

    // Clearing returns the row to its kind icon.
    await tester.tap(find.byKey(const Key('quick-emoji-clear')));
    await tester.pumpAndSettle();
    expect(lastPatch(api)['emoji'], isNull);
  });

  testWidgets('colour lands in the store and never touches the title style', (
    tester,
  ) async {
    final api = FakeApi();
    final link = api.seedQuickLink(
      kind: 'url',
      url: 'https://x.dev',
      title: 'Site',
    );

    wide(tester);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('quick-menu-${link['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Color'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick-color-#F59E0B')));
    await tester.pumpAndSettle();

    expect(lastPatch(api)['colorRgb'], '#F59E0B');

    // DESIGN §23 Q8: the user's colour is an accent, so the title keeps its
    // normal role and the ≥4.5:1 floor never depends on user input. #F59E0B is
    // exactly the swatch that would fail as text (2.15:1 on white).
    final title = tester.widget<Text>(find.text('Site').first);
    final theme = Theme.of(tester.element(find.text('Site').first));
    expect(title.style?.color, theme.colorScheme.onSurface);
  });

  testWidgets('renaming to nothing falls back to the target, not to blank', (
    tester,
  ) async {
    final api = FakeApi();
    final project = api.seedProject(name: 'Ahmet Yılmaz');
    final link = api.seedQuickLink(
      kind: 'project',
      targetId: project['id'] as String,
      title: 'Kısayol',
    );

    wide(tester);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('quick-menu-${link['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quick-rename-field')), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(lastPatch(api)['title'], 'Ahmet Yılmaz');
  });

  testWidgets('a renamed target is offered, never forced, on the shortcut', (
    tester,
  ) async {
    final api = FakeApi();
    // The project has since been renamed; the shortcut kept the name the user
    // gave it and only SHOWS the difference (BLUEPRINT §4.12). (That the rail
    // re-renders live on a rename is the store test's job — here the point is
    // what the row does about it.)
    final project = api.seedProject(name: 'Ahmet Yılmaz');
    final link = api.seedQuickLink(
      kind: 'project',
      targetId: project['id'] as String,
      title: 'Ahmet',
    );

    wide(tester);
    await tester.pumpWidget(await signedInApp(api));
    await tester.pumpAndSettle();

    expect(find.text('Ahmet'), findsWidgets);
    expect(find.textContaining('Now: Ahmet Yılmaz'), findsOneWidget);

    await tester.tap(find.byKey(Key('quick-menu-${link['id']}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Use the source's name"));
    await tester.pumpAndSettle();
    expect(lastPatch(api)['title'], 'Ahmet Yılmaz');
  });
}
