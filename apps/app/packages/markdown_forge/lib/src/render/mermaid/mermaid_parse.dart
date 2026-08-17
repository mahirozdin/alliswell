/// A mermaid subset, parsed into a typed graph (OPH-254, ADR-0028 §4).
///
/// **Two diagram types are drawn: `flowchart`/`graph` and `sequenceDiagram`.**
/// Everything else — class, state, ER, gantt, pie, journey — is recognised and
/// declined, because the costs differ by an order of magnitude: a sequence
/// diagram is participants-as-columns and messages-as-rows, essentially linear,
/// while a flowchart is a layered graph-drawing problem.
///
/// No parser extension was needed to get here: mermaid arrives as a fenced code
/// block with a `mermaid` info string, which the OPH-246 coverage measurement
/// confirmed already reaches us. This is render-time work.
///
/// **Declining and failing are different answers**, and D11 makes that a rule:
/// "this diagram type is not drawn yet" sends the reader somewhere different
/// from "this diagram could not be read". [MermaidUnsupported] and
/// [MermaidParseError] exist so the view can say the right one.
library;

/// Which way a flowchart grows.
enum MermaidDirection {
  /// Top → bottom. `TD` and `TB` are the same thing in mermaid.
  topDown,
  bottomUp,
  leftRight,
  rightLeft;

  bool get isVertical =>
      this == MermaidDirection.topDown || this == MermaidDirection.bottomUp;
}

/// Node outlines mermaid spells with bracket pairs.
enum MermaidShape {
  /// `A[text]`
  rect,

  /// `A(text)`
  round,

  /// `A([text])`
  stadium,

  /// `A{text}`
  diamond,

  /// `A((text))`
  circle,
}

/// How an edge is drawn.
enum MermaidEdgeStyle { solid, dotted, thick }

class MermaidNode {
  const MermaidNode({
    required this.id,
    required this.label,
    required this.shape,
  });

  final String id;
  final String label;
  final MermaidShape shape;
}

class MermaidEdge {
  const MermaidEdge({
    required this.from,
    required this.to,
    this.label,
    this.style = MermaidEdgeStyle.solid,
    this.arrow = true,
  });

  final String from;
  final String to;
  final String? label;
  final MermaidEdgeStyle style;

  /// `---` joins without an arrowhead; `-->` points.
  final bool arrow;
}

class MermaidParticipant {
  const MermaidParticipant({required this.id, required this.label});

  final String id;
  final String label;
}

class MermaidMessage {
  const MermaidMessage({
    required this.from,
    required this.to,
    required this.text,
    this.dotted = false,
    this.arrow = true,
  });

  final String from;
  final String to;
  final String text;

  /// `-->>` is the reply/return form.
  final bool dotted;
  final bool arrow;

  bool get isSelf => from == to;
}

sealed class MermaidDiagram {
  const MermaidDiagram();
}

class MermaidFlow extends MermaidDiagram {
  const MermaidFlow({
    required this.direction,
    required this.nodes,
    required this.edges,
  });

  final MermaidDirection direction;

  /// Declaration order — which is also the order a reader wrote them in, and
  /// therefore the tie-break the layout uses when nothing else decides.
  final List<MermaidNode> nodes;
  final List<MermaidEdge> edges;

  MermaidNode? nodeById(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }
}

class MermaidSequence extends MermaidDiagram {
  const MermaidSequence({required this.participants, required this.messages});

  final List<MermaidParticipant> participants;
  final List<MermaidMessage> messages;
}

/// A diagram type we recognise and deliberately do not draw.
class MermaidUnsupported extends MermaidDiagram {
  const MermaidUnsupported(this.type);

  /// The keyword as written, e.g. `gantt` — the view names it, so the reader
  /// learns which of their diagrams is affected rather than that "a diagram"
  /// is missing.
  final String type;
}

/// A diagram we should have been able to read and could not.
class MermaidParseError extends MermaidDiagram {
  const MermaidParseError(this.reason);

  final String reason;
}

/// Diagram keywords mermaid supports that we knowingly decline.
const Set<String> kMermaidKnownTypes = {
  'classdiagram',
  'statediagram',
  'statediagram-v2',
  'erdiagram',
  'gantt',
  'pie',
  'journey',
  'gitgraph',
  'mindmap',
  'timeline',
  'quadrantchart',
  'requirementdiagram',
  'c4context',
  'sankey-beta',
  'xychart-beta',
  'block-beta',
};

/// Parses [source] — the body of a ```` ```mermaid ```` fence.
MermaidDiagram parseMermaid(String source) {
  final lines = _meaningfulLines(source);
  if (lines.isEmpty) return const MermaidParseError('empty');

  final header = lines.first.trim();
  final keyword = header.split(RegExp(r'\s+')).first.toLowerCase();

  if (keyword == 'flowchart' || keyword == 'graph') {
    return _parseFlow(header, lines.skip(1));
  }
  if (keyword == 'sequencediagram') {
    return _parseSequence(lines.skip(1));
  }
  if (kMermaidKnownTypes.contains(keyword)) {
    return MermaidUnsupported(header.split(RegExp(r'\s+')).first);
  }
  return const MermaidParseError('unknown-type');
}

/// Strips comments and blank lines. `%%` is mermaid's comment marker.
List<String> _meaningfulLines(String source) => [
  for (final raw in source.split('\n'))
    if (raw.trim().isNotEmpty && !raw.trimLeft().startsWith('%%')) raw,
];

// ── flowchart ───────────────────────────────────────────────────────────────

MermaidDirection _direction(String header) {
  final parts = header.split(RegExp(r'\s+'));
  final token = parts.length > 1 ? parts[1].toUpperCase() : 'TD';
  return switch (token) {
    'BT' => MermaidDirection.bottomUp,
    'LR' => MermaidDirection.leftRight,
    'RL' => MermaidDirection.rightLeft,
    // TD and TB are the same direction; anything unrecognised reads as the
    // default rather than failing the whole diagram over one token.
    _ => MermaidDirection.topDown,
  };
}

/// `A`, `A[text]`, `A(text)`, `A([text])`, `A{text}`, `A((text))`.
final _nodeRe = RegExp(
  r'^([A-Za-z0-9_-]+)'
  r'(?:'
  r'\(\((.*?)\)\)' // ((circle))
  r'|\(\[(.*?)\]\)' // ([stadium])
  r'|\[(.*?)\]' // [rect]
  r'|\((.*?)\)' // (round)
  r'|\{(.*?)\}' // {diamond}
  r')?$',
);

/// `-->`, `---`, `-.->`, `==>`, each optionally carrying `|label|`.
final _edgeRe = RegExp(r'(-\.->|-\.-|==>|===|-->|---)(?:\|(.*?)\|)?');

MermaidDiagram _parseFlow(String header, Iterable<String> body) {
  final nodes = <String, MermaidNode>{};
  final order = <String>[];
  final edges = <MermaidEdge>[];

  MermaidNode? define(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final m = _nodeRe.firstMatch(text);
    if (m == null) return null;

    final id = m.group(1)!;
    final label =
        m.group(2) ?? m.group(3) ?? m.group(4) ?? m.group(5) ?? m.group(6);
    final shape = switch (m) {
      _ when m.group(2) != null => MermaidShape.circle,
      _ when m.group(3) != null => MermaidShape.stadium,
      _ when m.group(4) != null => MermaidShape.rect,
      _ when m.group(5) != null => MermaidShape.round,
      _ when m.group(6) != null => MermaidShape.diamond,
      _ => MermaidShape.rect,
    };

    final existing = nodes[id];
    // A node may appear several times; the FIRST time it carries a label wins,
    // and a bare mention never erases one.
    if (existing != null) {
      if (existing.label.isEmpty && label != null && label.isNotEmpty) {
        nodes[id] = MermaidNode(id: id, label: label, shape: shape);
      }
      return nodes[id];
    }
    order.add(id);
    return nodes[id] = MermaidNode(
      id: id,
      label: (label ?? id).trim(),
      shape: shape,
    );
  }

  for (final line in body) {
    final text = line.trim();
    if (text.isEmpty) continue;
    // Statements we do not model are skipped, not fatal: a `subgraph` or a
    // `style` line should cost its own feature, never the whole picture.
    final lower = text.toLowerCase();
    if (lower.startsWith('subgraph') ||
        lower == 'end' ||
        lower.startsWith('style ') ||
        lower.startsWith('classdef') ||
        lower.startsWith('class ') ||
        lower.startsWith('click ') ||
        lower.startsWith('linkstyle')) {
      continue;
    }

    final matches = _edgeRe.allMatches(text).toList();
    if (matches.isEmpty) {
      if (define(text) == null) {
        return MermaidParseError('bad-node: $text');
      }
      continue;
    }

    // `A --> B --> C` is a chain; each hop is an edge.
    var cursor = 0;
    String? previous;
    for (final m in matches) {
      final left = text.substring(cursor, m.start);
      final node = define(left);
      final fromId = node?.id ?? previous;
      if (fromId == null) return MermaidParseError('bad-edge: $text');

      final rest = text.substring(m.end);
      final nextEnd = matches
          .where((o) => o.start > m.start)
          .map((o) => o.start)
          .fold<int?>(null, (a, b) => a ?? b);
      final rightText = nextEnd == null ? rest : text.substring(m.end, nextEnd);
      final target = define(rightText);
      if (target == null) return MermaidParseError('bad-edge: $text');

      final op = m.group(1)!;
      edges.add(
        MermaidEdge(
          from: fromId,
          to: target.id,
          label: m.group(2)?.trim(),
          style: op.startsWith('-.')
              ? MermaidEdgeStyle.dotted
              : op.startsWith('=')
              ? MermaidEdgeStyle.thick
              : MermaidEdgeStyle.solid,
          arrow: op.endsWith('>'),
        ),
      );
      previous = target.id;
      cursor = m.end;
    }
  }

  if (nodes.isEmpty) return const MermaidParseError('no-nodes');
  return MermaidFlow(
    direction: _direction(header),
    nodes: [for (final id in order) nodes[id]!],
    edges: edges,
  );
}

// ── sequence ────────────────────────────────────────────────────────────────

final _participantRe = RegExp(
  r'^(?:participant|actor)\s+([A-Za-z0-9_-]+)(?:\s+as\s+(.*))?$',
  caseSensitive: false,
);

/// Ids here exclude `-`, unlike the `participant` line.
///
/// Not an oversight: with `-` in the class, `U-->>A: metin` matches `U-` as the
/// sender and `->>` as the operator, and the diagram silently grows a
/// participant called `U-`. Mermaid's own grammar has the same ambiguity and
/// resolves it the same way. A participant whose id really contains a hyphen
/// can still be DECLARED; only messages need the plainer id.
final _messageRe = RegExp(
  r'^([A-Za-z0-9_]+)\s*(-->>|->>|-->|->|--x|-x)\s*'
  r'([A-Za-z0-9_]+)\s*:\s*(.*)$',
);

MermaidDiagram _parseSequence(Iterable<String> body) {
  final participants = <String, MermaidParticipant>{};
  final order = <String>[];
  final messages = <MermaidMessage>[];

  void ensure(String id, [String? label]) {
    if (participants.containsKey(id)) {
      if (label != null && label.isNotEmpty) {
        participants[id] = MermaidParticipant(id: id, label: label);
      }
      return;
    }
    order.add(id);
    participants[id] = MermaidParticipant(id: id, label: label ?? id);
  }

  for (final line in body) {
    final text = line.trim();
    if (text.isEmpty) continue;

    final p = _participantRe.firstMatch(text);
    if (p != null) {
      ensure(p.group(1)!, p.group(2)?.trim());
      continue;
    }

    final m = _messageRe.firstMatch(text);
    if (m != null) {
      final from = m.group(1)!;
      final to = m.group(3)!;
      ensure(from);
      ensure(to);
      final op = m.group(2)!;
      messages.add(
        MermaidMessage(
          from: from,
          to: to,
          text: m.group(4)!.trim(),
          dotted: op.startsWith('--'),
          arrow: op.endsWith('>') || op.endsWith('x'),
        ),
      );
      continue;
    }

    // Blocks we do not model yet (`activate`, `note`, `loop`, `alt`, `end`)
    // are skipped rather than fatal — same reasoning as the flowchart.
    final lower = text.toLowerCase();
    if (lower.startsWith('activate') ||
        lower.startsWith('deactivate') ||
        lower.startsWith('note ') ||
        lower.startsWith('loop') ||
        lower.startsWith('alt') ||
        lower.startsWith('else') ||
        lower.startsWith('opt') ||
        lower.startsWith('par') ||
        lower.startsWith('autonumber') ||
        lower == 'end') {
      continue;
    }
    return MermaidParseError('bad-line: $text');
  }

  if (participants.isEmpty) return const MermaidParseError('no-participants');
  return MermaidSequence(
    participants: [for (final id in order) participants[id]!],
    messages: messages,
  );
}
