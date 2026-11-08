import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/tasks/ui/task_create_sheet.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';
import 'package:alliswell/src/widgets/dropdown_field.dart';

/// OPH-403 (H-6, DESIGN §49 N5–N7) — the new-task sheet has ONE input style.
///
/// The judge and the designer persona found three: a floating-label title, a
/// placeholder description, an icon-led "# Add tag…" (text starting at three
/// different x), a bare "Add file" link, and two Material dropdowns for
/// project and priority. Now every text field is the same G3 field (a label,
/// no leading icon, text on one line), and every choice — project, priority,
/// files — is a row of the sheet's own row pattern (icon column, name, value,
/// chevron) that opens a solid choice sheet.
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
    ],
    child: const AllisWellApp(),
  );
}

const _phone = Size(393, 852);
const _desktop = Size(1280, 900);

final _sheet = find.byType(TaskCreateSheet);
const _textFields = ['task-sheet-title', 'task-sheet-description', 'tag-input'];
const _rows = [
  'task-sheet-project',
  'task-sheet-priority',
  'task-sheet-attach',
  'task-sheet-when',
  'task-sheet-due',
  'task-sheet-remind',
  'task-sheet-duration',
  'task-sheet-urgent',
  'task-sheet-repeat',
];

Future<void> _open(
  WidgetTester tester,
  FakeApi api,
  Size size, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(await _app(api));
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(Scaffold).first);
  // ignore: unawaited_futures
  showTaskCreateSheet(context);
  await tester.pumpAndSettle();
  expect(_sheet, findsOneWidget);
}

Finder _in(String key) =>
    find.descendant(of: _sheet, matching: find.byKey(Key(key)));

/// The decorator that draws a text field's box.
InputDecoration _decorationOf(WidgetTester tester, String key) {
  final decorator = find.descendant(
    of: _in(key),
    matching: find.byType(InputDecorator),
  );
  expect(decorator, findsOneWidget, reason: '$key has one field box');
  return tester.widget<InputDecorator>(decorator).decoration;
}

double _textStart(WidgetTester tester, String key) => tester
    .getTopLeft(
      find.descendant(of: _in(key), matching: find.byType(EditableText)),
    )
    .dx;

/// A row's first icon (the icon column) and first text (its name).
Rect _rowIcon(WidgetTester tester, String key) => tester.getRect(
  find.descendant(of: _in(key), matching: find.byType(Icon)).first,
);
double _rowNameStart(WidgetTester tester, String key) => tester
    .getTopLeft(
      find.descendant(of: _in(key), matching: find.byType(Text)).first,
    )
    .dx;

Future<void> _checkOneStyle(WidgetTester tester) async {
  // No Material dropdown is left anywhere in the form.
  expect(
    find.descendant(
      of: _sheet,
      matching: find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField ||
            w is DropdownButton ||
            w is DropdownMenu ||
            w is AwDropdownField ||
            w is AwDropdownButton,
      ),
    ),
    findsNothing,
    reason: 'project and priority are rows, not dropdowns',
  );

  // The three text fields: the same G3 field — a label, no leading icon,
  // the same density — so their text starts on one x.
  final starts = <double>[];
  for (final key in _textFields) {
    final decoration = _decorationOf(tester, key);
    expect(decoration.labelText, isNotNull, reason: '$key has a label');
    expect(decoration.prefixIcon, isNull, reason: '$key has no leading icon');
    expect(decoration.prefix, isNull, reason: '$key has no leading widget');
    expect(decoration.isDense ?? false, isFalse, reason: '$key is not dense');
    starts.add(_textStart(tester, key));
  }
  for (final start in starts) {
    expect(start, moreOrLessEquals(starts.first, epsilon: 0.5));
  }

  // Every choice is a row of the one row pattern: icon in one column, name
  // starting on one x — the attach link and the dropdowns are gone.
  final first = _rows.first;
  for (final key in _rows) {
    await tester.ensureVisible(_in(key));
    await tester.pumpAndSettle();
    expect(_in(key), findsOneWidget, reason: '$key is a row of the sheet');
    expect(
      tester.widget(_in(key)),
      anyOf(
        isA<ListTile>().having((t) => t.onTap, 'onTap', isNotNull),
        isA<SwitchListTile>(),
      ),
      reason: '$key is a row of the one row pattern',
    );
  }
  final iconLeft = _rowIcon(tester, first).left;
  final nameLeft = _rowNameStart(tester, first);
  for (final key in _rows) {
    await tester.ensureVisible(_in(key));
    await tester.pumpAndSettle();
    expect(
      _rowIcon(tester, key).left,
      moreOrLessEquals(iconLeft, epsilon: 0.5),
      reason: '$key icon column',
    );
    expect(
      _rowNameStart(tester, key),
      moreOrLessEquals(nameLeft, epsilon: 0.5),
      reason: '$key name start',
    );
  }

  // No bare text-button link inside the form (the old "Add file").
  expect(
    find.descendant(
      of: find.byKey(const Key('task-sheet-form')),
      matching: find.byType(TextButton),
    ),
    findsNothing,
  );
}

void main() {
  for (final (label, size) in [('phone', _phone), ('desktop', _desktop)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('one input style on the $label at ${scale}x (OPH-403 H-6)', (
        tester,
      ) async {
        await _open(tester, FakeApi(), size, textScale: scale);
        await _checkOneStyle(tester);
      });
    }
  }

  testWidgets('project and priority are picked from a solid choice sheet', (
    tester,
  ) async {
    final api = FakeApi();
    final project = api.seedProject(name: 'Hedef Proje');
    await _open(tester, api, _phone);
    await tester.enterText(_in('task-sheet-title'), 'Seçimli iş');

    // The rows say what is chosen now: no project, the default Medium.
    expect(
      find.descendant(
        of: _in('task-sheet-project'),
        matching: find.text('No project'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _in('task-sheet-priority'),
        matching: find.text('Medium'),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(_in('task-sheet-project'));
    await tester.pumpAndSettle();
    await tester.tap(_in('task-sheet-project'));
    await tester.pumpAndSettle();
    final choices = find.byKey(const Key('aw-choice-sheet'));
    expect(choices, findsOneWidget);
    // A solid sheet (G1), the current value marked for sight and for screen
    // readers alike.
    expect(
      tester
          .widget<ListTile>(
            find.descendant(
              of: choices,
              matching: find.byKey(const Key('aw-choice-none')),
            ),
          )
          .selected,
      isTrue,
    );
    await tester.tap(
      find.descendant(of: choices, matching: find.text('Hedef Proje')),
    );
    await tester.pumpAndSettle();
    expect(choices, findsNothing);
    expect(
      find.descendant(
        of: _in('task-sheet-project'),
        matching: find.text('Hedef Proje'),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(_in('task-sheet-priority'));
    await tester.pumpAndSettle();
    await tester.tap(_in('task-sheet-priority'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ListTile>(
            find.descendant(
              of: choices,
              matching: find.byKey(const Key('aw-choice-medium')),
            ),
          )
          .selected,
      isTrue,
    );
    await tester.tap(find.descendant(of: choices, matching: find.text('High')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: _in('task-sheet-priority'),
        matching: find.text('High'),
      ),
      findsOneWidget,
    );

    // Backing out of a choice keeps what was chosen.
    await tester.tap(_in('task-sheet-priority'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(196, 20));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: _in('task-sheet-priority'),
        matching: find.text('High'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('task-sheet-create')));
    await tester.pumpAndSettle();
    expect(api.tasks.single['projectId'], project['id']);
    expect(api.tasks.single['priority'], 'high');
  });
}
