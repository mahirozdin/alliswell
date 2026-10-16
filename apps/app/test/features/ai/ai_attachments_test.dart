import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ai/data/ai_attachments.dart';
import 'package:alliswell/src/features/ai/data/ai_context_builder.dart';

/// OPH-377 — the pure request builder of "@" attachments: what is packed,
/// how it is cut, what is left out, and that only text ever leaves.
void main() {
  AiAttachmentRef note(String id, [String title = 'Not']) =>
      AiAttachmentRef(kind: AiAttachmentKind.note, id: id, title: title);

  group('packAttachedSegments', () {
    test('an item under the cap is packed whole as tier attached', () {
      final pack = packAttachedSegments([
        AiAttachment.ready(note('N1'), '# Q3 plan\n\nKarar: B'),
      ]);
      expect(pack.segments, hasLength(1));
      final s = pack.segments.single;
      expect(s.tier, 'attached');
      expect(s.source, 'attached_note');
      expect(s.id, 'N1');
      expect(s.text, '# Q3 plan\n\nKarar: B');
      expect(pack.truncated, isFalse);
      expect(pack.dropped, isEmpty);
    });

    test('an item over the cap is cut with the exact notice', () {
      final long = 'a' * 15000;
      final pack = packAttachedSegments([AiAttachment.ready(note('N1'), long)]);
      final text = pack.segments.single.text;
      expect(
        text,
        '${'a' * kAiAttachItemChars}\n[Truncated: the first 12000 of 15000 '
        'characters were attached.]',
      );
      expect(pack.truncated, isTrue);
      final a = AiAttachment.ready(note('N1'), long);
      expect(a.truncated, isTrue);
      expect(a.sentChars, kAiAttachItemChars);
      expect(a.totalChars, 15000);
    });

    test('the conversation cap leaves out whole items and reports them', () {
      final pack = packAttachedSegments([
        AiAttachment.ready(note('N1'), 'a' * 15000),
        AiAttachment.ready(note('N2'), 'b' * 15000),
        AiAttachment.ready(note('N3'), 'c' * 15000),
        AiAttachment.ready(note('N4', 'Dördüncü'), 'd' * 15000),
        AiAttachment.ready(note('N5'), 'short'),
      ]);
      // 3 × 12000 = 36000; a fourth 12000 would pass 40000 → N4 left out
      // whole; the short N5 still fits.
      expect(pack.segments.map((s) => s.id), ['N1', 'N2', 'N3', 'N5']);
      expect(pack.dropped.map((r) => r.title), ['Dördüncü']);
      expect(pack.truncated, isTrue);
    });

    test('newest first, duplicates deduplicated — the newest copy wins', () {
      final pack = packAttachedSegments([
        AiAttachment.ready(note('N1'), 'yeni'),
        AiAttachment.ready(note('N2'), 'başka'),
        AiAttachment.ready(note('N1'), 'eski'),
      ]);
      expect(pack.segments.map((s) => s.text), ['yeni', 'başka']);
    });

    test('loading and refused items are never packed', () {
      final pack = packAttachedSegments([
        AiAttachment.loading(note('N1')),
        AiAttachment.refused(note('N2'), AiAttachmentRefusal.notText),
      ]);
      expect(pack.segments, isEmpty);
      expect(pack.truncated, isFalse);
    });

    test('a file attachment serializes text only — no URL anywhere', () {
      const ref = AiAttachmentRef(
        kind: AiAttachmentKind.file,
        id: 'F1',
        title: 'notes.md',
        mime: 'text/markdown',
      );
      final pack = packAttachedSegments([
        AiAttachment.ready(ref, aiFileText('notes.md', 'merhaba')),
      ]);
      final bundle = const AiContextBundle(
        segments: [],
        tokenEstimate: 0,
        truncated: false,
      ).withAttached(pack.segments);
      final json = jsonEncode(bundle.toJson());
      expect(json, contains('attached_file'));
      expect(json, isNot(contains('http')));
      expect(json, isNot(contains('url')));
    });
  });

  group('AiContextBundle.withAttached', () {
    AiContextBundle liveAtBudget() => buildAiContext(
      meta: const AiContextMeta(
        locale: 'tr',
        timezone: 'Europe/Istanbul',
        nowIso: '2026-10-17T10:00:00+03:00',
        weekday: 'Saturday',
        defaultTaskTime: '09:00',
      ),
      projects: const [],
      excerpts: [
        for (var i = 0; i < 40; i++)
          SearchExcerpt(source: 'task', id: 'T$i', text: 'x' * 1000),
      ],
    );

    test('attached go first, truncated ORs, the live budget never cuts', () {
      final live = liveAtBudget();
      expect(live.truncated, isTrue, reason: 'the live bundle is full');
      final pack = packAttachedSegments([
        AiAttachment.ready(note('N1'), 'z' * 11000),
      ]);
      final bundle = live.withAttached(
        pack.segments,
        truncated: pack.truncated,
      );
      expect(bundle.segments.first.tier, 'attached');
      expect(bundle.segments.first.text.length, 11000);
      expect(bundle.segments.length, live.segments.length + 1);
      expect(bundle.truncated, isTrue);
      expect(bundle.tokenEstimate, live.tokenEstimate + 2750);
    });

    test('nothing attached → the same bundle', () {
      final live = liveAtBudget();
      expect(identical(live.withAttached(const []), live), isTrue);
    });
  });

  group('text files', () {
    test('aiFileIsTextLike', () {
      expect(aiFileIsTextLike('a.md', 'application/octet-stream'), isTrue);
      expect(aiFileIsTextLike('a.txt', ''), isTrue);
      expect(aiFileIsTextLike('a.csv', 'text/csv'), isTrue);
      expect(aiFileIsTextLike('data', 'application/json'), isTrue);
      expect(aiFileIsTextLike('x', 'text/x-whatever'), isTrue);
      expect(aiFileIsTextLike('x', 'text/plain; charset=utf-8'), isTrue);
      expect(aiFileIsTextLike('a.pdf', 'application/pdf'), isFalse);
      expect(
        aiFileIsTextLike(
          'a.docx',
          'application/vnd.openxmlformats-officedocument.'
              'wordprocessingml.document',
        ),
        isFalse,
      );
      expect(aiFileIsTextLike('a.png', 'image/png'), isFalse);
      expect(aiFileIsTextLike('a.bin', 'application/octet-stream'), isFalse);
      expect(aiFileIsTextLike('README', 'application/octet-stream'), isFalse);
    });

    test('aiLooksBinary finds a NUL in the first 8 KiB', () {
      expect(aiLooksBinary(utf8.encode('merhaba')), isFalse);
      expect(aiLooksBinary([0x41, 0x00, 0x42]), isTrue);
      expect(aiLooksBinary([...List.filled(9000, 0x41), 0x00]), isFalse);
    });

    test('aiDecodeText strips a BOM and keeps Turkish', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('Çalışma ğüşiöç')];
      expect(aiDecodeText(bytes), 'Çalışma ğüşiöç');
      expect(aiDecodeText([0x41, 0xFF, 0x42]), 'A�B');
    });
  });

  group('formatters', () {
    test('aiNoteText', () {
      expect(aiNoteText('Q3', 'Karar'), '# Q3\n\nKarar');
      expect(aiNoteText('Q3', '  '), '# Q3');
    });

    test('aiTaskText carries the fields, the body and the checklist', () {
      final text = aiTaskText(
        title: 'Kira',
        status: 'open',
        priority: 'high',
        dueLabel: '2026-10-18 09:00',
        whenLabel: '2026-10-17',
        minutes: 30,
        projectName: 'Ev',
        description: 'Banka havalesi',
        checklist: const [('IBAN', true), ('Dekont', false)],
      );
      expect(text, contains('Task: Kira'));
      expect(text, contains('Priority: high'));
      expect(text, contains('Project: Ev'));
      expect(text, contains('When: 2026-10-17'));
      expect(text, contains('Due: 2026-10-18 09:00'));
      expect(text, contains('Duration: 30 min'));
      expect(text, contains('Banka havalesi'));
      expect(text, contains('- [x] IBAN'));
      expect(text, contains('- [ ] Dekont'));
    });

    test('aiProjectText caps the open tasks at 50 with a count', () {
      final text = aiProjectText(
        name: 'Ev',
        description: 'Tadilat',
        openTasks: [
          for (var i = 0; i < 53; i++) ('İş $i', i == 0 ? '2026-10-18' : null),
        ],
      );
      expect(text, contains('Project: Ev'));
      expect(text, contains('Open tasks (53):'));
      expect(text, contains('- İş 0 — due 2026-10-18'));
      expect(text, contains('- İş 49'));
      expect(text, isNot(contains('- İş 50')));
      expect(text, contains('… and 3 more'));
    });
  });
}
