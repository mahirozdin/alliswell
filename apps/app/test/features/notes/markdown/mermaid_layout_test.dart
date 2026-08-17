import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:markdown_forge/markdown_forge.dart';

/// OPH-254 — the layered layout, measured rather than eyeballed.
///
/// Text measurement is injected, so every coordinate below is deterministic.
/// That is the whole reason `flow_layout.dart` has no widgets in it: a golden
/// image would tell us a diagram was drawn, not that it was drawn READABLY.
void main() {
  // 8 px per character, 16 px tall — close enough in shape to real text that
  // the relative sizes stay meaningful.
  Size measure(String label) => Size(label.length * 8.0, 16);

  FlowLayout layout(String src) =>
      layoutFlowchart(parseMermaid(src) as MermaidFlow, measure: measure);

  group('ranking', () {
    test('a chain puts each node on its own rank, in order', () {
      final l = layout('flowchart TD\n A --> B --> C');

      final a = l.nodeById('A')!, b = l.nodeById('B')!, c = l.nodeById('C')!;
      expect(a.rect.top, lessThan(b.rect.top));
      expect(b.rect.top, lessThan(c.rect.top));
    });

    test('longest path wins: a join sits below BOTH its sources', () {
      // A --> B --> C and A --> C. C must land on rank 2, not rank 1, or the
      // edge from B would point backwards.
      final l = layout('flowchart TD\n A --> B\n B --> C\n A --> C');

      expect(l.nodeById('C')!.rect.top, greaterThan(l.nodeById('B')!.rect.top));
    });

    test('a cycle still lays out instead of refusing', () {
      final l = layout('flowchart TD\n A --> B\n B --> C\n C --> A');

      expect(l.nodes, hasLength(3));
      expect(l.size.width, greaterThan(0));
      expect(l.size.height, greaterThan(0));
    });
  });

  group('direction', () {
    test('LR ranks along x, TD ranks along y', () {
      final td = layout('flowchart TD\n A --> B');
      final lr = layout('flowchart LR\n A --> B');

      expect(
        td.nodeById('B')!.rect.top,
        greaterThan(td.nodeById('A')!.rect.top),
      );
      expect(
        td.nodeById('B')!.rect.left,
        closeTo(td.nodeById('A')!.rect.left, 40),
      );

      expect(
        lr.nodeById('B')!.rect.left,
        greaterThan(lr.nodeById('A')!.rect.left),
      );
    });

    test('BT is TD mirrored, RL is LR mirrored', () {
      final bt = layout('flowchart BT\n A --> B');
      expect(bt.nodeById('B')!.rect.top, lessThan(bt.nodeById('A')!.rect.top));

      final rl = layout('flowchart RL\n A --> B');
      expect(
        rl.nodeById('B')!.rect.left,
        lessThan(rl.nodeById('A')!.rect.left),
      );
    });
  });

  group('ordering reduces crossings', () {
    test('a diagram with an obvious crossing is untangled', () {
      // Written so the naive (declaration) order crosses: A->D and B->C.
      final l = layout('flowchart TD\n A --> D\n B --> C');

      expect(l.crossings, 0, reason: 'the barycentre sweep should untangle it');
    });

    test('the fixture diagram lays out with no crossings', () {
      const src = '''
flowchart TD
    A[Paylaşılan metin] --> B{AI yapılandırılmış mı?}
    B -->|evet| C[Bubble + onay kartı]
    B -->|hayır| D[Inbox'a kaydet]
    D --> E([Sebebi söyleyen diyalog])
    C --> F[Görev]
    E --> F
''';
      final l = layout(src);

      expect(l.nodes, hasLength(6));
      expect(l.crossings, 0);
      // The two branches must actually be side by side, not stacked.
      expect(
        l.nodeById('C')!.rect.left,
        isNot(closeTo(l.nodeById('D')!.rect.left, 1)),
      );
    });

    test('layout is deterministic — same input, identical coordinates', () {
      const src = 'flowchart TD\n A --> B\n A --> C\n B --> D\n C --> D';
      final first = layout(src);
      final second = layout(src);

      for (final node in first.nodes) {
        expect(second.nodeById(node.id)!.rect, node.rect);
      }
    });
  });

  group('geometry', () {
    test('nodes never overlap', () {
      final l = layout(
        'flowchart TD\n A --> B\n A --> C\n A --> D\n B --> E\n C --> E',
      );

      for (var i = 0; i < l.nodes.length; i++) {
        for (var j = i + 1; j < l.nodes.length; j++) {
          expect(
            l.nodes[i].rect.overlaps(l.nodes[j].rect),
            isFalse,
            reason: '${l.nodes[i].id} overlaps ${l.nodes[j].id}',
          );
        }
      }
    });

    test('every node sits inside the reported size', () {
      final l = layout('flowchart LR\n A[uzunca bir etiket] --> B{karar}');

      for (final node in l.nodes) {
        expect(node.rect.left, greaterThanOrEqualTo(0));
        expect(node.rect.top, greaterThanOrEqualTo(0));
        expect(node.rect.right, lessThanOrEqualTo(l.size.width));
        expect(node.rect.bottom, lessThanOrEqualTo(l.size.height));
      }
    });

    test('a diamond is roomier than a rect with the same label', () {
      final l = layout('flowchart TD\n A[karar] --> B{karar}');

      expect(
        l.nodeById('B')!.rect.width,
        greaterThan(l.nodeById('A')!.rect.width),
      );
    });

    test('edges start and end ON the boxes, not at their centres', () {
      final l = layout('flowchart TD\n A --> B');
      final edge = l.edges.single;
      final a = l.nodeById('A')!.rect, b = l.nodeById('B')!.rect;

      expect(a.center, isNot(edge.points.first));
      // Touching the border, within a rounding hair.
      expect((edge.points.first.dy - a.bottom).abs(), lessThan(1));
      expect((edge.points.last.dy - b.top).abs(), lessThan(1));
    });

    test('an edge label is carried through to an anchor', () {
      final l = layout('flowchart TD\n A -->|evet| B');

      expect(l.edges.single.label, 'evet');
      expect(l.edges.single.labelAnchor, isNotNull);
    });

    test('a self-loop routes out and back instead of vanishing', () {
      final l = layout('flowchart TD\n A --> A');

      expect(l.edges, hasLength(1));
      expect(l.edges.single.points.length, greaterThan(2));
    });

    test('an edge spanning two ranks routes AROUND what sits between', () {
      // The fixture's shape: C --> F jumps a rank, and E lives on the rank in
      // between. Drawn as a straight line the edge crosses E's box, so the
      // picture claims an arrow the document never wrote.
      const src = '''
flowchart TD
    A --> B
    B --> C
    B --> D
    D --> E
    C --> F
    E --> F
''';
      final l = layout(src);

      // The claim is not "the edge has N points" — one skipped rank means one
      // waypoint, so counting is a brittle proxy. The claim is geometric: no
      // edge may pass through a node that is not one of its own ends.
      for (final edge in l.edges) {
        for (final node in l.nodes) {
          final isEnd =
              node.rect.inflate(2).contains(edge.points.first) ||
              node.rect.inflate(2).contains(edge.points.last);
          if (isEnd) continue;
          expect(
            _crosses(edge.points, node.rect.deflate(2)),
            isFalse,
            reason: 'an edge runs straight through ${node.id}',
          );
        }
      }
    });
  });

  group('sequence diagram', () {
    SequenceLayout seq(String src) =>
        layoutSequence(parseMermaid(src) as MermaidSequence, measure: measure);

    test('participants become columns in declaration order', () {
      final l = seq(
        'sequenceDiagram\n'
        '  participant U as Uzantı\n'
        '  participant G as App Group\n'
        '  participant A as Uygulama\n'
        '  U->>G: bir\n',
      );

      final xs = l.participants.map((p) => p.lifelineX).toList();
      expect(l.participants.map((p) => p.id), ['U', 'G', 'A']);
      expect(xs[0], lessThan(xs[1]));
      expect(xs[1], lessThan(xs[2]));
    });

    test('messages stack downward and land on their lifelines', () {
      final l = seq('sequenceDiagram\n A->>B: bir\n B-->>A: iki\n');

      expect(l.messages, hasLength(2));
      expect(
        l.messages[1].points.first.dy,
        greaterThan(l.messages[0].points.first.dy),
      );

      final a = l.byId('A')!, b = l.byId('B')!;
      expect(l.messages[0].points.first.dx, a.lifelineX);
      expect(l.messages[0].points.last.dx, b.lifelineX);
      // The reply comes back the other way.
      expect(l.messages[1].points.first.dx, b.lifelineX);
    });

    test('a self-message loops instead of collapsing to a point', () {
      final l = seq('sequenceDiagram\n A->>A: kendine\n');
      final m = l.messages.single;

      expect(m.isSelf, isTrue);
      expect(m.points, hasLength(4));
      // It has to occupy real width, or the caption would sit on the lifeline.
      expect(m.points[1].dx, greaterThan(m.points[0].dx));
    });

    test('a long self-message caption widens its own column', () {
      final narrow = seq('sequenceDiagram\n A->>A: kısa\n');
      final wide = seq(
        'sequenceDiagram\n A->>A: epeyce uzun bir mesaj metni burada\n B->>B: x\n',
      );

      expect(wide.size.width, greaterThan(narrow.size.width));
    });

    test('lifelines run past the last message', () {
      final l = seq('sequenceDiagram\n A->>B: bir\n');

      expect(
        l.participants.first.lifelineBottom,
        greaterThan(l.messages.single.points.first.dy),
      );
      expect(
        l.size.height,
        greaterThanOrEqualTo(l.participants.first.lifelineBottom),
      );
    });

    test('layout is deterministic', () {
      const src = 'sequenceDiagram\n A->>B: bir\n B->>C: iki\n C-->>A: üç\n';
      final first = seq(src), second = seq(src);

      expect(second.size, first.size);
      for (final p in first.participants) {
        expect(second.byId(p.id)!.lifelineX, p.lifelineX);
      }
    });
  });
}

/// Whether the polyline [points] passes through [rect]. Sampled rather than
/// solved: a segment/rectangle intersection is exact but longer than it needs
/// to be for a readability guard.
bool _crosses(List<Offset> points, Rect rect) {
  for (var i = 0; i + 1 < points.length; i++) {
    const steps = 24;
    for (var s = 1; s < steps; s++) {
      final t = s / steps;
      final p = Offset.lerp(points[i], points[i + 1], t)!;
      if (rect.contains(p)) return true;
    }
  }
  return false;
}
