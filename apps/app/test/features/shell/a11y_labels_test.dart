// OPH-407 (polish 4 T-07, `.ceo/shots3/ios/INDEX.md` E-7): what a screen
// reader hears matches what the screen says.
//
// - A task row's project pill was heard as "Project: Launch v1.0 / Launch
//   v1.0 / Launch v1.0" — an English prefix in a Turkish session, then the
//   name again from the text and again from the tooltip. It is one localized
//   label now, the name heard once.
// - The muted row's "Sesi aç" button was announced as "Alarmı geri aç": the
//   accessible name did not contain the visible words (WCAG 2.5.3 label in
//   name), so a voice-control user saying "Sesi aç" hit nothing.
// - The Görünüm menu drew a check on the current view and order but never
//   said "selected".
// - The large-text section list exposed each row twice: an outer button with
//   no label (only "Tab 2 of 5") around the ListTile's own button.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/list_sort.dart';
import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/ticket_work_providers.dart';
import 'package:alliswell/src/features/home/home_view_menu.dart';
import 'package:alliswell/src/features/projects/data/project.dart';
import 'package:alliswell/src/features/projects/providers.dart';
import 'package:alliswell/src/features/projects/ui/project_badge.dart';
import 'package:alliswell/src/features/tags/tags.dart';
import 'package:alliswell/src/features/tasks/data/task.dart';
import 'package:alliswell/src/features/tasks/data/task_sort.dart';
import 'package:alliswell/src/features/tasks/ui/task_tile.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/theme/tokens.dart';

import 'shell_harness.dart';

const _project = Project(
  id: 'P1',
  workspaceId: 'W1',
  name: 'Ev',
  colorRgb: '#2563EB',
  status: 'active',
  sortOrder: 0,
  isFavorite: false,
  revision: 1,
);

Task _task({bool muted = false}) => Task(
  id: muted ? 't-muted' : 't-plain',
  workspaceId: 'W1',
  title: 'Faturayı öde',
  status: 'open',
  priority: 'medium',
  timezone: 'Europe/Istanbul',
  isUrgent: muted,
  requiresAcknowledgement: false,
  sortOrder: 0,
  revision: 1,
  dueAt: muted ? DateTime.now().add(const Duration(days: 2)).toUtc() : null,
  remindAt: muted ? DateTime.now().add(const Duration(days: 1)).toUtc() : null,
  projectId: 'P1',
  alarmsMutedAt: muted ? DateTime.now().toUtc() : null,
);

Future<void> _pumpRow(WidgetTester tester, Task task) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        projectsByIdProvider.overrideWithValue(const {'P1': _project}),
        tagsByIdProvider.overrideWithValue(const <String, Tag>{}),
        unitLabelsProvider.overrideWithValue(const {}),
        workspaceAssigneesProvider.overrideWith((ref) => Stream.value({})),
        workTicketsByTaskProvider.overrideWith((ref) => Stream.value({})),
      ],
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: AwSpace.x4),
            children: [TaskTile(key: const ValueKey('row'), task: task)],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every label, value and tooltip a reader meets under [node].
List<String> _spoken(SemanticsNode node) {
  final out = <String>[];
  void visit(SemanticsNode n) {
    // A merged node speaks for its subtree; its parts are not heard again.
    if (n.isMergedIntoParent) return;
    final d = n.getSemanticsData();
    for (final s in [d.label, d.value, d.tooltip]) {
      if (s.trim().isNotEmpty) out.add(s);
    }
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(node);
  return out;
}

void main() {
  tearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));

  for (final language in ['tr', 'en']) {
    testWidgets('$language: the project pill is one localized label, the '
        'name heard once', (tester) async {
      AwI18n.instance.setActiveCached(Locale(language));
      final handle = tester.ensureSemantics();
      await _pumpRow(tester, _task());
      expect(find.byType(ProjectBadge), findsOneWidget);

      final expected = 'task.projectSemantic'.tr(args: {'project': 'Ev'});
      // The pill merges into the row's node; the row is where it is heard.
      final spoken = _spoken(
        tester.getSemantics(find.byKey(const ValueKey('row'))),
      ).join(' | ');
      expect(spoken, contains(expected), reason: spoken);
      if (language == 'tr') {
        expect(spoken, isNot(contains('Project:')), reason: spoken);
      }
      expect(
        RegExp(r'\bEv\b').allMatches(spoken).length,
        1,
        reason: 'the project name once: $spoken',
      );
      handle.dispose();
    });

    testWidgets('$language: the unmute button is heard as what it says', (
      tester,
    ) async {
      AwI18n.instance.setActiveCached(Locale(language));
      final handle = tester.ensureSemantics();
      await _pumpRow(tester, _task(muted: true));
      final button = find.byKey(const Key('unmute-t-muted'));
      final visible = 'task.unmuteShort'.tr();
      expect(
        find.descendant(of: button, matching: find.text(visible)),
        findsOneWidget,
      );
      final node = tester.getSemantics(button);
      final data = node.getSemanticsData();
      expect(data.label, visible);
      expect(data.flagsCollection.isButton, isTrue);
      expect(
        _spoken(node).join(' '),
        isNot(contains('task.unmuteAlarms'.tr())),
        reason: 'the long wording is a tooltip for the eye only',
      );
      handle.dispose();
    });
  }

  testWidgets('the Görünüm menu says which view and order are selected', (
    tester,
  ) async {
    AwI18n.instance.setActiveCached(const Locale('tr'));
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              HomeViewMenuButton(
                isBoard: false,
                calendarVisible: true,
                sortChoices: kTaskSortChoices,
                sort: const AwSortState('date', descending: false),
                onView: (_) {},
                onToggleCalendar: () {},
                onSort: (_) {},
                onEditColumns: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('home-view-menu')));
    await tester.pumpAndSettle();

    Tristate selected(String key) => tester
        .getSemantics(find.byKey(Key(key)))
        .getSemanticsData()
        .flagsCollection
        .isSelected;

    expect(selected('home-view-list'), Tristate.isTrue);
    expect(selected('home-view-board'), isNot(Tristate.isTrue));
    expect(selected('sort-option-date'), Tristate.isTrue);
    for (final choice in kTaskSortChoices.where((c) => c.id != 'date')) {
      expect(
        selected('sort-option-${choice.id}'),
        isNot(Tristate.isTrue),
        reason: choice.id,
      );
    }
    // An action is not a choice: it is never announced as selected.
    expect(selected('toggle-calendar'), isNot(Tristate.isTrue));
    handle.dispose();
  });

  testWidgets('the large-text section list has no unlabelled button', (
    tester,
  ) async {
    AwI18n.instance.setActiveCached(const Locale('tr'));
    final handle = tester.ensureSemantics();
    sizeTo(tester, const Size(393, 852));
    tester.platformDispatcher.textScaleFactorTestValue = 3.1;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(await teamApp(teamApi()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-menu-button')));
    await tester.pumpAndSettle();

    final sheet = tester.getSemantics(find.byKey(const Key('tab-menu-sheet')));
    final unlabelled = <String>[];
    var buttons = 0;
    void visit(SemanticsNode n) {
      if (n.isMergedIntoParent) return;
      final d = n.getSemanticsData();
      if (d.flagsCollection.isButton) {
        buttons++;
        if (d.label.trim().isEmpty) unlabelled.add('#${n.id} ${d.hint}');
      }
      n.visitChildren((c) {
        visit(c);
        return true;
      });
    }

    visit(sheet);
    expect(unlabelled, isEmpty, reason: 'buttons without a name');
    // Six sections and the sheet's drag handle — one button per row.
    expect(buttons, 7, reason: 'one button per section, not two');

    for (var i = 0; i < 6; i++) {
      final node = tester
          .getSemantics(find.byKey(Key('tab-menu-row-$i')))
          .getSemanticsData();
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.label, isNotEmpty);
      expect(
        node.flagsCollection.isSelected,
        i == 0 ? Tristate.isTrue : Tristate.isFalse,
      );
    }
    expect(
      tester
          .getSemantics(find.byKey(const Key('tab-menu-row-0')))
          .getSemanticsData()
          .label,
      'nav.home'.tr(),
    );
    handle.dispose();
  });
}
