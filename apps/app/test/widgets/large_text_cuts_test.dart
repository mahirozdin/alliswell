// OPH-400 polish 4 (T-06): what 2.0× text still cut short.
//
// `.ceo/shots3/web` 13, 15, 31, 100 and 101 at 2.0× showed:
// - a subtask's date ending in "Son tarih 14 Kas, 12:…" (the date never
//   wrapped, even in the large-text row that wraps everything else);
// - the Settings address split at the dot, "demo@alliswell / .space";
// - the task detail's Öncelik value drawn visibly smaller than Durum's
//   (the half-width field scaled "Yüksek" down to fit);
// - the unit name under the phone's title cut to "Demir Çelik Fabri…";
// - a request's subject in the list cut after two lines.
//
// Measured with the repo's real Roboto/DejaVu where widths matter: the test
// font's square glyphs make every Turkish word wider than a phone line.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/team_origin.dart';
import 'package:alliswell/src/features/ee/ticket_work_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/features/ee/ui/ticket_queue_screen.dart';
import 'package:alliswell/src/features/ee/unit_scope_providers.dart';
import 'package:alliswell/src/features/projects/providers.dart';
import 'package:alliswell/src/features/tags/tags.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/ui/task_detail_screen.dart';
import 'package:alliswell/src/features/tasks/ui/task_tile.dart';
import 'package:alliswell/src/features/tasks/ui/task_visuals.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/screens/home_shell.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/word_safe_text.dart';

import '../design_screenshots_test.dart' show loadRealFontsForStore;
import '../features/projects/fake_api.dart';
import '../features/tasks/tasks_flow_test.dart' show signedInAppWith;

const _family = 'ScreenshotSans';
const _phone = Size(393, 852);

void _surface(WidgetTester tester, double scale, {Size size = _phone}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

List<RenderParagraph> _paragraphsIn(WidgetTester tester, Finder of) => [
  for (final e
      in find.descendant(of: of, matching: find.byType(RichText)).evaluate())
    e.renderObject! as RenderParagraph,
];

/// The lines [p] is drawn in, as text.
List<String> _lines(RenderParagraph p) {
  final text = p.text.toPlainText(includeSemanticsLabels: false);
  final painter = TextPainter(
    text: p.text,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    maxLines: p.maxLines,
    ellipsis: p.overflow == TextOverflow.ellipsis ? '…' : null,
  )..layout(maxWidth: p.constraints.maxWidth);
  final out = <String>[];
  for (final line in painter.computeLineMetrics()) {
    final range = painter.getLineBoundary(
      painter.getPositionForOffset(Offset(1, line.baseline - line.ascent / 2)),
    );
    out.add(text.substring(range.start, range.end));
  }
  painter.dispose();
  return out;
}

/// No word of [p] is wider than the paragraph (so none is broken inside).
bool _wordsFit(RenderParagraph p) {
  final words = p.text
      .toPlainText(includeSemanticsLabels: false)
      .split(RegExp('[\\s$kAwZwsp]+'))
      .where((w) => w.isNotEmpty);
  return words.every(
    (w) =>
        (TextPainter(
          text: TextSpan(text: w, style: p.text.style),
          textDirection: p.textDirection,
          textScaler: p.textScaler,
        )..layout()).width <=
        p.size.width + 0.5,
  );
}

Task _subtask(String id, DateTime due) => Task(
  id: id,
  workspaceId: 'W1',
  title: 'Send the pre-read',
  status: 'open',
  priority: 'medium',
  timezone: 'Europe/Istanbul',
  isUrgent: false,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
  dueAt: due.toUtc(),
  remindAt: due.subtract(const Duration(hours: 1)).toUtc(),
  parentTaskId: 'PARENT',
);

TicketRecord _ticket(String id, int number, String subject) => TicketRecord(
  id: id,
  workspaceId: 'W1',
  number: number,
  subject: subject,
  status: 'new',
  priority: 'normal',
  source: 'internal',
  revision: 1,
  createdAt: DateTime.utc(2026, 11, 2),
);

WorkspaceSummary _ws(String id, String name) => WorkspaceSummary(
  id: id,
  name: name,
  slug: id.toLowerCase(),
  colorRgb: '#2563EB',
  icon: null,
  role: 'member',
);

class _FixedSelection extends SelectedWorkspace {
  _FixedSelection(this._value);
  final String _value;
  @override
  String? build() => _value;
}

void main() {
  setUpAll(loadRealFontsForStore);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });
  tearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));

  group('the account address breaks after "@" only', () {
    test('the domain stays one piece', () {
      expect(
        awBreakableAddress('demo@alliswell.space'),
        'demo@${kAwZwsp}alliswell.space',
      );
      expect(awBreakableAddress('a.b@c.d.e'), 'a.b@${kAwZwsp}c.d.e');
      expect(awBreakableAddress('nobody'), 'nobody');
    });

    for (final scale in [2.0, 2.35]) {
      testWidgets('$scale×: "demo@" / "alliswell.space", never "/ .space"', (
        tester,
      ) async {
        _surface(tester, scale);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAwTheme(Brightness.dark, fontFamilyOverride: _family),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  // The Settings row's subtitle slot on a 393 pt phone.
                  width: 230,
                  child: AwWordSafeText(
                    awBreakableAddress('demo@alliswell.space'),
                    key: const Key('t'),
                  ),
                ),
              ),
            ),
          ),
        );
        final p = _paragraphsIn(tester, find.byKey(const Key('t'))).single;
        final lines = _lines(p).map((l) => l.replaceAll(kAwZwsp, '')).toList();
        expect(lines, ['demo@', 'alliswell.space'], reason: '$lines');
      });
    }
  });

  group('a subtask\'s date at large text', () {
    for (final scale in [2.0, 2.35]) {
      testWidgets('$scale×: the date wraps between words, never "12:…"', (
        tester,
      ) async {
        _surface(tester, scale, size: const Size(393, 1600));
        final due = DateTime(2026, 11, 14, 12, 30);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              projectsByIdProvider.overrideWithValue(const {}),
              tagsByIdProvider.overrideWithValue(const {}),
              unitLabelsProvider.overrideWithValue(const {}),
              workspaceAssigneesProvider.overrideWith(
                (ref) => Stream.value({}),
              ),
              workTicketsByTaskProvider.overrideWith((ref) => Stream.value({})),
            ],
            child: MaterialApp(
              theme: buildAwTheme(Brightness.dark, fontFamilyOverride: _family),
              home: Scaffold(
                body: ListView(
                  // The detail's section card inside the page's gutter.
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  children: [
                    TaskTile(
                      task: _subtask('S1', due),
                      showProjectBadge: false,
                      swipeToDelete: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final p = _paragraphsIn(
          tester,
          find.byKey(const Key('task-due-S1')),
        ).single;
        final text = p.text.toPlainText(includeSemanticsLabels: false);
        expect(text, contains('12:30'));
        expect(p.didExceedMaxLines, isFalse, reason: _lines(p).join(' | '));
        expect(_wordsFit(p), isTrue, reason: _lines(p).join(' | '));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('1.0×: the row keeps its one-line date', (tester) async {
      _surface(tester, 1.0);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectsByIdProvider.overrideWithValue(const {}),
            tagsByIdProvider.overrideWithValue(const {}),
            unitLabelsProvider.overrideWithValue(const {}),
            workspaceAssigneesProvider.overrideWith((ref) => Stream.value({})),
            workTicketsByTaskProvider.overrideWith((ref) => Stream.value({})),
          ],
          child: MaterialApp(
            theme: buildAwTheme(Brightness.dark, fontFamilyOverride: _family),
            home: Scaffold(
              body: ListView(
                children: [
                  TaskTile(
                    task: _subtask('S1', DateTime(2026, 11, 14, 12, 30)),
                    showProjectBadge: false,
                    swipeToDelete: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final p = _paragraphsIn(
        tester,
        find.byKey(const Key('task-due-S1')),
      ).single;
      expect(p.maxLines, 1);
    });
  });

  group('the detail\'s Durum and Öncelik at large text', () {
    void coldStartAt(WidgetTester tester, String location) {
      tester.binding.platformDispatcher.defaultRouteNameTestValue = location;
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
    }

    double drawnHeight(WidgetTester tester, String field, String label) {
      final text = find.descendant(
        of: find.byKey(Key(field)),
        matching: find.text(label),
      );
      return tester.getRect(text.first).height;
    }

    for (final scale in [2.0, 2.35]) {
      testWidgets('$scale×: "Yüksek" is drawn as large as "Açık"', (
        tester,
      ) async {
        _surface(tester, scale);
        final api = FakeApi();
        final task = api.seedTask(title: 'Pay the rent', priority: 'high');
        coldStartAt(tester, '/tasks/${task['id']}');
        await tester.pumpWidget(await signedInAppWith(api));
        await tester.pumpAndSettle();
        expect(find.byType(TaskDetailScreen), findsOneWidget);
        AwI18n.instance.setActiveCached(const Locale('tr'));
        await tester.pumpAndSettle();
        final status = drawnHeight(
          tester,
          'status-dropdown',
          taskStatusLabel('open'),
        );
        final priority = drawnHeight(
          tester,
          'priority-dropdown',
          taskPriorityLabel('high'),
        );
        expect(priority, closeTo(status, 0.5), reason: '$priority vs $status');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('1.0×: the two fields stay side by side', (tester) async {
      _surface(tester, 1.0);
      final api = FakeApi();
      final task = api.seedTask(title: 'Pay the rent', priority: 'high');
      coldStartAt(tester, '/tasks/${task['id']}');
      await tester.pumpWidget(await signedInAppWith(api));
      await tester.pumpAndSettle();
      final status = tester.getRect(find.byKey(const Key('status-dropdown')));
      final priority = tester.getRect(
        find.byKey(const Key('priority-dropdown')),
      );
      expect(priority.top, closeTo(status.top, 1));
      expect(priority.left, greaterThan(status.right));
    });
  });

  group('the unit\'s name under the phone\'s title', () {
    const name = 'Demir Çelik Fabrikası Bakım';
    final units = [_ws('01WSA', name), _ws('01WSB', 'Saha Servis')];

    Future<void> pumpBar(WidgetTester tester, double scale) async {
      _surface(tester, scale);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserIdProvider.overrideWithValue('01USERAAAAAAAAAAAAAAAAAA'),
            workspacesProvider.overrideWith((ref) async => units),
            selectedWorkspaceIdProvider.overrideWith(
              () => _FixedSelection('01WSA'),
            ),
            teamIdentityProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            theme: buildAwTheme(Brightness.light, fontFamilyOverride: _family),
            home: Builder(
              builder: (context) => Scaffold(
                appBar: buildSectionAppBar(
                  context,
                  'Ana Sayfa',
                  // Home's three targets: ⚡, View ⌄, Settings (+ this one).
                  trailingActions: [
                    IconButton(onPressed: () {}, icon: const Icon(Icons.bolt)),
                    IconButton(onPressed: () {}, icon: const Icon(Icons.dns)),
                  ],
                ),
                body: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final scale in [2.0, 2.35]) {
      testWidgets('$scale×: the name wraps onto a second line, never "…"', (
        tester,
      ) async {
        await pumpBar(tester, scale);
        expect(tester.takeException(), isNull);
        final switcher = find.byKey(const Key('workspace-switcher'));
        final p = _paragraphsIn(
          tester,
          switcher,
        ).firstWhere((p) => p.text.toPlainText().contains('Demir'));
        expect(p.didExceedMaxLines, isFalse, reason: _lines(p).join(' | '));
        expect(_wordsFit(p), isTrue, reason: _lines(p).join(' | '));
        // Drawn inside the bar, not under it.
        final bar = tester.getRect(find.byType(AppBar));
        final bottom = p.localToGlobal(Offset(0, p.size.height)).dy;
        expect(bottom, lessThanOrEqualTo(bar.bottom + 0.5));
        // The heading is whole too.
        expect(find.text('Ana Sayfa'), findsOneWidget);
      });
    }

    testWidgets('1.0×: the bar keeps its height', (tester) async {
      await pumpBar(tester, 1.0);
      expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
    });
  });

  group('a request\'s subject in the list at large text', () {
    const subject =
        'Parti 24-118 flanşlarda ölçü sapması, kalite onayı bekliyor';

    for (final scale in [2.0, 2.35]) {
      testWidgets('$scale×: the subject reads whole', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              workspacesProvider.overrideWith((ref) async => const []),
              eeMyUnitsScopeProvider.overrideWith((ref) async => null),
              ticketQueueProvider.overrideWith(
                (ref) => Stream.value([_ticket('T1', 206, subject)]),
              ),
              ticketAssigneesProvider.overrideWith(
                (ref) => Stream.value(const <String, List<Assignee>>{}),
              ),
              currentUserIdProvider.overrideWithValue('01USERAAAAAAAAAAAAAAAA'),
              canProvider.overrideWith((ref, permission) => false),
            ],
            child: MaterialApp(
              theme: buildAwTheme(
                Brightness.light,
                fontFamilyOverride: _family,
              ),
              home: const EeTicketQueueScreen(),
            ),
          ),
        );
        _surface(tester, scale, size: const Size(393, 1600));
        await tester.pumpAndSettle();
        final card = find.byKey(const Key('ticket-T1'));
        expect(card, findsOneWidget);
        final p = _paragraphsIn(
          tester,
          card,
        ).firstWhere((p) => p.text.toPlainText().contains('#206'));
        expect(p.didExceedMaxLines, isFalse, reason: _lines(p).join(' | '));
      });
    }
  });
}
