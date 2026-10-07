import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ee/ui/approval_reason_dialog.dart';
import 'package:alliswell/src/features/ee/ui/sla_chip.dart';
import 'package:alliswell/src/features/ee/ui/ticket_archive_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/color_swatch_dot.dart';

/// OPH-359 — UI-AUDIT #64: the controls a screen reader met without a name.
///
/// Measured in the audit's semantics dumps: "alertdialog / Uyarı", "input: ",
/// "checkbox: " (in `ticket_bulk_test`), the SLA line missing, and colours
/// read as "#2563EB". Each one is asked for its name here.
void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  Widget host(Widget child) => ProviderScope(
    child: MaterialApp(theme: buildAwTheme(Brightness.light), home: child),
  );

  testWidgets('the approval reason dialog is named for what it asks', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const Scaffold(body: EeApprovalReasonDialog(approve: false))),
    );
    await tester.pumpAndSettle();
    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.semanticLabel, 'ee.approvals.rejectTitle'.tr());
  });

  testWidgets('the archive search field has a name, not only a hint', (
    tester,
  ) async {
    await tester.pumpWidget(host(const EeTicketArchiveSearchScreen()));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const Key('archive-search')),
    );
    expect(field.decoration?.labelText, 'ee.tickets.archive.searchLabel'.tr());
  });

  testWidgets('the SLA line is one node that says the whole thing', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final now = DateTime.utc(2026, 10, 7, 12);
    await tester.pumpWidget(
      host(
        Scaffold(
          body: AwSlaCountdown(
            now: now,
            ticket: TicketRecord(
              id: 'T1',
              workspaceId: 'W1',
              subject: 'Hat 3 durdu',
              status: 'new',
              priority: 'high',
              source: 'internal',
              revision: 1,
              createdAt: now,
              slaStatus: 'breached',
              slaDueAt: now.subtract(const Duration(hours: 2)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final label = tester
        .getSemantics(find.byKey(const Key('sla-countdown')))
        .label;
    expect(label, startsWith('${'ee.sla.dueLabel'.tr()}: '));
    expect(label.length, greaterThan('ee.sla.dueLabel'.tr().length + 2));
    handle.dispose();
  });

  group('colours are read by name', () {
    test('a hue becomes its everyday name, never its hex', () {
      expect(awColorName(const Color(0xFF2563EB)), 'color.blue'.tr());
      expect(awColorName(const Color(0xFFDC2626)), 'color.red'.tr());
      expect(awColorName(const Color(0xFF16A34A)), 'color.green'.tr());
      expect(awColorName(const Color(0xFF64748B)), 'color.grey'.tr());
    });

    test('two blues in one row are told apart', () {
      expect(awColorNames(const [Color(0xFF2563EB), Color(0xFF0284C7)]), [
        'color.blue'.tr(),
        '${'color.blue'.tr()} 2',
      ]);
    });

    testWidgets('a swatch says its name', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          Scaffold(
            body: AwColorSwatchDot(
              key: const Key('dot'),
              color: const Color(0xFF7C3AED),
              selected: false,
              onTap: () {},
            ),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('dot'))).label,
        'color.purple'.tr(),
      );
      handle.dispose();
    });
  });
}
