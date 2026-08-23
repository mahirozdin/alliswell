/// Drawing the blocks a page cannot typeset (round 19 #1, ADR-0034).
///
/// The PDF exporter turns markdown into `pdf` widgets, and two things in a note
/// have no `pdf` widget at all: a mermaid diagram and a display formula. They
/// used to print as their own source — "unsupported block" for math, a code
/// panel for mermaid — which is honest but is not what the note LOOKS like, and
/// round 19 asked for the look.
///
/// So we draw them with the widgets that already draw them on screen and hand
/// the pixels to the PDF as an image. Three consequences worth stating:
///
///  * **Only the figures become pixels.** Every heading, paragraph, list and
///    table stays real PDF text — selectable, searchable, and a tenth of the
///    bytes. Rasterizing the whole page would have been far less code and a
///    much worse document.
///  * **The figures are drawn in the LIGHT theme**, whatever the app is set to.
///    Print is always light (`note_pdf.dart` says so about its palette); a
///    dark-theme diagram on white paper is an invisible diagram.
///  * **A failure is not an error.** Anything that cannot be drawn — an
///    unparseable diagram, a browser whose canvas refuses `toImage`, a device
///    under memory pressure — simply yields no entry, and the exporter prints
///    the source instead (DESIGN §10 F3).
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_forge/markdown_forge.dart';

import '../../../theme/theme.dart';
import '../data/note_blocks.dart';
import '../markdown/markdown_forge_adapters.dart';

/// How wide a figure is drawn, in logical pixels.
///
/// A4 minus the exporter's 2.2 cm margins is ~465 pt of body width, so this is
/// a shade wider than the page: the image is scaled DOWN into the column, which
/// is the direction that stays sharp.
const double kNoteFigureWidth = 620;

/// Device pixels per logical pixel. 3× is the point past which a printed
/// diagram stops showing its own pixels; beyond it the PDF just gets heavier.
const double kNoteFigurePixelRatio = 3;

/// Far enough left that no figure of any width can bleed onto the screen while
/// it is being drawn.
const double _kOffscreen = 100000;

/// Turns [NoteBlockKind.figure] blocks into PNG bytes, keyed by their raster
/// key so they drop straight into `NotePdfDocument.images`.
///
/// A class rather than a function so the export flow can be tested with a fake
/// that returns fixed bytes — the same seam shape as `NotePdfSink`.
class NoteFigureRasterizer {
  const NoteFigureRasterizer();

  Future<Map<String, Uint8List>> rasterize(
    BuildContext context,
    List<NoteBlock> blocks,
  ) async {
    final figures = [
      for (final block in blocks)
        if (block.kind == NoteBlockKind.figure &&
            block.source != null &&
            block.figureKind != null)
          block,
    ];
    if (figures.isEmpty) return const {};

    final OverlayState overlay;
    try {
      overlay = Overlay.of(context, rootOverlay: true);
    } on Object {
      return const {}; // no overlay here (a bare widget test) — print sources
    }

    final keys = {for (final f in figures) f.source!: GlobalKey()};
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -_kOffscreen,
        top: 0,
        child: _FigureCanvas(figures: figures, keys: keys),
      ),
    );
    overlay.insert(entry);

    final out = <String, Uint8List>{};
    try {
      // Two frames: the first builds and lays the subtree out, the second is
      // the one whose paint the boundary can actually capture. One is enough
      // most of the time and silently is not on a cold layout — the exact
      // shape of bug that only appears on someone else's phone.
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;

      for (final figure in figures) {
        final bytes = await _capture(keys[figure.source!]!);
        if (bytes != null) out[figure.source!] = bytes;
      }
    } on Object {
      // Whatever survived is worth keeping; the rest prints its source.
    } finally {
      entry.remove();
    }
    return out;
  }

  Future<Uint8List?> _capture(GlobalKey key) async {
    try {
      final object = key.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) return null;
      final image = await object.toImage(pixelRatio: kNoteFigurePixelRatio);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final bytes = data?.buffer.asUint8List();
        return bytes == null || bytes.isEmpty ? null : bytes;
      } finally {
        image.dispose();
      }
    } on Object {
      return null; // this one figure prints its source; the others still draw
    }
  }
}

final noteFigureRasterizerProvider = Provider<NoteFigureRasterizer>(
  (ref) => const NoteFigureRasterizer(),
);

/// Every figure, stacked, each in its own repaint boundary.
///
/// One overlay entry rather than one per figure: inserting N entries would mean
/// waiting N times for a frame, and a note with a dozen diagrams would spend
/// most of the export watching the vsync clock.
class _FigureCanvas extends StatelessWidget {
  const _FigureCanvas({required this.figures, required this.keys});

  final List<NoteBlock> figures;
  final Map<String, GlobalKey> keys;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Theme(
      // Print is always light — see the library comment.
      data: buildAwTheme(Brightness.light),
      child: MediaQuery(
        // A phone set to 200% text would overflow a diagram whose box is fixed
        // at the page's width. The PDF has its own type scale; the system one
        // has no say in it.
        data: media.copyWith(textScaler: TextScaler.noScaling),
        child: AwMarkdownScope(
          child: Builder(
            builder: (context) => Material(
              color: Theme.of(context).colorScheme.surface,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final figure in figures)
                    RepaintBoundary(
                      key: keys[figure.source!],
                      child: Container(
                        width: kNoteFigureWidth,
                        color: Theme.of(context).colorScheme.surface,
                        padding: const EdgeInsets.all(8),
                        child: _figure(context, figure),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _figure(BuildContext context, NoteBlock block) =>
      switch (block.figureKind!) {
        NoteFigureKind.mermaid => MermaidView(source: block.text),
        NoteFigureKind.math => Center(
          child: Math.tex(
            block.text,
            mathStyle: MathStyle.display,
            textStyle: MdStyles.of(context).body,
            // Same rule as the reading view: a formula we cannot typeset shows
            // itself and says why. Here that becomes a picture OF the reason,
            // which is still more use than a blank.
            onErrorFallback: (_) => MdUnsupportedBlock(
              icon: Icons.functions,
              reason: context.mdStrings.badMath,
              source: block.text,
            ),
          ),
        ),
      };
}
