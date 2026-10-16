import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/day_boundary.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/quick_parse.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/tasks/data/quick_add_apply.dart';
import 'package:alliswell/src/features/tasks/data/task_when.dart';
import 'package:alliswell/src/features/tasks/ui/quick_add_text_controller.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// OPH-373: the quick-add bars read the text offline — chips, highlight,
/// undo, the help sheet — and the parse lands as a real task (tags resolved,
/// series started), on Home, in the Inbox and on a project's Tasks tab.

/// Friday 16 October 2026, 10:00 — the parser's "now" in every test here.
final _now = DateTime(2026, 10, 16, 10);

Future<Widget> _app(FakeApi api) async {
  SharedPreferences.setMockInitialValues({});
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
      nowProvider.overrideWithValue(() => _now),
    ],
    child: const AllisWellApp(),
  );
}

Future<void> _wide(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

DateTime _local(Object? iso) => DateTime.parse(iso as String).toLocal();

String _wall(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pump();
  // Let the chips row finish growing (AnimatedSize, AwMotion.base).
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _submit(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => localKv.remove('alliswell_default_task_time'));

  group('quickParseBody', () {
    AwQuickParse parse(String text) =>
        awParseQuickAdd(text, AwQuickParseOptions(now: _now));

    test('with defaults: medium + urgent alarm + reminder an hour before', () {
      final body = quickParseBody(parse("yarın 9'da kira"), withDefaults: true);
      expect(body['title'], 'kira');
      expect(body['priority'], 'medium');
      expect(body['isUrgent'], true);
      expect(_wall(_local(body['dueAt'])), '2026-10-17 09:00');
      expect(_wall(_local(body['remindAt'])), '2026-10-17 08:00');
    });

    test('a typed priority wins over the default', () {
      final body = quickParseBody(parse('p1 kira'), withDefaults: true);
      expect(body['priority'], 'high');
    });

    test('without defaults a deadline still arms its reminder (C2)', () {
      final body = quickParseBody(parse('yarın süt'), withDefaults: false);
      expect(body.containsKey('priority'), isFalse);
      expect(body.containsKey('isUrgent'), isFalse);
      expect(_wall(_local(body['remindAt'])), '2026-10-17 22:59');
    });

    test('when is stored as local midnight, and needs no deadline', () {
      final body = quickParseBody(
        parse('başla pazartesi rapor'),
        withDefaults: false,
      );
      expect(body['startAt'], awWhenIso(DateTime(2026, 10, 19)));
      expect(body.containsKey('dueAt'), isFalse);
    });

    test('a fallback deadline applies only when the text has none', () {
      final picked = DateTime(2026, 10, 20, 12);
      expect(
        _wall(
          _local(
            quickParseBody(
              parse('süt'),
              withDefaults: true,
              dueAt: picked,
            )['dueAt'],
          ),
        ),
        '2026-10-20 12:00',
      );
      expect(
        _wall(
          _local(
            quickParseBody(
              parse('yarın süt'),
              withDefaults: true,
              dueAt: picked,
            )['dueAt'],
          ),
        ),
        '2026-10-17 23:59',
      );
    });
  });

  testWidgets('Home: "Yarın 9\'da kira #ev p1" shows chips and saves without '
      'the date picker', (tester) async {
    await _wide(tester);
    final api = FakeApi();
    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();

    await _type(tester, 'home-quick-add', "Yarın 9'da kira #ev p1");
    expect(find.byKey(const Key('quick-add-token-due')), findsOneWidget);
    expect(find.byKey(const Key('quick-add-token-tag-0')), findsOneWidget);
    expect(find.byKey(const Key('quick-add-token-priority')), findsOneWidget);
    expect(find.text('#ev'), findsOneWidget);
    // The highlight: due, its time, the tag and the priority.
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('home-quick-add')),
        matching: find.byType(EditableText),
      ),
    );
    final controller = field.controller as QuickAddTextController;
    expect(controller.recognized, hasLength(4));

    await _submit(tester);
    expect(find.byType(DatePickerDialog), findsNothing);
    final task = api.tasks.single;
    expect(task['title'], 'kira');
    expect(_wall(_local(task['dueAt'])), '2026-10-17 09:00');
    expect(_wall(_local(task['remindAt'])), '2026-10-17 08:00');
    expect(task['priority'], 'high');
    expect(task['isUrgent'], true);
    expect(api.tags.single['name'], 'ev');
    expect(task['tagIds'], [api.tags.single['id']]);
    // The bar is clean for the next entry.
    expect(find.byKey(const Key('quick-add-token-due')), findsNothing);
    expect(controller.recognized, isEmpty);
  });

  testWidgets('✕ on the deadline chip keeps its words and brings the picker '
      'back', (tester) async {
    await _wide(tester);
    final api = FakeApi();
    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();

    await _type(tester, 'home-quick-add', "Yarın 9'da kira");
    // The chip's ✕ (tooltip "Keep as text") — its last icon.
    await tester.tap(
      find
          .descendant(
            of: find.byKey(const Key('quick-add-token-due')),
            matching: find.byType(Icon),
          )
          .last,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quick-add-token-due')), findsNothing);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // No date in the text any more → the round-14 deadline ask (C3).
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final task = api.tasks.single;
    expect(task['title'], "Yarın 9'da kira");
    expect(task['dueAt'], isNull);
  });

  testWidgets('Home: deadline and when from one line', (tester) async {
    await _wide(tester);
    final api = FakeApi();
    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();

    await _type(tester, 'home-quick-add', 'rapor başla pazartesi son cuma');
    expect(find.byKey(const Key('quick-add-token-when')), findsOneWidget);
    expect(find.byKey(const Key('quick-add-token-due')), findsOneWidget);
    await _submit(tester);

    final task = api.tasks.single;
    expect(task['title'], 'rapor');
    expect(task['startAt'], awWhenIso(DateTime(2026, 10, 19)));
    expect(_wall(_local(task['dueAt'])), '2026-10-16 23:59');
  });

  testWidgets('Home: a recurrence starts a series adopting the new task', (
    tester,
  ) async {
    await _wide(tester);
    final api = FakeApi();
    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();

    await _type(tester, 'home-quick-add', "her pazartesi 9'da spor #sağlık");
    expect(find.byKey(const Key('quick-add-token-repeat')), findsOneWidget);
    await _submit(tester);

    final task = api.tasks.single;
    expect(task['title'], 'spor');
    expect(_wall(_local(task['dueAt'])), '2026-10-19 09:00');

    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('home-quick-add'))),
      listen: false,
    );
    final db = container.read(databaseProvider);
    final series = await tester.runAsync(() => db.select(db.taskSeries).get());
    expect(series, hasLength(1));
    expect(series!.single.ruleJson, contains('"day":"MO"'));
    expect(
      _wall(series.single.anchorAt.toLocal()),
      '2026-10-19 09:00',
      reason: 'the occurrence takes its time of day from the anchor',
    );
    expect(series.single.templateJson, contains('"title":"spor"'));
    expect(series.single.templateJson, contains(api.tags.single['id']));
    // The series create crossed the wire with the task it adopts (OPH-208).
    final pushed = api.pushedMutations.singleWhere(
      (m) => m['entityType'] == 'task_series',
    );
    expect((pushed['patch'] as Map)['fromTaskId'], task['id']);
  });

  testWidgets('a typed tag reuses the existing one, fold-insensitively', (
    tester,
  ) async {
    await _wide(tester);
    final api = FakeApi()..seedTag(name: 'ev');
    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();

    await _type(tester, 'home-quick-add', 'yarın süpür #Ev');
    await _submit(tester);
    expect(api.tags, hasLength(1));
    expect(api.tasks.single['tagIds'], [api.tags.single['id']]);
  });

  testWidgets('Inbox: a dated capture is born open; a plain one stays inbox', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox').last);
    await tester.pumpAndSettle();

    await _type(tester, 'quick-add', 'yarın süt');
    await _submit(tester);
    await _type(tester, 'quick-add', 'ekmek');
    await _submit(tester);

    final dated = api.tasks.firstWhere((t) => t['title'] == 'süt');
    expect(dated['status'], 'open');
    expect(_wall(_local(dated['dueAt'])), '2026-10-17 23:59');
    expect(dated['isUrgent'], true);
    final plain = api.tasks.firstWhere((t) => t['title'] == 'ekmek');
    expect(plain['status'], 'inbox');
    expect(plain['dueAt'], isNull);
  });

  testWidgets('Project tab: +Name is not read; the task stays in the project', (
    tester,
  ) async {
    final api = FakeApi()
      ..seedProject(name: 'Hedef')
      ..seedProject(name: 'Other');
    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hedef'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('Tasks')),
    );
    await tester.pumpAndSettle();

    await _type(tester, 'project-quick-add', '+Other x');
    expect(find.byKey(const Key('quick-add-token-project')), findsNothing);
    await _submit(tester);

    final hedef = api.projects.firstWhere((p) => p['name'] == 'Hedef');
    expect(api.tasks.single['title'], '+Other x');
    expect(api.tasks.single['projectId'], hedef['id']);
  });

  testWidgets('Home: +Name files the task in an existing project', (
    tester,
  ) async {
    await _wide(tester);
    final api = FakeApi()..seedProject(name: 'Ev İşleri');
    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();

    await _type(tester, 'home-quick-add', 'yarın bulaşık +ev işleri');
    expect(find.byKey(const Key('quick-add-token-project')), findsOneWidget);
    await _submit(tester);
    expect(api.tasks.single['title'], 'bulaşık');
    expect(api.tasks.single['projectId'], api.projects.single['id']);
  });

  testWidgets('the ? opens the syntax sheet', (tester) async {
    await _wide(tester);
    final api = FakeApi();
    await tester.pumpWidget(await _app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('quick-add-help')).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quick-add-help-sheet')), findsOneWidget);
    expect(find.text('What quick add understands'), findsWidgets);
    expect(find.text('Deadline or When'), findsOneWidget);
  });
}
