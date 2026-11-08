// OPH-400 polish 3 (J-03, DESIGN §46 R6): a task row never cuts its project's
// name.
//
// The badge used to be the first six letters and "…" ("Launch…", "Home r…",
// "Person…") in a fixed right-hand strip. Now the badge stays only when the
// WHOLE name fits a compact pill; otherwise the full name moves to the meta
// line behind its colour dot, and wraps onto a line of its own (between words)
// rather than being cut or dropped. Neighbouring items stay ≥ 8 pt apart.
//
// Measured with the repo's real Roboto/DejaVu at 1.0× and AX3 (3.1×), and with
// the test font, on 360 and 393 pt, light and dark, TR and EN.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/ticket_work_providers.dart';
import 'package:alliswell/src/features/projects/data/project.dart';
import 'package:alliswell/src/features/projects/providers.dart';
import 'package:alliswell/src/features/projects/ui/project_badge.dart';
import 'package:alliswell/src/features/tags/tags.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/ui/task_tile.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/theme/tokens.dart';

import '../../design_screenshots_test.dart' show loadRealFontsForStore;

const _family = 'ScreenshotSans';

/// The seeded projects the judge saw cut (`.ceo/shots2` 20, 21, 82, Home).
const _names = [
  'Launch AllisWell',
  'Home renovation',
  'Personal',
  'Acme — retainer',
  'Design System',
  'Ev',
];

final _future = DateTime.now().add(const Duration(days: 3, hours: 2));

Project _project(int i) => Project(
  id: 'P$i',
  workspaceId: 'W1',
  name: _names[i],
  colorRgb: const [
    '#16A34A',
    '#2563EB',
    '#8B5CF6',
    '#DC2626',
    '#F59E0B',
  ][i % 5],
  status: 'active',
  sortOrder: i,
  isFavorite: false,
  revision: 1,
);

Task _task(int i, {bool withDate = true, bool tagged = false}) => Task(
  id: 't$i',
  workspaceId: 'W1',
  title: i.isEven ? 'Kısa iş' : 'Review the budget deck before the meeting',
  status: 'open',
  priority: 'medium',
  timezone: 'Europe/Istanbul',
  isUrgent: true,
  requiresAcknowledgement: false,
  sortOrder: i,
  revision: 1,
  dueAt: withDate ? _future.toUtc() : null,
  remindAt: withDate
      ? _future.subtract(const Duration(hours: 1)).toUtc()
      : null,
  projectId: 'P$i',
  tagIds: tagged ? const ['G1', 'G2'] : const [],
);

const _tags = {
  'G1': Tag(id: 'G1', name: 'ev', slug: 'ev', colorRgb: '#2563EB'),
  'G2': Tag(id: 'G2', name: 'acil', slug: 'acil', colorRgb: '#DC2626'),
};

List<Task> _rows() => [
  for (var i = 0; i < _names.length; i++)
    _task(i, withDate: i != 2, tagged: i == 1),
];

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required double scale,
  Brightness brightness = Brightness.light,
  String? family,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        projectsByIdProvider.overrideWithValue({
          for (var i = 0; i < _names.length; i++) 'P$i': _project(i),
        }),
        tagsByIdProvider.overrideWithValue(_tags),
        unitLabelsProvider.overrideWithValue(const {}),
        workspaceAssigneesProvider.overrideWith((ref) => Stream.value({})),
        workTicketsByTaskProvider.overrideWith((ref) => Stream.value({})),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAwTheme(brightness, fontFamilyOverride: family),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AwSpace.x4),
            children: [
              for (final task in _rows())
                TaskTile(key: ValueKey('row-${task.id}'), task: task),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _in(String id, Finder f) =>
    find.descendant(of: find.byKey(ValueKey('row-$id')), matching: f);

/// The paragraph that draws [name] inside row [id] — in the badge or in the
/// meta line — and checks it is whole: the exact name, nothing cut.
RenderParagraph _nameParagraph(WidgetTester tester, String id, String name) {
  final texts = _in(id, find.byType(RichText)).evaluate().where((e) {
    final plain = (e.widget as RichText).text.toPlainText(
      includeSemanticsLabels: false,
      includePlaceholders: false,
    );
    return plain.trim() == name;
  }).toList();
  expect(texts, hasLength(1), reason: '$id: "$name" drawn once, whole');
  return texts.single.renderObject! as RenderParagraph;
}

/// [breaks]: check every wrap falls between words. Off for the test font,
/// whose em-wide glyphs make "AllisWell" wider than a 3.1× line on their own.
void _expectWhole(WidgetTester tester, String label, {bool breaks = true}) {
  for (var i = 0; i < _names.length; i++) {
    final id = 't$i';
    final name = _names[i];
    final why = '$label $id "$name"';
    expect(_in(id, find.textContaining('…')), findsNothing, reason: why);
    final p = _nameParagraph(tester, id, name);
    expect(p.didExceedMaxLines, isFalse, reason: why);
    final painter = TextPainter(
      text: p.text,
      textDirection: p.textDirection,
      textScaler: p.textScaler,
    );
    // The colour dot is an 8 pt dot + 4 pt gap placeholder.
    final placeholders = <PlaceholderDimensions>[];
    p.text.visitChildren((span) {
      if (span is PlaceholderSpan) {
        placeholders.add(
          const PlaceholderDimensions(
            size: Size(12, 8),
            alignment: PlaceholderAlignment.middle,
          ),
        );
      }
      return true;
    });
    painter
      ..setPlaceholderDimensions(placeholders)
      ..layout(maxWidth: p.size.width);
    // Every line ends where a reader would break the name.
    final plain = p.text.toPlainText(includeSemanticsLabels: false);
    final lines = painter.computeLineMetrics();
    for (final line
        in breaks ? lines.take(lines.length - 1) : <LineMetrics>[]) {
      final end = painter
          .getLineBoundary(
            painter.getPositionForOffset(
              Offset(1, line.baseline - line.ascent / 2),
            ),
          )
          .end;
      if (end <= 0 || end >= plain.length) continue;
      expect(
        RegExp(r'\s').hasMatch(plain[end - 1]) ||
            RegExp(r'\s').hasMatch(plain[end]),
        isTrue,
        reason: '$why: broke inside a word at $end',
      );
    }
    painter.dispose();

    final card = tester.getRect(_in(id, find.byType(Card)));
    final rect = tester.getRect(find.byWidget(_richOf(tester, id, name)));
    expect(rect.left, greaterThanOrEqualTo(card.left - 0.5), reason: why);
    expect(rect.right, lessThanOrEqualTo(card.right + 0.5), reason: why);

    final badge = _in(id, find.byType(ProjectBadge));
    if (badge.evaluate().isNotEmpty) {
      // A badge only when the whole name fits a compact pill.
      expect(
        tester.getSize(badge).width,
        lessThanOrEqualTo(kAwProjectBadgeMaxWidth + 0.5),
        reason: why,
      );
    } else {
      expect(
        find.descendant(
          of: find.byKey(Key('task-meta-$id')),
          matching: find.byKey(Key('task-project-$id')),
        ),
        findsOneWidget,
        reason: '$why: the name moved to the meta line',
      );
    }

    // ≥ 8 pt between neighbouring meta items on the same line.
    final meta = find.byKey(Key('task-meta-$id'));
    if (meta.evaluate().isEmpty) continue;
    final render = tester.renderObject<RenderBox>(meta);
    final rects = <Rect>[];
    render.visitChildren((child) {
      final box = child as RenderBox;
      if (!box.hasSize || box.size.isEmpty) return;
      final data = box.parentData! as BoxParentData;
      rects.add(data.offset & box.size);
    });
    for (final a in rects) {
      for (final b in rects) {
        if (identical(a, b) || a.left >= b.left) continue;
        final sameLine = a.top < b.bottom && b.top < a.bottom;
        if (!sameLine) continue;
        expect(
          b.left - a.right,
          greaterThanOrEqualTo(8 - 0.5),
          reason: '$why: items closer than 8 pt',
        );
      }
    }
  }
}

RichText _richOf(WidgetTester tester, String id, String name) =>
    _in(id, find.byType(RichText))
            .evaluate()
            .firstWhere(
              (e) =>
                  (e.widget as RichText).text
                      .toPlainText(
                        includeSemanticsLabels: false,
                        includePlaceholders: false,
                      )
                      .trim() ==
                  name,
            )
            .widget
        as RichText;

void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));
  tearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));

  testWidgets('a short name keeps its badge on the right, whole', (
    tester,
  ) async {
    await _pump(tester, width: 393, scale: 1.0);
    expect(_in('t5', find.byType(ProjectBadge)), findsOneWidget);
    expect(_in('t5', find.text('Ev')), findsOneWidget);
    // A long name is never a badge with a cut label.
    expect(_in('t0', find.byType(ProjectBadge)), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('task-meta-t0')),
        matching: find.byKey(const Key('task-project-t0')),
      ),
      findsOneWidget,
    );
    _nameParagraph(tester, 't0', 'Launch AllisWell');
  });

  testWidgets('test font: every seeded name whole at 1.0×, 1.3× and 3.1×', (
    tester,
  ) async {
    for (final width in [360.0, 393.0]) {
      for (final scale in [1.0, 1.3, 3.1]) {
        await _pump(tester, width: width, scale: scale);
        final label = '$width × $scale';
        expect(tester.takeException(), isNull, reason: label);
        _expectWhole(tester, label, breaks: false);
      }
    }
  });

  group('real glyphs', () {
    setUpAll(loadRealFontsForStore);

    testWidgets('360/393 × 1.0/AX3 × TR/EN × light/dark: every seeded name '
        'whole, ≥ 8 pt apart, nothing off the card', (tester) async {
      for (final language in ['tr', 'en']) {
        AwI18n.instance.setActiveCached(Locale(language));
        for (final brightness in Brightness.values) {
          for (final width in [360.0, 393.0]) {
            for (final scale in [1.0, 3.1]) {
              await _pump(
                tester,
                width: width,
                scale: scale,
                brightness: brightness,
                family: _family,
              );
              final label = '$language ${brightness.name} $width × $scale';
              expect(tester.takeException(), isNull, reason: label);
              _expectWhole(tester, label);
            }
          }
        }
      }
    });
  });
}
