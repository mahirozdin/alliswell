import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/ai/data/ai_context_builder.dart';

/// OPH-221 — the context packer is pure: budget, tiers, caps, provenance.
void main() {
  const meta = AiContextMeta(
    locale: 'tr',
    timezone: 'Europe/Istanbul',
    nowIso: '2026-07-30T12:00:00+03:00',
    weekday: 'Thursday',
    defaultTaskTime: '23:59',
  );

  test('T0 meta is always present', () {
    final bundle = buildAiContext(meta: meta, projects: const []);
    expect(bundle.segments, isNotEmpty);
    expect(bundle.segments.first.tier, 't0');
    expect(bundle.segments.first.text, contains('tz=Europe/Istanbul'));
  });

  test('T1 caps at 50 rows and flags truncation', () {
    final many = List.generate(80, (i) => TaskLite(title: 'Görev $i'));
    final bundle = buildAiContext(meta: meta, projects: const [], today: many);
    final t1 = bundle.segments.firstWhere((s) => s.tier == 't1');
    expect('\n'.allMatches(t1.text).length + 1, 50);
    expect(bundle.truncated, isTrue);
  });

  test(
    'the token budget drops T2 excerpts from the tail with a truncation flag',
    () {
      final excerpts = List.generate(
        20,
        (i) => SearchExcerpt(source: 'note', id: 'N$i', text: 'x' * 400),
      );
      final bundle = buildAiContext(
        meta: meta,
        projects: const [],
        excerpts: excerpts,
        tokenBudget: 300,
      );
      expect(bundle.tokenEstimate, lessThanOrEqualTo(300));
      expect(bundle.truncated, isTrue);
    },
  );

  test('a shared block is framed as external content', () {
    final bundle = buildAiContext(
      meta: meta,
      projects: const [],
      sharedBlock: const SharedPayload(
        text: 'paylaşılan metin',
        url: 'https://x.example',
      ),
    );
    final shared = bundle.segments.firstWhere(
      (s) => s.source == 'external_share',
    );
    expect(shared.text, contains('paylaşılan metin'));
    expect(shared.text, contains('https://x.example'));
  });

  test('project names and counts land in a T0 segment', () {
    final bundle = buildAiContext(
      meta: meta,
      projects: const [ProjectLite(id: 'P1', name: 'Ev işleri', openCount: 3)],
    );
    final projects = bundle.segments.firstWhere((s) => s.source == 'projects');
    expect(projects.text, contains('Ev işleri (3)'));
  });

  test('toJson never carries anything but tier/source/id/text', () {
    final bundle = buildAiContext(
      meta: meta,
      projects: const [ProjectLite(id: 'P1', name: 'X')],
      excerpts: const [
        SearchExcerpt(source: 'task', id: 'T1', text: 'excerpt'),
      ],
    );
    for (final segment in bundle.toJson()['segments'] as List) {
      expect(
        (segment as Map).keys.toSet().difference({
          'tier',
          'source',
          'id',
          'text',
        }),
        isEmpty,
      );
    }
  });
}
