import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/search/search.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/sync_applier.dart';

/// OPH-167 (ADR-0013) — the tiered fold search over the replica. Rows arrive
/// through the REAL applier, so these tests also prove the applier populates
/// the fold shadows for every searched entity type.
void main() {
  late AwDatabase db;
  late SearchService service;
  const ws = 'W1';

  setUp(() {
    db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    service = SearchService(db);
  });

  tearDown(() => db.close());

  Future<void> applyTask(
    String id,
    String title, {
    String? description,
    String status = 'open',
    List<String> tagIds = const [],
  }) async {
    await db
        .into(db.tasks)
        .insertOnConflictUpdate(
          taskCompanion({
            'id': id,
            'workspaceId': ws,
            'title': title,
            'description': description,
            'status': status,
          }),
        );
    await replaceTaskTags(db, id, tagIds);
  }

  Future<void> applyTag(String id, String name) => db
      .into(db.tags)
      .insertOnConflictUpdate(
        tagCompanion({
          'id': id,
          'workspaceId': ws,
          'name': name,
          'slug': name.toLowerCase(),
        }),
      );

  Future<void> applyTicket(
    String id,
    String subject, {
    String? body,
    int? number,
    String? createdAt,
  }) => db
      .into(db.tickets)
      .insertOnConflictUpdate(
        ticketCompanion({
          'id': id,
          'workspaceId': ws,
          'subject': subject,
          'body': body,
          'number': number,
          'createdAt': createdAt,
          'status': 'new',
          'priority': 'normal',
          'source': 'internal',
        }),
      );

  Future<void> applyTicketComment(String id, String ticketId, String body) => db
      .into(db.ticketComments)
      .insertOnConflictUpdate(
        ticketCommentCompanion({
          'id': id,
          'workspaceId': ws,
          'ticketId': ticketId,
          'body': body,
        }),
      );

  test('ranks title > tag > description and folds Turkish both ways', () async {
    await applyTag('G1', 'Çay');
    await applyTask('T-title', 'Çay siparişi');
    await applyTask('T-tag', 'Mutfak alışverişi', tagIds: ['G1']);
    await applyTask(
      'T-body',
      'Toplantı',
      description: 'çay servisi unutulmasın',
    );
    await applyTask('T-none', 'Alakasız iş');

    // ASCII query finds the Turkish text (cay → Çay), ranked by tier.
    final hits = await service.searchTasks(ws, 'cay', statuses: ['open']);
    expect(hits.map((h) => h.id).toList(), ['T-title', 'T-tag', 'T-body']);
    expect(hits.map((h) => h.tier).toList(), [0, 1, 2]);

    // And the reverse: a Turkish query finds ASCII-ish text.
    final reverse = await service.searchTasks(ws, 'ÇAY', statuses: ['open']);
    expect(reverse.map((h) => h.id), contains('T-title'));
  });

  test('multi-word queries AND their words, order-free', () async {
    await applyTask('T1', 'Sunum hazırla', description: 'pazartesi teslim');
    await applyTask('T2', 'Sunum izle');

    final both = await service.searchTasks(
      ws,
      'teslim sunum', // reversed order, split across title+description
      statuses: ['open'],
    );
    expect(both.map((h) => h.id).toList(), ['T1']);
    // Words split across FIELDS match the entity but no single field has
    // them all → body tier.
    expect(both.single.tier, 2);
  });

  test(
    'status scope is honored (inbox captures searchable on demand)',
    () async {
      await applyTask('T-in', 'Fikir: çay makinesi', status: 'inbox');
      expect(await service.searchTasks(ws, 'cay', statuses: ['open']), isEmpty);
      final withInbox = await service.searchTasks(
        ws,
        'cay',
        statuses: ['open', 'inbox'],
      );
      expect(withInbox.single.id, 'T-in');
    },
  );

  test('events search summary (tier 0) and location (tier 2)', () async {
    await db
        .into(db.externalEvents)
        .insertOnConflictUpdate(
          externalEventCompanion({
            'id': 'E1',
            'workspaceId': ws,
            'summary': 'Diş randevusu',
            'location': 'Kadıköy',
            'startsAt': '2026-08-01T09:00:00.000Z',
            'endsAt': '2026-08-01T10:00:00.000Z',
          }),
        );
    final bySummary = await service.searchEvents(ws, 'dis randevu');
    expect(bySummary.single.tier, 0);
    final byLocation = await service.searchEvents(ws, 'kadikoy');
    expect(byLocation.single.tier, 2);
  });

  test('projects search name (0) and description (2)', () async {
    await db
        .into(db.projects)
        .insertOnConflictUpdate(
          projectCompanion({
            'id': 'P1',
            'workspaceId': ws,
            'name': 'Yazılım',
            'description': 'iç araçlar',
          }),
        );
    expect((await service.searchProjects(ws, 'yazilim')).single.tier, 0);
    expect((await service.searchProjects(ws, 'araclar')).single.tier, 2);
  });

  test('LIKE wildcards in the query are literals, not wildcards', () async {
    await applyTask('T%', 'yüzde %20 indirim');
    await applyTask('TX', 'indirimsiz');
    final hits = await service.searchTasks(ws, '%20', statuses: ['open']);
    expect(hits.map((h) => h.id).toList(), ['T%']);
  });

  /// EE-169 — the service desk joins the registry. Tier 0 is the subject, tier
  /// 2 is the body AND the replies, and the NUMBER is its own exact path.
  test('tickets rank subject (0) over body and replies (2)', () async {
    // Distinct creation times: inside a tier the newest is first, and rows
    // that all tie would be ordered by id — which would make this test assert
    // an accident instead of the rule.
    await applyTicket(
      'K1',
      'Dolum bandı durdu',
      number: 41,
      createdAt: '2026-09-01T08:00:00.000Z',
    );
    await applyTicket(
      'K2',
      'Yazıcı arızası',
      body: 'Dolum hattında da oldu',
      number: 42,
      createdAt: '2026-09-03T08:00:00.000Z',
    );
    await applyTicket(
      'K3',
      'Kompresör',
      number: 43,
      createdAt: '2026-09-02T08:00:00.000Z',
    );
    await applyTicketComment('C1', 'K3', 'Dolum bölümünden bildirildi');

    final hits = await service.searchTickets(ws, 'dolum');
    expect(hits.map((h) => h.id), ['K1', 'K2', 'K3']);
    expect(hits.map((h) => h.tier), [0, 2, 2]);
  });

  test('a Turkish query folds both ways, like every other domain', () async {
    await applyTicket('K1', 'ISITICI arızası', number: 1);
    final hits = await service.searchTickets(ws, 'ısıtıcı');
    expect(hits.single.id, 'K1');
    expect(hits.single.tier, 0);
  });

  test('#1042 is an exact lookup, not a word in the body', () async {
    await applyTicket('K1', 'Rulman değişimi', number: 1042);
    await applyTicket(
      'K2',
      'Bakım',
      body: 'Sipariş no 1042 ile geldi',
      number: 7,
    );

    // The lookup answers with the request that HAS the number, and ONLY it:
    // the other one merely mentions 1042 in its body, and somebody reading a
    // number off a mail subject is not browsing.
    final byNumber = await service.searchTickets(ws, '#1042');
    expect(byNumber.map((h) => h.id), ['K1']);
    expect(byNumber.single.tier, 1);

    // … and the bare digits do the same, because a person types both.
    expect((await service.searchTickets(ws, '1042')).map((h) => h.id), ['K1']);
  });

  test('a number that no request holds finds the text instead', () async {
    await applyTicket(
      'K2',
      'Bakım',
      body: 'Sipariş no 1042 ile geldi',
      number: 7,
    );
    final hits = await service.searchTickets(ws, '1042');
    expect(hits.map((h) => h.id), ['K2']);
    expect(hits.single.tier, 2);
  });

  test('a query with a number AND a word stays a text search', () async {
    await applyTicket('K1', 'Rulman değişimi', number: 1042);
    await applyTicket(
      'K2',
      'Rulman sipariş',
      body: '1042 numaralı parça',
      number: 8,
    );
    // "1042 rulman" is somebody remembering roughly; answering with request
    // 1042 alone would drop half of what they typed.
    expect(ticketNumberQuery('1042 rulman'), null);
    final hits = await service.searchTickets(ws, '1042 rulman');
    expect(hits.map((h) => h.id), ['K2']);
  });

  test('the number query parser refuses everything that is not one', () {
    expect(ticketNumberQuery('#1042'), 1042);
    expect(ticketNumberQuery(' 1042 '), 1042);
    expect(ticketNumberQuery('#0'), null);
    expect(ticketNumberQuery('#'), null);
    expect(ticketNumberQuery('10x42'), null);
    expect(ticketNumberQuery('1234567890123'), null);
  });

  test(
    'the applier folds a ticket and its replies — both write points',
    () async {
      await applyTicket('K1', 'Fırın sıcaklığı', body: 'Gövde metni');
      await applyTicketComment('C1', 'K1', 'Yorum metni');
      final ticket = await (db.select(
        db.tickets,
      )..where((t) => t.id.equals('K1'))).getSingle();
      final comment = await (db.select(
        db.ticketComments,
      )..where((c) => c.id.equals('C1'))).getSingle();
      expect(ticket.subjectFold, 'firin sicakligi');
      expect(ticket.bodyFold, 'govde metni');
      expect(comment.bodyFold, 'yorum metni');
    },
  );

  /// The v27 upgrade's half that nobody would notice was missing: pull is
  /// incremental, so a request already on the device is never sent again and
  /// its shadows would stay null forever. "No results" would then mean "this
  /// device joined before search existed", which is indistinguishable on
  /// screen from "no such request".
  test('the v27 backfill folds requests that were already on the device', () async {
    await db.customStatement(
      "INSERT INTO tickets (id, workspace_id, subject, body, status, priority, source, revision) "
      "VALUES ('K9', ?, 'ISITICI arızası', 'Gövde metni', 'new', 'normal', 'internal', 0)",
      [ws],
    );
    await db.customStatement(
      "INSERT INTO ticket_comments (id, workspace_id, ticket_id, body, internal, revision) "
      "VALUES ('C9', ?, 'K9', 'Yorum metni', 0, 0)",
      [ws],
    );
    // Unfolded rows are invisible to search — that is the hole.
    expect(await service.searchTickets(ws, 'ısıtıcı'), isEmpty);

    await backfillTicketFolds(db);

    final hits = await service.searchTickets(ws, 'ısıtıcı');
    expect(hits.single.id, 'K9');
    expect((await service.searchTickets(ws, 'yorum')).single.id, 'K9');
  });

  // ── OPH-374: notes, tags and files join the registry ──────────────────

  Future<void> applyNote(
    String id,
    String title, {
    String? plainText,
    bool archived = false,
    String workspaceId = ws,
    String updatedAt = '2026-10-01T10:00:00.000Z',
  }) => db
      .into(db.notes)
      .insertOnConflictUpdate(
        noteCompanion({
          'id': id,
          'workspaceId': workspaceId,
          'title': title,
          'plainText': plainText,
          'isArchived': archived,
          'updatedAt': updatedAt,
        }),
      );

  Future<void> applyFile(
    String id,
    String name, {
    String targetType = 'workspace',
    String status = 'ready',
    String workspaceId = ws,
  }) => db
      .into(db.fileRows)
      .insertOnConflictUpdate(
        fileCompanion({
          'id': id,
          'workspaceId': workspaceId,
          'targetType': targetType,
          'targetId': 'X1',
          'name': name,
          'mime': 'application/pdf',
          'sizeBytes': 10,
          'status': status,
        }),
      );

  test(
    'notes: title (0) over body (2), archived and other workspaces out',
    () async {
      await applyNote('N1', 'Elektrik', plainText: 'ışık faturası burada');
      await applyNote('N2', 'Işık notu');
      await applyNote('N3', 'Işık arşivi', archived: true);
      await applyNote('N4', 'Işık başka alanda', workspaceId: 'W2');

      final hits = await service.searchNotes(ws, 'isik');
      expect(hits.map((h) => h.id), ['N2', 'N1']);
      expect(hits.map((h) => h.tier), [0, 2]);
    },
  );

  test('tags: one tier, no CASE — the single-tier SQL runs', () async {
    await applyTag('G1', 'Çay');
    await applyTag('G2', 'Kahve');

    final hits = await service.searchTags(ws, 'cay');
    expect(hits.single.id, 'G1');
    expect(hits.single.tier, 0);
    expect(await service.searchTags(ws, 'yok'), isEmpty);
  });

  test(
    'files: the applier writes the name fold; desk and unready rows are out',
    () async {
      await applyFile('F1', 'Fatura_Ekim.PDF');
      await applyFile('F2', 'Fatura cevabı.pdf', targetType: 'ticket_comment');
      await applyFile('F3', 'Fatura taslak.pdf', status: 'uploading');
      await applyFile('F4', 'Fatura başka.pdf', workspaceId: 'W2');
      await applyFile('F5', 'Proje fatura.pdf', targetType: 'task');

      final raw = await db
          .customSelect("SELECT name_fold FROM file_rows WHERE id = 'F1'")
          .getSingle();
      expect(raw.data['name_fold'], 'fatura_ekim.pdf');

      final hits = await service.searchFiles(ws, 'fatura');
      expect(hits.map((h) => h.id).toSet(), {'F1', 'F5'});
      expect(hits.every((h) => h.tier == 0), isTrue);
    },
  );

  test('searchSnippet windows around the folded match', () {
    const body =
        'Uzun bir açıklamanın ortasında çay servisi geçiyor ve devamında '
        'başka şeyler anlatılıyor.';
    final snippet = searchSnippet(body, 'cay');
    expect(snippet, contains('çay servisi'));
    expect(snippet.length, lessThan(body.length));
  });

  group('OPH-386: searchSnippet on multi-line text', () {
    test('newlines and runs of spaces do not shift the window', () {
      // Every line break before the hit used to move the cut one character
      // left of where the folded index pointed.
      const body =
          'Alışveriş listesi\n\n\n- ekmek\n- süt\n\n\n\n'
          'Pazartesi    günü   kirayı   ödemeyi unutma\n\nson satır';
      final snippet = searchSnippet(body, 'kira', radius: 12);
      expect(snippet, contains('kirayı'));
      expect(snippet, isNot(contains('\n')));
      expect(snippet, isNot(contains('  ')));
      expect(snippet, '…günü kirayı ödemeyi…');
    });

    test('the window never opens or closes on half a word', () {
      const body =
          'Birinci satır burada\nikinci satır şurada\n'
          'üçüncü satırda ÇAY demlemek var\ndördüncü satır orada';
      final snippet = searchSnippet(body, 'cay', radius: 10);
      expect(snippet, contains('ÇAY'));
      final words = body.replaceAll('\n', ' ').split(' ').toSet();
      final inner = snippet.replaceAll('…', '').split(' ');
      for (final w in inner) {
        expect(words, contains(w), reason: 'fragment "$w" in "$snippet"');
      }
    });

    test('Turkish dotted/dotless I and İ fold onto the right offsets', () {
      const body = 'IĞDIR\nyolculuğu için\n\nİSTANBUL ofisinde ılık bir gün';
      expect(searchSnippet(body, 'istanbul', radius: 6), startsWith('…'));
      expect(searchSnippet(body, 'istanbul', radius: 6), contains('İSTANBUL'));
      expect(searchSnippet(body, 'ilik', radius: 4), contains('ılık'));
      expect(searchSnippet(body, 'igdir', radius: 4), startsWith('IĞDIR'));
    });

    test('an expanding fold (ß → ss) keeps the hit whole', () {
      const body = 'Die Straße\nist lang und die Sonne scheint heute sehr warm';
      final snippet = searchSnippet(body, 'sonne', radius: 8);
      expect(snippet, contains('Sonne'));
      expect(snippet, isNot(contains('\n')));
    });

    test('no hit: the head of the collapsed text, cut on a word', () {
      const body = 'kısa\n\nnot';
      expect(searchSnippet(body, 'yok'), 'kısa not');
      final long = List.filled(30, 'kelime').join('\n');
      final snippet = searchSnippet(long, 'yok', radius: 10);
      expect(snippet, endsWith('…'));
      expect(
        snippet.replaceAll('…', '').split(' ').every((w) => w == 'kelime'),
        isTrue,
      );
    });
  });
}
