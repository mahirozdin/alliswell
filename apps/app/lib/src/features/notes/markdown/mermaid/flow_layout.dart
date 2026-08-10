/// Layered layout for a flowchart (OPH-254, ADR-0028 §4).
///
/// The classic Sugiyama pipeline, in the classic four steps:
///   1. **rank** — longest path from the sources, so every edge points forward;
///   2. **order** — barycentre sweeps within each rank, to reduce crossings;
///   3. **coordinates** — pack each rank, then centre it;
///   4. **route** — an exit point, a curve, an entry point.
///
/// ADR-0028 put this in its own task precisely because it is this: a flowchart
/// is a graph-drawing problem, while a sequence diagram is columns and rows.
///
/// **Pure Dart with no widgets**, and text measurement arrives through
/// [MermaidMeasure]. That is what makes the coordinates unit-testable: a test
/// injects a fixed-size measurer and asserts exact positions and an exact
/// crossing count, instead of eyeballing a golden.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'mermaid_parse.dart';

/// How wide and tall a node's label renders.
typedef MermaidMeasure = Size Function(String label);

/// Spacing constants. Named because a diagram that reads well is mostly about
/// these six numbers.
const double kFlowNodePadH = 14;
const double kFlowNodePadV = 10;
const double kFlowMinNodeWidth = 48;
const double kFlowRankGap = 56;
const double kFlowNodeGap = 28;
const double kFlowMargin = 12;

class FlowNodeBox {
  const FlowNodeBox({
    required this.id,
    required this.label,
    required this.shape,
    required this.rect,
  });

  final String id;
  final String label;
  final MermaidShape shape;
  final Rect rect;
}

class FlowEdgePath {
  const FlowEdgePath({
    required this.points,
    required this.style,
    required this.arrow,
    this.label,
    this.labelAnchor,
  });

  /// Start, optional control points, end — the painter draws a smooth path
  /// through them.
  final List<Offset> points;
  final MermaidEdgeStyle style;
  final bool arrow;
  final String? label;
  final Offset? labelAnchor;
}

class FlowLayout {
  const FlowLayout({
    required this.nodes,
    required this.edges,
    required this.size,
    required this.crossings,
  });

  final List<FlowNodeBox> nodes;
  final List<FlowEdgePath> edges;
  final Size size;

  /// Edge crossings left after ordering. Exposed so a test can assert the
  /// heuristic actually did something — "it laid out" is not the same claim as
  /// "it laid out readably".
  final int crossings;

  FlowNodeBox? nodeById(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }
}

FlowLayout layoutFlowchart(
  MermaidFlow flow, {
  required MermaidMeasure measure,
}) {
  final sizes = <String, Size>{
    for (final node in flow.nodes) node.id: _nodeSize(node, measure),
  };

  final ranks = _assignRanks(flow);

  // Sugiyama's third step, and the one it is tempting to skip: an edge that
  // spans more than one rank gets a VIRTUAL node on each rank in between.
  //
  // Skipping it was measured, not theorised. The fixture's `C --> F` jumps two
  // ranks, and without chaining it was drawn as a straight line right across
  // the node sitting between them — so the picture said "C goes to E", which
  // is not what the document says. A diagram that draws the wrong arrows is
  // worse than one that declines to draw.
  final chains = _chainSpanningEdges(flow, ranks, sizes);
  final layers = _layers(flow, ranks, chains.virtualRanks);
  final crossings = _order(flow, layers, chains.adjacency);

  final positions = _positions(flow, layers, sizes);
  final bounds = _bounds(positions, sizes, flow);

  final boxes = <FlowNodeBox>[
    for (final node in flow.nodes)
      FlowNodeBox(
        id: node.id,
        label: node.label,
        shape: node.shape,
        rect: Rect.fromLTWH(
          positions[node.id]!.dx - bounds.left,
          positions[node.id]!.dy - bounds.top,
          sizes[node.id]!.width,
          sizes[node.id]!.height,
        ),
      ),
  ];

  final byId = {for (final b in boxes) b.id: b};
  final waypoints = <String, Offset>{
    for (final id in chains.virtualRanks.keys)
      if (positions[id] != null)
        id: Offset(
          positions[id]!.dx - bounds.left,
          positions[id]!.dy - bounds.top,
        ),
  };

  final paths = <FlowEdgePath>[
    for (var i = 0; i < flow.edges.length; i++)
      if (byId[flow.edges[i].from] != null && byId[flow.edges[i].to] != null)
        _route(
          flow.edges[i],
          byId[flow.edges[i].from]!,
          byId[flow.edges[i].to]!,
          [
            for (final id in chains.edgeChains[i] ?? const <String>[])
              if (waypoints[id] != null) waypoints[id]!,
          ],
        ),
  ];

  return FlowLayout(
    nodes: boxes,
    edges: paths,
    size: Size(bounds.width, bounds.height),
    crossings: crossings,
  );
}

// ── 1. rank ─────────────────────────────────────────────────────────────────

/// Longest path from every source, with back edges ignored.
///
/// A cycle has no "correct" ranking, and refusing to draw one would be a worse
/// answer than drawing it with the back edge pointing uphill — mermaid itself
/// draws cycles.
Map<String, int> _assignRanks(MermaidFlow flow) {
  final outgoing = <String, List<String>>{};
  final indegree = <String, int>{for (final n in flow.nodes) n.id: 0};
  for (final e in flow.edges) {
    if (e.from == e.to) continue;
    outgoing.putIfAbsent(e.from, () => []).add(e.to);
    indegree[e.to] = (indegree[e.to] ?? 0) + 1;
  }

  final rank = <String, int>{for (final n in flow.nodes) n.id: 0};
  // Kahn's order gives longest-path ranks in one pass over a DAG; nodes left
  // over are exactly the ones on cycles, and they keep the rank their first
  // reachable predecessor implied.
  final queue = <String>[
    for (final n in flow.nodes)
      if ((indegree[n.id] ?? 0) == 0) n.id,
  ];
  final seen = <String>{...queue};
  final remaining = Map<String, int>.from(indegree);

  var head = 0;
  while (head < queue.length) {
    final id = queue[head++];
    for (final next in outgoing[id] ?? const <String>[]) {
      rank[next] = math.max(rank[next] ?? 0, (rank[id] ?? 0) + 1);
      remaining[next] = (remaining[next] ?? 1) - 1;
      if (remaining[next] == 0 && seen.add(next)) queue.add(next);
    }
  }

  // Anything unvisited sits on a cycle: place it after its highest-ranked
  // predecessor so the picture still flows the right way overall.
  for (final n in flow.nodes) {
    if (seen.contains(n.id)) continue;
    var best = 0;
    for (final e in flow.edges) {
      if (e.to == n.id && seen.contains(e.from)) {
        best = math.max(best, (rank[e.from] ?? 0) + 1);
      }
    }
    rank[n.id] = best;
  }
  return rank;
}

/// The virtual chain for every edge that spans more than one rank.
class _Chains {
  const _Chains({
    required this.virtualRanks,
    required this.edgeChains,
    required this.adjacency,
  });

  /// Virtual node id → the rank it sits on.
  final Map<String, int> virtualRanks;

  /// Edge index → the virtual ids it passes through, in order.
  final Map<int, List<String>> edgeChains;

  /// The graph the ordering step works on: real edges, plus the hop-by-hop
  /// edges of every chain. Ordering has to see the chains or it cannot pull a
  /// long edge out of the way of a node.
  final Map<String, List<String>> adjacency;
}

_Chains _chainSpanningEdges(
  MermaidFlow flow,
  Map<String, int> ranks,
  Map<String, Size> sizes,
) {
  final virtualRanks = <String, int>{};
  final edgeChains = <int, List<String>>{};
  final adjacency = <String, List<String>>{};

  void link(String from, String to) =>
      adjacency.putIfAbsent(from, () => []).add(to);

  for (var i = 0; i < flow.edges.length; i++) {
    final edge = flow.edges[i];
    if (edge.from == edge.to) continue;

    final a = ranks[edge.from], b = ranks[edge.to];
    if (a == null || b == null) continue;
    if ((b - a).abs() <= 1) {
      link(edge.from, edge.to);
      continue;
    }

    final step = b > a ? 1 : -1;
    final chain = <String>[];
    var previous = edge.from;
    for (var rank = a + step; rank != b; rank += step) {
      final id = ' v$i@$rank';
      virtualRanks[id] = rank;
      // Zero-width: a waypoint should steer the edge, never widen the picture.
      sizes[id] = Size.zero;
      chain.add(id);
      link(previous, id);
      previous = id;
    }
    link(previous, edge.to);
    edgeChains[i] = chain;
  }

  return _Chains(
    virtualRanks: virtualRanks,
    edgeChains: edgeChains,
    adjacency: adjacency,
  );
}

List<List<String>> _layers(
  MermaidFlow flow,
  Map<String, int> ranks,
  Map<String, int> virtualRanks,
) {
  final maxRank = [...ranks.values, ...virtualRanks.values].fold(0, math.max);
  final layers = List.generate(maxRank + 1, (_) => <String>[]);
  // Declaration order is the tie-break, so a diagram nobody has arranged still
  // comes out in the order it was written.
  for (final node in flow.nodes) {
    layers[ranks[node.id]!].add(node.id);
  }
  for (final entry in virtualRanks.entries) {
    layers[entry.value].add(entry.key);
  }
  return layers;
}

// ── 2. order ────────────────────────────────────────────────────────────────

/// Barycentre sweeps. Returns the crossing count of the final ordering.
///
/// Works on [adjacency] — the chained graph — not on the raw edge list, so a
/// long edge's waypoints get ordered alongside real nodes and the edge can be
/// pulled clear of whatever sits between its ends.
int _order(
  MermaidFlow flow,
  List<List<String>> layers,
  Map<String, List<String>> adjacency,
) {
  final up = <String, List<String>>{};
  final down = <String, List<String>>{};
  for (final entry in adjacency.entries) {
    for (final to in entry.value) {
      down.putIfAbsent(entry.key, () => []).add(to);
      up.putIfAbsent(to, () => []).add(entry.key);
    }
  }

  var best = _countCrossings(layers, down);
  var bestSnapshot = [for (final l in layers) List<String>.from(l)];

  // Four sweeps: two down, two up. More stops helping on the diagram sizes a
  // document actually contains, and this stays deterministic.
  for (var sweep = 0; sweep < 4; sweep++) {
    final forward = sweep.isEven;
    final indices = forward
        ? List.generate(layers.length, (i) => i)
        : List.generate(layers.length, (i) => layers.length - 1 - i);

    for (final i in indices) {
      final neighbours = forward ? up : down;
      final reference = forward ? i - 1 : i + 1;
      if (reference < 0 || reference >= layers.length) continue;

      final positionInReference = <String, int>{
        for (var k = 0; k < layers[reference].length; k++)
          layers[reference][k]: k,
      };

      double barycentre(String id) {
        final ns = neighbours[id] ?? const <String>[];
        final known = [
          for (final n in ns)
            if (positionInReference[n] != null) positionInReference[n]!,
        ];
        // A node with no neighbour in the reference layer keeps its place
        // rather than being flung to one end.
        if (known.isEmpty) return layers[i].indexOf(id).toDouble();
        return known.reduce((a, b) => a + b) / known.length;
      }

      final keyed =
          [
            for (var k = 0; k < layers[i].length; k++)
              (id: layers[i][k], key: barycentre(layers[i][k]), tie: k),
          ]..sort((a, b) {
            final c = a.key.compareTo(b.key);
            return c != 0 ? c : a.tie.compareTo(b.tie);
          });
      layers[i] = [for (final e in keyed) e.id];
    }

    final crossings = _countCrossings(layers, down);
    if (crossings < best) {
      best = crossings;
      bestSnapshot = [for (final l in layers) List<String>.from(l)];
    }
  }

  for (var i = 0; i < layers.length; i++) {
    layers[i] = bestSnapshot[i];
  }
  return best;
}

/// Inversions between the edges joining each adjacent pair of layers.
int _countCrossings(List<List<String>> layers, Map<String, List<String>> down) {
  var total = 0;
  for (var i = 0; i + 1 < layers.length; i++) {
    final upper = {for (var k = 0; k < layers[i].length; k++) layers[i][k]: k};
    final lower = {
      for (var k = 0; k < layers[i + 1].length; k++) layers[i + 1][k]: k,
    };

    final pairs = <(int, int)>[];
    for (final from in layers[i]) {
      for (final to in down[from] ?? const <String>[]) {
        if (lower[to] == null) continue;
        pairs.add((upper[from]!, lower[to]!));
      }
    }
    for (var a = 0; a < pairs.length; a++) {
      for (var b = a + 1; b < pairs.length; b++) {
        final (ua, la) = pairs[a];
        final (ub, lb) = pairs[b];
        if ((ua - ub) * (la - lb) < 0) total++;
      }
    }
  }
  return total;
}

// ── 3. coordinates ──────────────────────────────────────────────────────────

Map<String, Offset> _positions(
  MermaidFlow flow,
  List<List<String>> layers,
  Map<String, Size> sizes,
) {
  final vertical = flow.direction.isVertical;
  final positions = <String, Offset>{};

  // Along the rank axis: each layer starts after the tallest (or widest) box
  // of the previous one.
  final rankOffsets = <double>[];
  var cursor = 0.0;
  for (final layer in layers) {
    rankOffsets.add(cursor);
    final extent = layer.fold<double>(
      0,
      (a, id) => math.max(a, vertical ? sizes[id]!.height : sizes[id]!.width),
    );
    cursor += extent + kFlowRankGap;
  }

  // Across it: pack, then centre each layer against the widest one.
  final layerExtents = <double>[
    for (final layer in layers)
      layer.fold<double>(
            0,
            (a, id) => a + (vertical ? sizes[id]!.width : sizes[id]!.height),
          ) +
          kFlowNodeGap * math.max(0, layer.length - 1),
  ];
  final widest = layerExtents.fold<double>(0, math.max);

  for (var i = 0; i < layers.length; i++) {
    var across = (widest - layerExtents[i]) / 2;
    for (final id in layers[i]) {
      final size = sizes[id]!;
      positions[id] = vertical
          ? Offset(across, rankOffsets[i])
          : Offset(rankOffsets[i], across);
      across += (vertical ? size.width : size.height) + kFlowNodeGap;
    }
  }

  // `BT` and `RL` are the same layout, mirrored — computing them separately
  // would be two more code paths to keep in step.
  if (flow.direction == MermaidDirection.bottomUp ||
      flow.direction == MermaidDirection.rightLeft) {
    final total = cursor - kFlowRankGap;
    for (final entry in positions.entries.toList()) {
      final size = sizes[entry.key]!;
      positions[entry.key] = vertical
          ? Offset(entry.value.dx, total - entry.value.dy - size.height)
          : Offset(total - entry.value.dx - size.width, entry.value.dy);
    }
  }
  return positions;
}

Rect _bounds(
  Map<String, Offset> positions,
  Map<String, Size> sizes,
  MermaidFlow flow,
) {
  // Only REAL nodes define the picture. A waypoint is a routing hint; letting
  // one push the border out would leave a margin nobody can see the reason for.
  final real = {for (final n in flow.nodes) n.id};
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final entry in positions.entries) {
    if (!real.contains(entry.key)) continue;
    final size = sizes[entry.key]!;
    minX = math.min(minX, entry.value.dx);
    minY = math.min(minY, entry.value.dy);
    maxX = math.max(maxX, entry.value.dx + size.width);
    maxY = math.max(maxY, entry.value.dy + size.height);
  }
  if (minX == double.infinity) return Rect.zero;
  return Rect.fromLTRB(
    minX - kFlowMargin,
    minY - kFlowMargin,
    maxX + kFlowMargin,
    maxY + kFlowMargin,
  );
}

// ── 4. routing ──────────────────────────────────────────────────────────────

FlowEdgePath _route(
  MermaidEdge edge,
  FlowNodeBox from,
  FlowNodeBox to,
  List<Offset> waypoints,
) {
  if (from.id == to.id) {
    // A self-loop leaves the right edge and comes back to the top.
    final r = from.rect;
    final points = [
      Offset(r.right, r.center.dy),
      Offset(r.right + 34, r.center.dy),
      Offset(r.right + 34, r.top - 18),
      Offset(r.center.dx, r.top - 18),
      Offset(r.center.dx, r.top),
    ];
    return FlowEdgePath(
      points: points,
      style: edge.style,
      arrow: edge.arrow,
      label: edge.label,
      labelAnchor: Offset(r.right + 40, r.top - 24),
    );
  }

  // With waypoints the edge aims at its FIRST hop, not straight at the target —
  // which is the whole point: it leaves the box heading around the obstacle
  // rather than through it.
  final firstTarget = waypoints.isEmpty ? to.rect.center : waypoints.first;
  final lastSource = waypoints.isEmpty ? from.rect.center : waypoints.last;
  final start = _anchor(from.rect, firstTarget);
  final end = _anchor(to.rect, lastSource);

  final points = <Offset>[start, ...waypoints, end];
  final mid = waypoints.isNotEmpty
      ? waypoints[waypoints.length ~/ 2]
      : Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);

  return FlowEdgePath(
    points: points,
    style: edge.style,
    arrow: edge.arrow,
    label: edge.label,
    labelAnchor: mid,
  );
}

/// Where a line from [rect]'s centre toward [target] leaves the box.
///
/// Clipping to the border rather than starting at the centre is what keeps an
/// arrowhead off the text and stops a short edge from looking like a smudge.
Offset _anchor(Rect rect, Offset target) {
  final c = rect.center;
  final dx = target.dx - c.dx;
  final dy = target.dy - c.dy;
  if (dx == 0 && dy == 0) return c;

  final halfW = rect.width / 2;
  final halfH = rect.height / 2;
  final scale = math.min(
    dx == 0 ? double.infinity : halfW / dx.abs(),
    dy == 0 ? double.infinity : halfH / dy.abs(),
  );
  return Offset(c.dx + dx * scale, c.dy + dy * scale);
}

// ── sizing ──────────────────────────────────────────────────────────────────

Size _nodeSize(MermaidNode node, MermaidMeasure measure) {
  final text = measure(node.label);
  var w = math.max(text.width + kFlowNodePadH * 2, kFlowMinNodeWidth);
  var h = text.height + kFlowNodePadV * 2;

  switch (node.shape) {
    case MermaidShape.diamond:
      // A rhombus wastes its corners: the label needs the box to grow before
      // it fits inside the outline rather than poking through it.
      w *= 1.45;
      h *= 1.7;
    case MermaidShape.circle:
      final side = math.max(w, h) * 1.15;
      w = side;
      h = side;
    case MermaidShape.stadium:
    case MermaidShape.round:
      w += kFlowNodePadH;
    case MermaidShape.rect:
      break;
  }
  return Size(w, h);
}
