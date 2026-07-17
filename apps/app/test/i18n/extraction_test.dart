import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/core/error_messages.dart';
import 'package:alliswell/src/features/home/task_grouping.dart';
import 'package:alliswell/src/features/onboarding/tour.dart';
import 'package:alliswell/src/features/tasks/ui/task_visuals.dart';
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

  group('task surface (OPH-123)', () {
    test('Home bucket labels localize', () {
      expect(HomeBucket.overdue.label, 'Overdue');
      expect(HomeBucket.next30Days.label, 'Next 30 days');
      AwI18n.instance.setActiveCached(const Locale('tr'));
      expect(HomeBucket.overdue.label, 'Geciken');
      expect(HomeBucket.noDate.label, 'Tarihsiz');
    });

    test('status + priority names localize', () {
      expect(taskStatusLabel('open'), 'Open');
      expect(taskStatusLabel('in_progress'), 'In progress');
      expect(taskPriorityLabel('high'), 'High');
      AwI18n.instance.setActiveCached(const Locale('tr'));
      expect(taskStatusLabel('open'), 'Açık');
      expect(taskPriorityLabel('urgent'), 'Acil');
    });
  });

  group('feature strings (OPH-124)', () {
    test('onboarding tour steps localize', () {
      expect(kTourSteps.first.title, 'Welcome to AllisWell');
      expect(kTourSteps[1].title, 'Home');
      AwI18n.instance.setActiveCached(const Locale('tr'));
      expect(kTourSteps.first.title, "AllisWell'e hoş geldin");
      expect(kTourSteps.last.title, 'Hazırsın');
    });

    test('project / note / calendar keys resolve in both languages', () {
      expect('project.archive'.tr(), 'Archive');
      expect('note.pin'.tr(), 'Pin');
      expect('calendar.connect'.tr(), 'Connect');
      AwI18n.instance.setActiveCached(const Locale('tr'));
      expect('project.archive'.tr(), 'Arşivle');
      expect('note.pin'.tr(), 'Sabitle');
      expect('calendar.connect'.tr(), 'Bağlan');
    });

    test('args fill placeholders (project.deleteBody)', () {
      expect(
        'project.deleteBody'.tr(args: {'name': 'Netgross'}),
        '"Netgross" will be removed. Its tasks stay in the workspace.',
      );
    });
  });

  group('error messages (OPH-125)', () {
    test('maps an ApiException code to a localized message', () {
      expect(
        localizedError(const ApiException('NETWORK_ERROR', 'raw')),
        contains('Could not reach'),
      );
      AwI18n.instance.setActiveCached(const Locale('tr'));
      expect(
        localizedError(const ApiException('NETWORK_ERROR', 'raw')),
        contains('ulaşılamadı'),
      );
    });

    test('falls back to the server message for an untranslated code', () {
      expect(
        localizedError(const ApiException('WEIRD_CODE', 'Server said no')),
        'Server said no',
      );
    });

    test('a non-ApiException resolves to the generic message', () {
      expect(
        localizedError(Exception('boom')),
        'Something went wrong. Please try again.',
      );
    });
  });
}
