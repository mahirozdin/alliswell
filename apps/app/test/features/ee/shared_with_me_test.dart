import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/shared_items_providers.dart';
import 'package:alliswell/src/features/ee/ui/shared_with_me_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-061 — the receiving end of the bridge.
///
/// What is pinned: a shared item reads as a REFERENCE with a known ceiling,
/// not as one of your own tasks. Both halves matter — dressing it up as a task
/// would promise reordering and completing that this row cannot do, and hiding
/// the ceiling would let somebody type into something they may only read.
SharedItem item({
  String id = 'M1',
  String title = 'Fatura mutabakatı',
  String entityType = 'task',
  String rights = 'view',
}) => SharedItem(
  id: id,
  workspaceId: 'W1',
  shareId: 'S1',
  sourceWorkspaceId: 'W-SOURCE',
  entityType: entityType,
  entityId: 'E1',
  rights: rights,
  title: title,
  revision: 3,
  updatedAt: DateTime.utc(2026, 8, 21),
);

Widget harness(List<SharedItem> items) => ProviderScope(
  overrides: [sharedWithMeProvider.overrideWith((ref) => Stream.value(items))],
  child: MaterialApp(
    theme: buildAwTheme(Brightness.light),
    home: const EeSharedWithMeScreen(),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  testWidgets('nothing shared reads as empty, not as broken', (tester) async {
    await tester.pumpWidget(harness(const []));
    await tester.pumpAndSettle();
    expect(find.text('ee.shared.emptyTitle'.tr()), findsOneWidget);
  });

  testWidgets('a shared item names its kind AND its ceiling', (tester) async {
    await tester.pumpWidget(harness([item()]));
    await tester.pumpAndSettle();
    expect(find.text('Fatura mutabakatı'), findsOneWidget);
    // Read-only has to be legible BEFORE somebody starts typing.
    expect(find.textContaining('ee.shared.readOnly'.tr()), findsOneWidget);
  });

  testWidgets('an editable share says so, and differently', (tester) async {
    await tester.pumpWidget(harness([item(rights: 'edit')]));
    await tester.pumpAndSettle();
    expect(find.textContaining('ee.shared.canEdit'.tr()), findsOneWidget);
    expect(find.textContaining('ee.shared.readOnly'.tr()), findsNothing);
  });

  testWidgets('an untitled reference still renders a row to act on', (
    tester,
  ) async {
    // The cached label can be absent (a source with no title yet). A row that
    // vanished for want of a label would hide access somebody actually has.
    await tester.pumpWidget(harness([item(title: '')]));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shared-M1')), findsOneWidget);
    // And it SAYS it has no title rather than rendering a blank line — an
    // empty string is not null, which `??` alone would have missed.
    expect(find.text('ee.shared.untitled'.tr()), findsOneWidget);
  });
}
