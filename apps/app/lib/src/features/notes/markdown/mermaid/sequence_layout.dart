/// Sequence-diagram layout (OPH-254, ADR-0028 §4).
///
/// Participants are columns, messages are rows. That is the whole algorithm,
/// and it is exactly why ADR-0028 drew the v1 line here and not one diagram
/// type further: this is arithmetic, while a flowchart is graph drawing.
///
/// Pure Dart, same as `flow_layout.dart`, with measurement injected — the
/// coordinates are asserted directly in tests.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'flow_layout.dart' show MermaidMeasure;
import 'mermaid_parse.dart';

const double kSeqHeaderPadH = 14;
const double kSeqHeaderPadV = 8;
const double kSeqColumnGap = 40;
const double kSeqMinColumn = 90;
const double kSeqRowGap = 44;
const double kSeqSelfLoopHeight = 34;
const double kSeqMargin = 12;
const double kSeqLifelineTail = 20;

class SeqParticipantBox {
  const SeqParticipantBox({
    required this.id,
    required this.label,
    required this.header,
    required this.lifelineX,
    required this.lifelineBottom,
  });

  final String id;
  final String label;
  final Rect header;
  final double lifelineX;
  final double lifelineBottom;
}

class SeqMessageLine {
  const SeqMessageLine({
    required this.points,
    required this.text,
    required this.dotted,
    required this.arrow,
    required this.textAnchor,
    required this.isSelf,
  });

  final List<Offset> points;
  final String text;
  final bool dotted;
  final bool arrow;

  /// Where the caption sits — above the line for a normal message, to the
  /// right of the loop for a self-message.
  final Offset textAnchor;
  final bool isSelf;
}

class SequenceLayout {
  const SequenceLayout({
    required this.participants,
    required this.messages,
    required this.size,
  });

  final List<SeqParticipantBox> participants;
  final List<SeqMessageLine> messages;
  final Size size;

  SeqParticipantBox? byId(String id) {
    for (final p in participants) {
      if (p.id == id) return p;
    }
    return null;
  }
}

SequenceLayout layoutSequence(
  MermaidSequence seq, {
  required MermaidMeasure measure,
}) {
  if (seq.participants.isEmpty) {
    return const SequenceLayout(
      participants: [],
      messages: [],
      size: Size.zero,
    );
  }

  // Columns are as wide as the widest thing they must hold: the header, or a
  // self-message caption that would otherwise run into the next lifeline.
  final headerSizes = <String, Size>{};
  final columnWidths = <String, double>{};
  for (final p in seq.participants) {
    final text = measure(p.label);
    final header = Size(
      text.width + kSeqHeaderPadH * 2,
      text.height + kSeqHeaderPadV * 2,
    );
    headerSizes[p.id] = header;
    columnWidths[p.id] = math.max(header.width, kSeqMinColumn);
  }
  for (final m in seq.messages) {
    if (!m.isSelf) continue;
    final caption = measure(m.text).width + kSeqSelfLoopHeight + 24;
    columnWidths[m.from] = math.max(columnWidths[m.from] ?? 0, caption);
  }

  final headerHeight = headerSizes.values.fold<double>(
    0,
    (a, s) => math.max(a, s.height),
  );

  // Place the columns.
  final centres = <String, double>{};
  var x = kSeqMargin;
  for (final p in seq.participants) {
    final width = columnWidths[p.id]!;
    centres[p.id] = x + width / 2;
    x += width + kSeqColumnGap;
  }
  final totalWidth = x - kSeqColumnGap + kSeqMargin;

  // Then the rows.
  final lines = <SeqMessageLine>[];
  var y = kSeqMargin + headerHeight + kSeqRowGap;
  for (final m in seq.messages) {
    final fromX = centres[m.from];
    final toX = centres[m.to];
    if (fromX == null || toX == null) continue;

    if (m.isSelf) {
      // Out to the right, down, and back — the shape every sequence renderer
      // uses, because a message to yourself has no horizontal distance to
      // travel.
      final points = [
        Offset(fromX, y),
        Offset(fromX + kSeqSelfLoopHeight, y),
        Offset(fromX + kSeqSelfLoopHeight, y + kSeqSelfLoopHeight),
        Offset(fromX, y + kSeqSelfLoopHeight),
      ];
      lines.add(
        SeqMessageLine(
          points: points,
          text: m.text,
          dotted: m.dotted,
          arrow: m.arrow,
          textAnchor: Offset(fromX + kSeqSelfLoopHeight + 8, y + 4),
          isSelf: true,
        ),
      );
      y += kSeqSelfLoopHeight + kSeqRowGap;
      continue;
    }

    lines.add(
      SeqMessageLine(
        points: [Offset(fromX, y), Offset(toX, y)],
        text: m.text,
        dotted: m.dotted,
        arrow: m.arrow,
        // Captions sit ABOVE the line: below, they collide with the next
        // message on a dense diagram.
        textAnchor: Offset((fromX + toX) / 2, y - 6),
        isSelf: false,
      ),
    );
    y += kSeqRowGap;
  }

  final lifelineBottom = y - kSeqRowGap + kSeqLifelineTail;
  final boxes = <SeqParticipantBox>[
    for (final p in seq.participants)
      SeqParticipantBox(
        id: p.id,
        label: p.label,
        header: Rect.fromCenter(
          center: Offset(centres[p.id]!, kSeqMargin + headerHeight / 2),
          width: headerSizes[p.id]!.width,
          height: headerHeight,
        ),
        lifelineX: centres[p.id]!,
        lifelineBottom: lifelineBottom,
      ),
  ];

  return SequenceLayout(
    participants: boxes,
    messages: lines,
    size: Size(totalWidth, lifelineBottom + kSeqMargin),
  );
}
