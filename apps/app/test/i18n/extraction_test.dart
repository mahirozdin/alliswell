import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sections.dart';
import 'package:alliswell/src/widgets/status_views.dart';

/// OPH-122 — the extracted chrome strings (nav, shared states) actually localize:
/// English by default, Turkish when the locale flips. Proves `.tr()` is wired,
/// not just that English still renders. Reset to en before each test (shared
/// singleton).
void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  group('AppSection labels', () {
    test('resolve in English by default', () {
      expect(AppSection.home.title, 'Home');
      expect(AppSection.projects.title, 'Projects');
      expect(AppSection.inbox.description, contains('Capture'));
    });

    test('follow the active language', () {
      AwI18n.instance.setActiveCached(const Locale('tr'));
      expect(AppSection.home.title, 'Ana Sayfa');
      expect(AppSection.projects.title, 'Projeler');
      expect(AppSection.inbox.description, contains('yakala'));
    });
  });

  group('shared error state', () {
    testWidgets('renders English by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AwErrorState(message: 'boom')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('renders Turkish when the locale is tr', (tester) async {
      AwI18n.instance.setActiveCached(const Locale('tr'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AwErrorState(message: 'boom', onRetry: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bir şeyler ters gitti'), findsOneWidget);
      expect(find.text('Tekrar dene'), findsOneWidget);
    });
  });
}
