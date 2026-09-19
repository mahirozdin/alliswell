import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/data/team_webhooks_models.dart';
import 'package:alliswell/src/features/ee/team_webhooks_providers.dart';
import 'package:alliswell/src/features/ee/ui/team_webhooks_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-176 — the management screen, asserted where it would mislead.
///
/// The three claims worth holding down are the ones a redesign would quietly
/// break:
///
///   1. THE EVENT LIST IS THE SERVER'S. A free text box would let somebody
///      subscribe to an event this product never fires, and the symptom is a
///      call that never arrives — indistinguishable from a broken endpoint.
///   2. SAVE IS DEAD UNTIL THE FORM MEANS SOMETHING (DESIGN §22). An endpoint
///      with no events subscribed is a row that can never do anything.
///   3. A PAUSED ENDPOINT SAYS SO IN WORDS. The colour is a mark; the state is
///      a sentence, because `warning` is short of the contrast a label needs
///      (EE-097's rule).
class _Fixed extends EeTeamWebhooksController {
  _Fixed(this._value);
  final EeWebhooksData? _value;
  @override
  Future<EeWebhooksData?> build() async => _value;
}

const _vocabulary = ['ticket.routed', 'ticket.commented', 'sla.breached'];

EeWebhook _hook({
  String id = 'W1',
  String url = 'https://hooks.example.com/inbound',
  List<String> events = const ['ticket.routed'],
  bool enabled = true,
  String? last4 = '9f2c',
}) => EeWebhook(
  id: id,
  url: url,
  eventClasses: events,
  enabled: enabled,
  createdAt: DateTime(2026, 9, 19, 12),
  secretLast4: last4,
);

Future<void> _pump(WidgetTester tester, EeWebhooksData? value) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eeTeamWebhooksProvider.overrideWith(() => _Fixed(value)),
        // The delivery list is a separate round trip; an endpoint with no
        // history is the ordinary case and the one this file draws.
        eeWebhookDeliveriesProvider.overrideWith((ref, id) async => const []),
      ],
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: const EeTeamWebhooksScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  testWidgets(
    'an empty team is told what an endpoint is FOR, and what travels',
    (tester) async {
      await _pump(
        tester,
        const EeWebhooksData(items: [], eventClasses: _vocabulary),
      );
      expect(find.textContaining('No endpoints yet'), findsOneWidget);
      // The data boundary is on the empty screen rather than buried in a help
      // page: somebody deciding whether to add an endpoint is deciding what
      // leaves the building, and that is the moment to say it.
      expect(
        find.textContaining('never the text of a request'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a paused endpoint says so in WORDS, not only in colour', (
    tester,
  ) async {
    await _pump(
      tester,
      EeWebhooksData(items: [_hook(enabled: false)], eventClasses: _vocabulary),
    );
    expect(find.textContaining('Paused'), findsOneWidget);
    expect(find.textContaining('nothing is being sent'), findsOneWidget);
  });

  testWidgets('a row shows four characters of the secret and no more', (
    tester,
  ) async {
    await _pump(
      tester,
      EeWebhooksData(items: [_hook()], eventClasses: _vocabulary),
    );
    await tester.tap(find.byKey(const Key('webhook-W1')));
    await tester.pumpAndSettle();

    expect(find.textContaining('9f2c'), findsOneWidget);
    // Every control the row offers is an action on the endpoint. None of them
    // is "show the secret", because no endpoint exists to back one.
    expect(find.byKey(const Key('webhook-rotate-W1')), findsOneWidget);
    expect(find.textContaining('whsec_'), findsNothing);
  });

  testWidgets('the add dialog offers the SERVER\'s events and nothing else', (
    tester,
  ) async {
    await _pump(
      tester,
      const EeWebhooksData(items: [], eventClasses: _vocabulary),
    );
    await tester.tap(find.byKey(const Key('team-webhooks-add')));
    await tester.pumpAndSettle();

    for (final name in _vocabulary) {
      expect(find.byKey(Key('webhook-event-$name')), findsOneWidget);
    }
    // The classes this product does not fire are absent rather than offered:
    // `ticket.created` is the one somebody will look for and the one that
    // does not exist (the vocabulary calls it `ticket.routed`).
    expect(find.byKey(const Key('webhook-event-ticket.created')), findsNothing);
  });

  testWidgets('save stays dead until there is an address AND an event', (
    tester,
  ) async {
    await _pump(
      tester,
      const EeWebhooksData(items: [], eventClasses: _vocabulary),
    );
    await tester.tap(find.byKey(const Key('team-webhooks-add')));
    await tester.pumpAndSettle();

    FilledButton save() => tester.widget<FilledButton>(
      find.byKey(const Key('webhook-create-confirm')),
    );

    expect(save().onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('webhook-url-field')),
      'https://hooks.example.com/inbound',
    );
    await tester.tap(find.byKey(const Key('webhook-event-ticket.routed')));
    await tester.pumpAndSettle();

    expect(save().onPressed, isNotNull);
  });

  testWidgets('the ORDER does not matter: event first, then address', (
    tester,
  ) async {
    // The bug this holds down: Save is computed from the text field, and a
    // field with no listener does not rebuild the dialog. Typing last left
    // the button grey after the form was complete — a control lying about
    // itself, which is the one thing §22 forbids outright.
    await _pump(
      tester,
      const EeWebhooksData(items: [], eventClasses: _vocabulary),
    );
    await tester.tap(find.byKey(const Key('team-webhooks-add')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('webhook-event-sla.breached')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('webhook-url-field')),
      'https://hooks.example.com/inbound',
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('webhook-create-confirm')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('a team without the surface is told where it lives', (
    tester,
  ) async {
    await _pump(tester, null);
    expect(find.textContaining('belong to a team'), findsOneWidget);
    // Nothing to press: a FAB that could only fail is a dead control.
    expect(find.byKey(const Key('team-webhooks-add')), findsNothing);
  });
}
