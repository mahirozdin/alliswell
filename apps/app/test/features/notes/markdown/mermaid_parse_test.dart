import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/notes/markdown/mermaid/mermaid_parse.dart';

/// OPH-254 — the mermaid subset (ADR-0028 §4).
void main() {
  group('flowchart', () {
    test('reads the fixture diagram: shapes, labelled edges, a join', () {
      const src = '''
flowchart TD
    A[Paylaşılan metin] --> B{AI yapılandırılmış mı?}
    B -->|evet| C[Bubble + onay kartı]
    B -->|hayır| D[Inbox'a kaydet]
    D --> E([Sebebi söyleyen diyalog])
    C --> F[Görev]
    E --> F
''';
      final flow = parseMermaid(src) as MermaidFlow;

      expect(flow.direction, MermaidDirection.topDown);
      expect(flow.nodes.map((n) => n.id), ['A', 'B', 'C', 'D', 'E', 'F']);
      expect(flow.nodeById('B')!.shape, MermaidShape.diamond);
      expect(flow.nodeById('E')!.shape, MermaidShape.stadium);
      expect(flow.nodeById('A')!.label, 'Paylaşılan metin');

      expect(flow.edges, hasLength(6));
      final labelled = flow.edges.where((e) => e.label != null).toList();
      expect(labelled.map((e) => e.label), ['evet', 'hayır']);
      // F is reached from two places — the join is what makes the layout
      // interesting, so it must survive parsing.
      expect(flow.edges.where((e) => e.to == 'F'), hasLength(2));
    });

    test('every direction token, and TB is TD', () {
      MermaidDirection dir(String d) =>
          (parseMermaid('flowchart $d\n  A --> B') as MermaidFlow).direction;

      expect(dir('TD'), MermaidDirection.topDown);
      expect(dir('TB'), MermaidDirection.topDown);
      expect(dir('LR'), MermaidDirection.leftRight);
      expect(dir('RL'), MermaidDirection.rightLeft);
      expect(dir('BT'), MermaidDirection.bottomUp);
    });

    test('`graph` is the same language as `flowchart`', () {
      expect(parseMermaid('graph LR\n  A --> B'), isA<MermaidFlow>());
    });

    test('edge operators carry their style and their arrowhead', () {
      final flow =
          parseMermaid('flowchart LR\n A --> B\n B --- C\n C -.-> D\n D ==> E')
              as MermaidFlow;

      expect(flow.edges[0].style, MermaidEdgeStyle.solid);
      expect(flow.edges[0].arrow, isTrue);
      expect(flow.edges[1].arrow, isFalse, reason: '--- has no arrowhead');
      expect(flow.edges[2].style, MermaidEdgeStyle.dotted);
      expect(flow.edges[3].style, MermaidEdgeStyle.thick);
    });

    test('a chain on one line becomes one edge per hop', () {
      final flow = parseMermaid('flowchart LR\n  A --> B --> C') as MermaidFlow;

      expect(flow.edges.map((e) => '${e.from}${e.to}'), ['AB', 'BC']);
    });

    test('a bare mention never erases a label given elsewhere', () {
      final flow =
          parseMermaid('flowchart TD\n A[Uzun ad] --> B\n A --> C')
              as MermaidFlow;

      expect(flow.nodeById('A')!.label, 'Uzun ad');
    });

    test('statements we do not model are skipped, not fatal', () {
      final flow =
          parseMermaid(
                'flowchart TD\n'
                '  %% yorum\n'
                '  subgraph one\n'
                '  A --> B\n'
                '  end\n'
                '  style A fill:#f00\n',
              )
              as MermaidFlow;

      expect(flow.edges, hasLength(1));
    });
  });

  group('sequenceDiagram', () {
    test('reads the fixture diagram, including a self-message', () {
      const src = '''
sequenceDiagram
    participant U as Uzantı
    participant G as App Group
    participant A as Uygulama
    U->>G: didSelectPost() payload yazar
    U-->>A: yerel bildirim (metin YOK)
    A->>G: her resume'da oku
    G-->>A: payload
    A->>A: oku-ve-sil
''';
      final seq = parseMermaid(src) as MermaidSequence;

      expect(seq.participants.map((p) => p.id), ['U', 'G', 'A']);
      expect(seq.participants.first.label, 'Uzantı');
      expect(seq.messages, hasLength(5));
      expect(seq.messages[1].dotted, isTrue, reason: '-->> is the reply form');
      expect(seq.messages.last.isSelf, isTrue);
    });

    test('a participant mentioned only in a message still gets a column', () {
      final seq =
          parseMermaid('sequenceDiagram\n  A->>B: merhaba') as MermaidSequence;

      expect(seq.participants.map((p) => p.id), ['A', 'B']);
      expect(seq.participants.first.label, 'A', reason: 'id doubles as label');
    });

    test('blocks we do not model yet are skipped', () {
      final seq =
          parseMermaid(
                'sequenceDiagram\n'
                '  autonumber\n'
                '  A->>B: bir\n'
                '  activate B\n'
                '  Note right of B: not\n'
                '  loop her gün\n'
                '  B-->>A: iki\n'
                '  end\n',
              )
              as MermaidSequence;

      expect(seq.messages, hasLength(2));
    });
  });

  group('declining and failing are different answers (D11)', () {
    test('a known type we do not draw names ITSELF', () {
      final result = parseMermaid(
        'gantt\n  title Bu tip v1\'de çizilmiyor\n  section Epic 24\n',
      );

      expect(result, isA<MermaidUnsupported>());
      // Naming the type is the point: the reader learns WHICH of their
      // diagrams is affected, not that "a diagram" went missing.
      expect((result as MermaidUnsupported).type, 'gantt');
    });

    for (final type in ['pie', 'classDiagram', 'stateDiagram-v2', 'journey']) {
      test('$type is declined, not failed', () {
        expect(parseMermaid('$type\n  x\n'), isA<MermaidUnsupported>());
      });
    }

    test('the fixture\'s broken flowchart FAILS rather than declining', () {
      // An unclosed bracket: this is a diagram we should have been able to
      // read. Reporting it as "not supported yet" would send the reader to
      // wait for a feature instead of fixing their line.
      const src = '''
flowchart TD
    A[Kapanmamış köşeli parantez --> B
    B -->
''';
      expect(parseMermaid(src), isA<MermaidParseError>());
    });

    test('an empty fence fails', () {
      expect(parseMermaid('   \n\n'), isA<MermaidParseError>());
    });

    test('a keyword nobody recognises fails rather than pretending', () {
      expect(parseMermaid('kediDiagram\n A --> B'), isA<MermaidParseError>());
    });
  });
}
