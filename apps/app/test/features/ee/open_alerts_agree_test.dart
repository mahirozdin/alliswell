import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/features/ee/approvals_providers.dart';
import 'package:alliswell/src/features/ee/data/ee_models.dart';
import 'package:alliswell/src/features/ee/data/sla_dashboard_models.dart';
import 'package:alliswell/src/features/ee/data/unit_tickets_api.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/sla_dashboard_providers.dart';
import 'package:alliswell/src/features/ee/ui/home_ticket_cards.dart';
import 'package:alliswell/src/features/ee/ui/sla_dashboard_screen.dart';
import 'package:alliswell/src/features/ee/unit_tickets_providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// HK-1 (polish 3, OPH-409) — Home's "your units" figures and the SLA
/// board's "open right now" pair say the same numbers at the same moment.
///
/// Measured before the fix: the server counts both from one query, and two
/// captures 14 s apart agreed (Home 15, board 15 + 7). The 22 against
/// 15 + 7 came from two moments: Home, mounted all session, kept the page
/// it read first while the sweep moved seven requests from "due soon" to
/// "past SLA", and the board kept the answer of its first opening. Home
/// also said "late" for what the board calls "past SLA" and never named
/// "due soon", so a reader had to guess whether 22 was 15 + 7.
class _Perms extends EePermissionsController {
  @override
  Future<EePermissions> build() async => const EePermissions(
    workspaceId: 'ws-general',
    governed: true,
    permissions: ['tickets.create'],
    desk: true,
  );
}

/// Answers the pages in [answers] in turn, the last one for good.
class _MovingUnitsApi extends Fake implements EeUnitTicketsApi {
  _MovingUnitsApi(this.answers);
  final List<EeUnitTicketsPage> answers;
  int calls = 0;

  @override
  Future<EeUnitTicketsPage> list({
    bool alertsOnly = false,
    String? except,
    String? cursor,
    int? limit,
  }) async {
    final page = answers[calls.clamp(0, answers.length - 1)];
    calls += 1;
    return page;
  }
}

class _MovingBoard extends EeSlaDashboardController {
  static int calls = 0;
  static const answers = [
    EeSlaDashboard(openBreached: 15, openWarned: 7),
    EeSlaDashboard(openBreached: 22, openWarned: 0),
  ];

  @override
  Future<EeSlaDashboard?> build() async {
    final answer = answers[calls.clamp(0, answers.length - 1)];
    calls += 1;
    return answer;
  }
}

EeUnitTicketsPage _alerts(int breached, int warned) =>
    EeUnitTicketsPage(breached: breached, warned: warned);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  testWidgets('Home names "past SLA" and "due soon" apart, in the board\'s '
      'words, and asks again on every pull', (tester) async {
    final beats = StreamController<DateTime?>.broadcast();
    addTearDown(() => unawaited(beats.close()));
    final api = _MovingUnitsApi([_alerts(15, 7), _alerts(22, 0)]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eeFeatureProvider.overrideWith((ref, name) => true),
          currentUserIdProvider.overrideWithValue('user-1'),
          eePermissionsProvider.overrideWith(_Perms.new),
          eeUnitTicketsApiProvider.overrideWithValue(api),
          eeCurrentUnitPulledAtProvider.overrideWith((ref) => beats.stream),
          eeApprovalsDoorProvider.overrideWith((ref) => false),
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: const Scaffold(body: EeHomeTicketCards()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The pair the board shows ("Süresi aşılmış 15 · Dolmak üzere 7"),
    // never one folded number.
    expect(find.text('15 talebin süresi aşıldı'), findsOneWidget);
    expect(find.text('7 talebin süresi dolmak üzere'), findsOneWidget);
    expect(find.textContaining('gecikti'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('ee-home-warned'))).height,
      greaterThanOrEqualTo(44),
    );

    // The unit on screen pulls: Home reads the scope again, as the queue
    // and the other-units strip do.
    beats.add(DateTime.utc(2026, 11, 8, 7, 35));
    await tester.pumpAndSettle();
    expect(find.text('22 talebin süresi aşıldı'), findsOneWidget);
    expect(find.byKey(const Key('ee-home-warned')), findsNothing);
  });

  testWidgets('the SLA board asks again each time it is opened', (
    tester,
  ) async {
    _MovingBoard.calls = 0;
    final open = ValueNotifier(true);
    addTearDown(open.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [eeSlaDashboardProvider.overrideWith(_MovingBoard.new)],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: open,
              builder: (context, shown, _) => shown
                  ? const EeSlaDashboardScreen(embedded: true)
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    String figure(String key) => tester
        .widget<Text>(
          find
              .descendant(
                of: find.byKey(Key('sla-open-$key')),
                matching: find.byType(Text),
              )
              .last,
        )
        .data!;
    expect(figure('breached'), '15');
    expect(figure('warned'), '7');

    // Another tab, then back: the board does not show its first answer.
    open.value = false;
    await tester.pumpAndSettle();
    open.value = true;
    await tester.pumpAndSettle();
    expect(_MovingBoard.calls, 2);
    expect(figure('breached'), '22');
    expect(figure('warned'), '0');
  });
}
