import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ee/ui/new_ticket_screen.dart';
import 'package:alliswell/src/features/ee/ui/team_chip.dart';
import 'package:alliswell/src/features/workspaces/ui/workspace_switcher.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/widgets/glass.dart';

import 'shell_harness.dart';

/// OPH-359 — the phone shell: what floats over the content, and what the
/// content does about it.
///
///   • UI-AUDIT #10: a section's OWN floating button (the request queue's
///     "new request") sat under the glass bar — invisible, and a tap on it
///     opened Files. It must clear the bar and do its job.
///   • UI-AUDIT #58: the bar's outermost labels were clipped by the capsule's
///     corners and six of them did not fit; the empty state sat behind the
///     floating buttons; the title lost its room to the unit switcher, which
///     could only be an icon there.
void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  testWidgets('UI-AUDIT #10: the queue\'s "new request" clears the bar and '
      'opens the form', (tester) async {
    sizeTo(tester, const Size(390, 844));
    await tester.pumpWidget(await teamApp(teamApi()));
    await tester.pumpAndSettle();
    appRouter().go('/tickets');
    await tester.pumpAndSettle();

    final fab = find.byKey(const Key('ticket-new'));
    expect(fab, findsOneWidget);
    final bar = tester.getRect(find.byType(NavigationBar));
    final button = tester.getRect(fab);
    expect(
      button.bottom,
      lessThanOrEqualTo(bar.top),
      reason: 'the button is drawn under the glass bar',
    );

    await tester.tap(fab);
    await tester.pumpAndSettle();
    expect(find.byType(EeNewTicketScreen), findsOneWidget);
    expect(appRouter().state.uri.path, '/tickets/new');
  });

  testWidgets('UI-AUDIT #58: six sections — the labels sit inside the '
      'capsule\'s curve and only the selected one is written', (tester) async {
    sizeTo(tester, const Size(390, 844));
    await tester.pumpWidget(await teamApp(teamApi()));
    await tester.pumpAndSettle();

    final navBar = find.byType(NavigationBar);
    final bar = tester.widget<NavigationBar>(navBar);
    expect(bar.destinations, hasLength(6));
    expect(
      bar.labelBehavior,
      NavigationDestinationLabelBehavior.onlyShowSelected,
    );
    final capsule = tester.getRect(
      find.ancestor(of: navBar, matching: find.byType(GlassSurface)),
    );
    final inner = tester.getRect(navBar);
    expect(inner.left - capsule.left, greaterThanOrEqualTo(12));
    expect(capsule.right - inner.right, greaterThanOrEqualTo(12));
  });

  testWidgets('UI-AUDIT #58: the empty Home says its sentence where no '
      'floating button covers it', (tester) async {
    sizeTo(tester, const Size(390, 844));
    final api = teamApi()..seedAiConnection(provider: 'anthropic');
    await tester.pumpWidget(await teamApp(api));
    await tester.pumpAndSettle();

    final sentence = find.text('home.allCaughtUpBody'.tr());
    expect(sentence, findsOneWidget);
    final text = tester.getRect(sentence);
    final fabs = find.byType(FloatingActionButton);
    expect(fabs, findsWidgets);
    for (final element in fabs.evaluate()) {
      final fab = tester.getRect(find.byWidget(element.widget));
      expect(
        text.overlaps(fab),
        isFalse,
        reason: 'the empty state sits behind a floating button',
      );
    }
  });

  testWidgets('UI-AUDIT #58: on a phone the team and the unit ride under '
      'the title, and the unit is NAMED', (tester) async {
    sizeTo(tester, const Size(390, 844));
    const units = [
      WorkspaceSummary(
        id: '01HWS00000000000000000BAKM',
        name: 'Bakım',
        slug: 'bakim',
        colorRgb: '#2563EB',
        role: 'member',
      ),
      WorkspaceSummary(
        id: '01HWS00000000000000000URTM',
        name: 'Üretim',
        slug: 'uretim',
        colorRgb: '#2563EB',
        role: 'member',
      ),
    ];
    await tester.pumpWidget(
      await teamApp(
        teamApi(),
        more: [workspacesProvider.overrideWith((ref) async => units)],
      ),
    );
    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar).first);
    // The title IS the switcher: two lines, one target.
    expect(appBar.title, isA<AwWorkspaceSwitcher>());
    final title = find.byWidget(appBar.title!);
    expect(
      find.descendant(of: title, matching: find.byType(AwTeamChip)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: title, matching: find.text('Bakım')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: title, matching: find.text('nav.home'.tr())),
      findsOneWidget,
    );
    // Not in the action row any more, where it ate the title's room.
    for (final action in appBar.actions ?? const <Widget>[]) {
      expect(action, isNot(isA<AwWorkspaceSwitcher>()));
    }
    // DESIGN §5: a target a thumb can hit.
    expect(
      tester.getSize(find.byKey(const Key('workspace-switcher'))).height,
      greaterThanOrEqualTo(44),
    );
  });
}
