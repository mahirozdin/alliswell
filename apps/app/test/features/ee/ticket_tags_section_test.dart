import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/features/ee/providers.dart';
import 'package:alliswell/src/features/ee/ticket_tags_providers.dart';
import 'package:alliswell/src/features/ee/ui/ticket_tags_section.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-235 — the desk's words on a request: read from the device, written over
/// REST, grey with a reason when there is no signal.
const _ticketId = '01TKAAAAAAAAAAAAAAAAAAAAAA';

TicketRecord _ticket({String? tagNames}) => TicketRecord(
  id: _ticketId,
  workspaceId: 'W1',
  subject: 'Pres hidroliği kaçırıyor',
  status: 'in_progress',
  priority: 'high',
  source: 'internal',
  tagNames: tagNames,
  revision: 3,
);

class _Api implements EeTicketTagsApi {
  final tagged = <String>[];
  final untagged = <String>[];
  var words = [const EeTagWord(id: 'TG1', name: 'Garanti', uses: 4)];

  @override
  Future<List<EeTagWord>> vocabulary() async => words;

  @override
  Future<List<EeTagWord>> tag(String ticketId, String name) async {
    tagged.add(name);
    // One entry per word, as the server answers (the vocabulary's fold).
    return [
      const EeTagWord(id: 'TG1', name: 'Garanti'),
      if (foldTag(name) != foldTag('Garanti')) EeTagWord(id: 'TG2', name: name),
    ];
  }

  @override
  Future<void> untag(String ticketId, String tagId) async =>
      untagged.add(tagId);
}

class _Online extends ServerReachability {
  @override
  bool? build() => true;
}

class _Offline extends ServerReachability {
  @override
  bool? build() => false;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('tr'));
  });

  Future<_Api> pump(
    WidgetTester tester, {
    String? tagNames,
    bool may = true,
    bool online = true,
  }) async {
    final api = _Api();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eeTicketTagsApiProvider.overrideWithValue(api),
          eeTagVocabularyProvider.overrideWith((ref) async => api.words),
          canProvider.overrideWith(
            (ref, permission) => may && permission == 'tickets.comment',
          ),
          serverReachabilityProvider.overrideWith(
            online ? _Online.new : _Offline.new,
          ),
          syncEngineProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: buildAwTheme(Brightness.light),
          home: Scaffold(
            body: EeTicketTagsSection(ticket: _ticket(tagNames: tagNames)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('the words on the row are chips — and a new one goes to the '
      'server and shows at once', (tester) async {
    final api = await pump(tester, tagNames: '["Garanti"]');
    expect(find.byKey(const Key('ticket-tag-Garanti')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ticket-tag-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ticket-tag-field')),
      'Hidrolik',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('ticket-tag-save')));
    await tester.pumpAndSettle();

    expect(api.tagged, ['Hidrolik']);
    // The server's answer until the next pull brings the row down.
    expect(find.byKey(const Key('ticket-tag-Hidrolik')), findsOneWidget);
    expect(find.byKey(const Key('ticket-tag-Garanti')), findsOneWidget);
  });

  testWidgets('a word the team already uses is one tap away', (tester) async {
    final api = await pump(tester);
    await tester.tap(find.byKey(const Key('ticket-tag-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ticket-tag-field')), 'gar');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ticket-tag-suggestion-Garanti')));
    await tester.pumpAndSettle();
    expect(api.tagged, ['Garanti']);
  });

  testWidgets('taking a word off asks the server by the word\'s id', (
    tester,
  ) async {
    final api = await pump(tester, tagNames: '["Garanti"]');
    final chip = tester.widget<InputChip>(
      find.byKey(const Key('ticket-tag-Garanti')),
    );
    chip.onDeleted!();
    await tester.pumpAndSettle();
    expect(api.untagged, ['TG1']);
    expect(find.byKey(const Key('ticket-tag-Garanti')), findsNothing);
  });

  testWidgets('with no signal the chips stay, the doors go grey and say why', (
    tester,
  ) async {
    await pump(tester, tagNames: '["Garanti"]', online: false);
    expect(find.byKey(const Key('ticket-tag-Garanti')), findsOneWidget);
    expect(
      tester
          .widget<InputChip>(find.byKey(const Key('ticket-tag-Garanti')))
          .onDeleted,
      isNull,
    );
    expect(
      tester
          .widget<ActionChip>(find.byKey(const Key('ticket-tag-add')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('ticket-tags-offline')), findsOneWidget);
    expect(
      find.text('Etiket eklemek ve kaldırmak bağlantı ister.'),
      findsOneWidget,
    );
  });

  testWidgets('somebody who may not tag reads the words and gets no doors — '
      'and no heading at all when there are none', (tester) async {
    await pump(tester, tagNames: '["Garanti"]', may: false);
    expect(find.byKey(const Key('ticket-tag-Garanti')), findsOneWidget);
    expect(find.byKey(const Key('ticket-tag-add')), findsNothing);

    await pump(tester, may: false);
    expect(find.byKey(const Key('ticket-tags')), findsNothing);
  });
}
