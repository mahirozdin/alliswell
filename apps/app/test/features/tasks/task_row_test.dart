// OPH-400 (DESIGN §46, R-09 · T-02 · U-06 · U-12): the task row's anatomy.
//
// The row used to let a title run to five lines, centre the check circle on
// the whole card, and spend a quarter of the width on a right-hand column of
// flag + bell + hourglass that said "default" on almost every row. These tests
// measure the new shape instead of trusting it:
//
//   • title ≤ 2 lines + "…" (3 in the large-text layout), never broken inside
//     a word; a bare URL is one line, "host › path" behind a link glyph;
//   • the check circle and the one right-hand item sit on the FIRST line;
//   • one meta line, 13/18 tabular: date · repeat · alarm · priority · first
//     tag +N — and only what differs from the defaults (open, medium,
//     urgent-armed) earns a glyph;
//   • "Overdue" is the red word, the date beside it stays neutral;
//   • above 1.3× text the row goes vertical: title full width, meta under it.
//
// The geometry matrix runs with the test font; the 2.0× word-break check loads
// the repo's real Roboto/DejaVu, because the test font's square glyphs make
// every 9-letter Turkish word wider than a 2.0× line and would prove nothing.
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
const bool _shots = bool.fromEnvironment('screenshots');

final _now = DateTime.now();
final _past = DateTime(
  _now.year,
  _now.month,
  _now.day,
).subtract(const Duration(days: 2, hours: -9));
final _future = DateTime(
  _now.year,
  _now.month,
  _now.day,
).add(const Duration(days: 3, hours: 14, minutes: 30));

Task _task(
  String id,
  String title, {
  String status = 'open',
  String priority = 'medium',
  bool urgent = true,
  DateTime? due,
  String? projectId,
  List<String> tagIds = const [],
  String? seriesId,
  DateTime? mutedAt,
}) => Task(
  id: id,
  workspaceId: 'W1',
  title: title,
  status: status,
  priority: priority,
  timezone: 'Europe/Istanbul',
  isUrgent: urgent,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
  dueAt: due?.toUtc(),
  remindAt: due?.subtract(const Duration(hours: 1)).toUtc(),
  projectId: projectId,
  tagIds: tagIds,
  seriesId: seriesId,
  occurrenceDate: seriesId == null ? null : '2030-01-01',
  alarmsMutedAt: mutedAt?.toUtc(),
);

const _project = Project(
  id: 'P1',
  workspaceId: 'W1',
  name: 'Ev tadilatı',
  colorRgb: '#16A34A',
  status: 'active',
  sortOrder: 0,
  isFavorite: false,
  revision: 1,
);

const _tags = {
  'G1': Tag(id: 'G1', name: 'ev', slug: 'ev', colorRgb: '#2563EB'),
  'G2': Tag(id: 'G2', name: 'acil', slug: 'acil', colorRgb: '#DC2626'),
  'G3': Tag(id: 'G3', name: 'usta', slug: 'usta', colorRgb: '#7C3AED'),
};

String _longTitle(String language) => language == 'tr'
    ? 'Pazartesi sabahki müşteri toplantısından önce bütçe sunumunun son '
          'halini ekiple birlikte gözden geçir ve onaya gönder'
    : 'Review the final version of the budget presentation with the team '
          'before Monday morning’s client meeting and send it for approval';

/// The rows every case renders: the long title, the default-everything row,
/// the deviations, an overdue row, a bare URL and a three-tag row.
List<Task> _rows(String language) => [
  _task('long', _longTitle(language), due: _future, projectId: 'P1'),
  _task('plain', language == 'tr' ? 'Süt al' : 'Buy milk', due: _future),
  _task(
    'odd',
    language == 'tr' ? 'Faturayı öde' : 'Pay the bill',
    status: 'in_progress',
    priority: 'high',
    urgent: false,
    due: _future,
    seriesId: 'S1',
  ),
  _task(
    'late',
    language == 'tr' ? 'Kira' : 'Rent',
    due: _past,
    projectId: 'P1',
  ),
  _task(
    'url',
    'https://github.com/alliswell/app/issues/412?tab=comments',
    priority: 'none',
    urgent: false,
  ),
  _task(
    'tags',
    language == 'tr' ? 'Ustayı ara' : 'Call the plumber',
    tagIds: const ['G1', 'G2', 'G3'],
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  required List<Task> tasks,
  double width = 393,
  double height = 1400,
  double scale = 1.0,
  Brightness brightness = Brightness.light,
  String? family,
  Map<String, Widget> trailing = const {},
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width, height);
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
        projectsByIdProvider.overrideWithValue(const {'P1': _project}),
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
              for (final task in tasks)
                TaskTile(
                  key: ValueKey('row-${task.id}'),
                  task: task,
                  trailingAction: trailing[task.id],
                ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _row(String id) => find.byKey(ValueKey('row-$id'));
Finder _in(String id, Finder matching) =>
    find.descendant(of: _row(id), matching: matching);

RenderParagraph _titleParagraph(WidgetTester tester, String id) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byKey(Key('task-title-$id')),
        matching: find.byType(RichText),
      ),
    );

/// A [TextPainter] laid out exactly like [p], so its lines can be read.
TextPainter _painterLike(RenderParagraph p) => TextPainter(
  text: p.text,
  textDirection: p.textDirection,
  textScaler: p.textScaler,
  maxLines: p.maxLines,
  ellipsis: p.overflow == TextOverflow.ellipsis ? '…' : null,
  strutStyle: p.strutStyle,
  textWidthBasis: p.textWidthBasis,
  textHeightBehavior: p.textHeightBehavior,
)..layout(maxWidth: p.size.width);

/// The title's first line, in global coordinates.
Rect _firstLine(WidgetTester tester, String id) {
  final p = _titleParagraph(tester, id);
  final painter = _painterLike(p);
  final line = painter.computeLineMetrics().first;
  painter.dispose();
  final top = p.localToGlobal(Offset.zero);
  return Rect.fromLTWH(top.dx, top.dy, p.size.width, line.height);
}

int _titleLines(WidgetTester tester, String id) {
  final painter = _painterLike(_titleParagraph(tester, id));
  final lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}

/// Every place the title wraps must be a place a reader would break it: after
/// a space, a zero-width break the row put there on purpose, or a URL
/// separator. A break inside a word is the U-12 defect.
List<String> _midWordBreaks(WidgetTester tester, String id) {
  final p = _titleParagraph(tester, id);
  final text = p.text.toPlainText(includeSemanticsLabels: false);
  final painter = _painterLike(p);
  final lines = painter.computeLineMetrics();
  final bad = <String>[];
  // The last visible line ends where the ellipsis is — that is not a wrap.
  for (final line in lines.take(lines.length - 1)) {
    final end = painter
        .getLineBoundary(
          painter.getPositionForOffset(
            Offset(0, line.baseline - line.ascent / 2),
          ),
        )
        .end;
    if (end <= 0 || end >= text.length) continue;
    final before = text[end - 1];
    final after = text[end];
    final ok =
        RegExp(r'[\s​/?&=\-]').hasMatch(before) ||
        RegExp(r'\s').hasMatch(after);
    if (!ok) {
      bad.add(
        '${text.substring((end - 6).clamp(0, end), end)}|'
        '${text.substring(end, (end + 6).clamp(end, text.length))}',
      );
    }
  }
  painter.dispose();
  return bad;
}

Rect _rect(WidgetTester tester, Finder f) => tester.getRect(f);

void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));
  tearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));

  testWidgets('a long title stops at two lines; the check circle and the '
      'right item sit on the first line', (tester) async {
    await _pump(tester, tasks: _rows('en'), width: 375);

    expect(_titleLines(tester, 'long'), 2);
    expect(_titleParagraph(tester, 'long').didExceedMaxLines, isTrue);

    final line = _firstLine(tester, 'long');
    final check = tester.getCenter(_in('long', find.byType(Checkbox)));
    expect((check.dy - line.center.dy).abs(), lessThanOrEqualTo(1.5));

    final right = _rect(tester, find.byKey(const Key('task-right-long')));
    expect((right.center.dy - line.center.dy).abs(), lessThanOrEqualTo(1.5));
    // One item on the right, and it is narrow. (The test font draws every
    // glyph a full em wide, so the 6-letter badge is ~93 pt here; with Roboto
    // it is ~60, under R-09's 15 %.)
    final card = _rect(tester, _in('long', find.byType(Card)));
    expect(right.width, lessThanOrEqualTo(card.width * 0.3));
    expect(_in('long', find.byType(ProjectBadge)), findsOneWidget);
  });

  testWidgets('defaults earn no glyph: open, medium, urgent-armed', (
    tester,
  ) async {
    await _pump(tester, tasks: _rows('en'));

    expect(_in('plain', find.byIcon(Icons.hourglass_empty)), findsNothing);
    expect(_in('plain', find.byIcon(Icons.flag)), findsNothing);
    expect(
      _in('plain', find.byIcon(Icons.notification_important)),
      findsNothing,
    );
    expect(find.byKey(const Key('task-alarm-plain')), findsNothing);
    expect(find.byKey(const Key('task-status-plain')), findsNothing);
    expect(find.byKey(const Key('task-priority-plain')), findsNothing);
    // Nothing on the right of a row without a project either.
    expect(find.byKey(const Key('task-right-plain')), findsNothing);
  });

  testWidgets('deviations are glyphs on the one meta line, in order: '
      'date · repeat · alarm · status · priority', (tester) async {
    // Wide enough for all five in the test font's em-wide glyphs.
    await _pump(tester, tasks: _rows('en'), width: 700);

    final meta = find.byKey(const Key('task-meta-odd'));
    final keys = [
      'task-due-odd',
      'repeat-badge-odd',
      'task-alarm-odd',
      'task-status-odd',
      'task-priority-odd',
    ];
    final rects = [
      for (final key in keys)
        _rect(
          tester,
          find.descendant(of: meta, matching: find.byKey(Key(key))),
        ),
    ];
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].left, greaterThan(rects[i - 1].right), reason: keys[i]);
      expect(
        (rects[i].center.dy - rects[0].center.dy).abs(),
        lessThanOrEqualTo(1),
        reason: '${keys[i]} is on the same line',
      );
    }
    // Not urgent = a plain bell; in progress = its own glyph, high = a flag.
    expect(
      find.descendant(
        of: find.byKey(const Key('task-alarm-odd')),
        matching: find.byIcon(Icons.notifications_none),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('task-status-odd')),
        matching: find.byIcon(Icons.timelapse),
      ),
      findsOneWidget,
    );
    // The meta line is ONE line of 13/18 text: no taller than its glyphs.
    expect(_rect(tester, meta).height, lessThanOrEqualTo(18));
    // Nothing is left on the right of the row.
    expect(find.byKey(const Key('task-right-odd')), findsNothing);
  });

  testWidgets('"Overdue" is the red word; the date beside it stays neutral', (
    tester,
  ) async {
    AwI18n.instance.setActiveCached(const Locale('tr'));
    await _pump(tester, tasks: _rows('tr'));

    final scheme = Theme.of(tester.element(_row('late'))).colorScheme;
    final text = tester.widget<Text>(find.byKey(const Key('task-due-late')));
    final spans = <TextSpan>[];
    text.textSpan!.visitChildren((span) {
      if (span is TextSpan && (span.text ?? '').trim().isNotEmpty) {
        spans.add(span);
      }
      return true;
    });
    final word = spans.firstWhere((s) => s.text == 'Gecikti');
    expect(word.style?.color, scheme.error);
    final date = spans.lastWhere((s) => s != word);
    expect(date.style?.color, isNot(scheme.error));
    expect(date.style?.color, scheme.onSurfaceVariant);
    expect(
      text.textSpan!.toPlainText(),
      startsWith('Gecikti '),
      reason: 'G5: the word is there, not just the colour',
    );
  });

  testWidgets('first tag + N; a bare URL is one "host › path" line behind a '
      'link glyph', (tester) async {
    await _pump(tester, tasks: _rows('en'));

    expect(_in('tags', find.text('#ev')), findsOneWidget);
    expect(_in('tags', find.text('#acil')), findsNothing);
    expect(_in('tags', find.text('+2')), findsOneWidget);

    expect(_titleLines(tester, 'url'), 1);
    expect(
      _titleParagraph(tester, 'url').text.toPlainText(),
      contains('github.com › alliswell/app/issues/412'),
    );
    expect(find.byKey(const Key('task-link-url')), findsOneWidget);
    // The whole URL is still what the check circle names.
    final checkbox = tester.widget<Checkbox>(_in('url', find.byType(Checkbox)));
    expect(checkbox.semanticLabel, contains('github.com/alliswell'));
  });

  testWidgets('a screen action takes the right slot; the project moves into '
      'the meta line as a dot and its name', (tester) async {
    await _pump(
      tester,
      tasks: _rows('en'),
      trailing: {
        'long': IconButton(
          key: const Key('reopen-long'),
          onPressed: () {},
          icon: const Icon(Icons.replay, size: 18),
        ),
      },
    );
    final right = find.byKey(const Key('task-right-long'));
    expect(
      find.descendant(
        of: right,
        matching: find.byKey(const Key('reopen-long')),
      ),
      findsOneWidget,
    );
    expect(_in('long', find.byType(ProjectBadge)), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('task-meta-long')),
        matching: find.byKey(const Key('task-project-long')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a meta line that does not fit drops items from its end, never '
      'wraps and never overflows', (tester) async {
    final crowded = _task(
      'crowd',
      'Kısa',
      status: 'waiting',
      priority: 'urgent',
      urgent: false,
      due: _past,
      seriesId: 'S1',
      tagIds: const ['G1', 'G2'],
    );
    await _pump(tester, tasks: [crowded], width: 240);
    expect(tester.takeException(), isNull);
    final meta = _rect(tester, find.byKey(const Key('task-meta-crowd')));
    expect(meta.height, lessThanOrEqualTo(18));
    // The date is first and is always shown.
    expect(
      tester.getRect(find.byKey(const Key('task-due-crowd'))).right,
      lessThanOrEqualTo(meta.right + 0.5),
    );
  });

  testWidgets('matrix: 360/375/393/430 × 1.0/1.3 × TR/EN × light/dark — '
      'horizontal anatomy holds, nothing overflows', (tester) async {
    for (final language in ['tr', 'en']) {
      AwI18n.instance.setActiveCached(Locale(language));
      for (final brightness in Brightness.values) {
        for (final width in [360.0, 375.0, 393.0, 430.0]) {
          for (final scale in [1.0, 1.3]) {
            final label = '$language $brightness $width × $scale';
            await _pump(
              tester,
              tasks: _rows(language),
              width: width,
              scale: scale,
              brightness: brightness,
            );
            expect(tester.takeException(), isNull, reason: label);
            for (final task in _rows(language)) {
              final id = task.id;
              expect(
                _titleLines(tester, id),
                lessThanOrEqualTo(2),
                reason: '$label $id',
              );
              final line = _firstLine(tester, id);
              final check = tester.getCenter(_in(id, find.byType(Checkbox)));
              expect(
                (check.dy - line.center.dy).abs(),
                lessThanOrEqualTo(1.5),
                reason: '$label $id: check on the first line',
              );
              final meta = find.byKey(Key('task-meta-$id'));
              if (meta.evaluate().isNotEmpty) {
                expect(
                  _rect(tester, meta).height,
                  lessThanOrEqualTo(18 * scale + 0.5),
                  reason: '$label $id: one meta line',
                );
                expect(
                  _rect(tester, meta).top,
                  greaterThanOrEqualTo(
                    _rect(tester, find.byKey(Key('task-title-$id'))).bottom,
                  ),
                  reason: '$label $id: meta under the title',
                );
              }
            }
          }
        }
      }
    }
  });

  testWidgets('above 1.3× the row goes vertical: title full width, meta and '
      'project under it', (tester) async {
    await _pump(tester, tasks: _rows('en'), width: 375, scale: 1.6);
    expect(tester.takeException(), isNull);

    final title = _rect(tester, find.byKey(const Key('task-title-long')));
    final card = _rect(tester, _in('long', find.byType(Card)));
    expect(_titleLines(tester, 'long'), lessThanOrEqualTo(3));
    // Full width: the title runs to the card's inner edge (12 pt padding).
    expect(card.right - title.right, lessThanOrEqualTo(AwSpace.x3 + 0.5));
    final meta = _rect(tester, find.byKey(const Key('task-meta-long')));
    expect(meta.top, greaterThanOrEqualTo(title.bottom));
    final right = _rect(tester, find.byKey(const Key('task-right-long')));
    expect(right.top, greaterThanOrEqualTo(title.bottom));
  });

  group('2.0× with real glyphs', () {
    setUpAll(loadRealFontsForStore);

    testWidgets('360/375/393/430 × TR/EN: never a mid-word break, ≤ 3 '
        'title lines, the card ≤ 240 pt', (tester) async {
      for (final language in ['tr', 'en']) {
        AwI18n.instance.setActiveCached(Locale(language));
        for (final width in [360.0, 375.0, 393.0, 430.0]) {
          final label = '$language $width × 2.0';
          await _pump(
            tester,
            tasks: _rows(language),
            width: width,
            height: 3000,
            scale: 2.0,
            family: _family,
          );
          expect(tester.takeException(), isNull, reason: label);
          for (final task in _rows(language)) {
            final id = task.id;
            expect(
              _midWordBreaks(tester, id),
              isEmpty,
              reason: '$label $id: "${task.title}"',
            );
            expect(_titleLines(tester, id), lessThanOrEqualTo(3));
            final check = tester.getCenter(_in(id, find.byType(Checkbox)));
            final line = _firstLine(tester, id);
            expect(
              (check.dy - line.center.dy).abs(),
              lessThanOrEqualTo(1.5),
              reason: '$label $id: check on the first line',
            );
          }
          expect(
            _rect(tester, _in('long', find.byType(Card))).height,
            lessThanOrEqualTo(240),
            reason: label,
          );
        }
      }
    });

    testWidgets('E35 G-B review r1: a silenced alarm stays on a narrow row — '
        'its glyph and its way back are never dropped', (tester) async {
      // 360 pt, 1.0×, real glyphs, a date and a project on the right: the
      // full "Turn alarms back on" no longer fits after the date. A muted row must still not look
      // like an armed one (§11 A5), so the item shortens instead of vanishing.
      for (final language in ['en', 'tr']) {
        AwI18n.instance.setActiveCached(Locale(language));
        for (final due in [_future, _past]) {
          final muted = _task(
            'muted',
            language == 'tr' ? 'Faturayı öde' : 'Pay the bill',
            due: due,
            projectId: 'P1',
            mutedAt: _now,
          );
          await _pump(tester, tasks: [muted], width: 360, family: _family);
          final label = '$language $due';
          expect(tester.takeException(), isNull, reason: label);
          final meta = _rect(tester, find.byKey(const Key('task-meta-muted')));
          expect(meta.height, lessThanOrEqualTo(18.5), reason: label);
          final glyph = _in('muted', find.byIcon(Icons.notifications_off));
          expect(glyph.hitTestable(), findsOneWidget, reason: label);
          expect(
            _rect(tester, glyph).right,
            lessThanOrEqualTo(meta.right + 0.5),
            reason: label,
          );
          final unmute = find.byKey(const Key('unmute-muted'));
          expect(unmute.hitTestable(), findsOneWidget, reason: label);
          expect(
            _rect(tester, unmute).right,
            lessThanOrEqualTo(meta.right + 0.5),
            reason: label,
          );
        }
      }
    });

    // The picture for a human (docs/DESIGN.md §5): the rows at 1.0× and 2.0×,
    // light and dark. Generated output, not committed — run with
    // `--update-goldens --dart-define=screenshots=true`.
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'golden: phone rows ${brightness.name} ${scale}x',
          skip: !_shots,
          (tester) async {
            AwI18n.instance.setActiveCached(const Locale('tr'));
            await _pump(
              tester,
              tasks: _rows('tr'),
              width: 393,
              height: scale == 1.0 ? 760 : 1700,
              scale: scale,
              brightness: brightness,
              family: _family,
            );
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                '../../goldens/phone_task_rows_${brightness.name}_'
                '${scale == 1.0 ? '1x' : '2x'}.png',
              ),
            );
          },
        );
      }
    }
  });
}
