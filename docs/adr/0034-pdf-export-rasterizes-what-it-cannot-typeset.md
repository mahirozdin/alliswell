# ADR-0034 — The PDF exporter draws what it cannot typeset

- **Status:** Accepted
- **Date:** 2026-08-24
- **Related task:** OPH-275 (feedback round 19 #1)
- **Binding documents:** [MARKDOWN.md](../MARKDOWN.md) · [DESIGN.md §10 F3](../DESIGN.md)
- **Extends:** [ADR-0028 §3](0028-markdown-document-model-and-renderer.md)
  (how far diagrams go) — that section said a diagram is drawn in pure Flutter
  and stopped at the screen. This says what happens when the same document has
  to become a page.

## Context

The owner's report was one sentence: *"exporting notes to PDF loses the images
that were added to the note — we have to export the MD file the way it LOOKS,
graphics and images, all of it."*

Two separate failures were behind it.

**The images were a plain bug.** `markdown_blocks.dart` promoted an image to a
figure only when it was the *sole* child of its paragraph. An image written
inside a sentence — which is exactly what the app's own "insert image" button
produces, because it writes `![](alliswell://file/{id})` at the caret — fell
through to the inline-span walker, whose `default:` branch recurses into an
element's children. An `img` has none. So it contributed nothing, silently, and
no test caught it because every image case anyone had written put the image on
its own line.

**The graphics were a design limit.** Mermaid diagrams printed as their own
source in a code panel and display formulas printed the words "unsupported
block". Both were deliberate and both were honest — `note_pdf.dart` builds the
page out of `pdf` package widgets, and there is no `pdf` widget for a directed
graph or for KaTeX. Honest is not the same as what the note looks like.

## Decision

**Rasterize the blocks that have no page representation, and only those.**

A new `NoteBlockKind.figure` carries two things: a raster key and the source to
fall back to. `note_export.dart` builds the same widgets the reading view uses
(`MermaidView`, `Math.tex`), paints them off-screen, and hands the PNG bytes to
the layout engine through the map it already uses for fetched media. If no
picture could be made, the page prints the block's source.

Three properties this shape was chosen for:

1. **The text stays text.** Every heading, paragraph, list, table and link
   remains real PDF content — selectable, searchable, and roughly a tenth of the
   bytes. Rasterizing the whole page would have been far less code and a much
   worse document.
2. **`note_pdf.dart` stays pure.** It gains one `case` and still knows nothing
   about widgets, platform channels or the network. Its whole test suite runs in
   a plain `flutter test`.
3. **Failure degrades to the old behaviour**, not to a hole. DESIGN §10 F3 is
   unchanged: what cannot be drawn says what it is.

### How the off-screen pass works, and why not the other way

`MermaidView` and `Math.tex` read `MdStyles.of(context)` and `context.mdTheme`.
Rendering them through a detached `BuildOwner`/`PipelineOwner` — the usual
"screenshot a widget with no tree" recipe — would mean re-providing every
inherited widget they depend on by hand, and re-providing them *correctly* is a
thing that fails quietly and later. So the figures are inserted into the app's
own root `Overlay` at `left: -100000`, inside a `RepaintBoundary`, and captured
after two frames.

All the figures go into **one** overlay entry: one insert, one settle, N
captures. One entry per figure would mean waiting a frame per figure, and a note
with a dozen diagrams would spend the export watching the vsync clock.

Two things are deliberately overridden inside that subtree:

- **The light theme, always.** `note_pdf.dart` already says print is light — a
  dark-theme diagram on white paper is an invisible diagram.
- **`TextScaler.noScaling`.** A phone set to 200% text would overflow a figure
  whose box is fixed at the page's width. The PDF has its own type scale.

## Alternatives considered

- **Leave mermaid as a code panel.** It is defensible — a reader who gets the
  diagram's source has more than one who gets nothing — and it is what we did.
  It is not what the note looks like, which is what was asked for. It survives
  as the fallback.
- **Render the whole page to images.** One code path instead of two, and it
  throws away selectable text, searchable text, working links and an order of
  magnitude of file size. No.
- **Ship an HTML export instead.** A different product decision, not an answer
  to this one. Parked.

## Consequences

- Export now needs a `BuildContext` with an overlay in it. On a surface with no
  overlay the rasterizer returns nothing and the fallback prints — so the
  exporter still works headless, it just prints sources.
- `toImage` is unreliable on Flutter web outside CanvasKit. Same fallback.
- Inline images become full-width figures, with the paragraph split around them.
  On screen the renderer keeps them inline as a `WidgetSpan`; at page width a
  figure reads better and loses nothing.
- Inline math (`$x^2$`) stays inline, as code-marked text. Splitting a sentence
  around a two-character formula would read worse than the LaTeX does.
