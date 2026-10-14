# ADR-0048 — Word export is our own OOXML writer, drawn with the PDF's style

- **Status:** Accepted
- **Date:** 2026-10-15
- **Related task:** note export round (MD + DOCX); closes the parked "DOCX export" idea in
  TASKS.md (round 17 park queue, MARKDOWN.md §2 rows 5 and 10)

## Context

A note exported as PDF (round 16 #3, round 19/19b) looks like the reading view: Roboto, the
light palette, sized headings, real nested lists, green checkbox ticks, tinted alert panels,
tables, fetched pictures and rasterized Mermaid/KaTeX figures. Users asked for the same note as
a Word file they can keep editing, and the owner's bar was "the DOCX must look like the PDF".

Constraints: the export is local-first and works offline (pictures come from the device's own
fetch and figures from the off-screen rasterizer, both already in `note_export.dart`); it has to
run on all six targets including the web; and the layout must stay unit-testable without a
platform channel, like `note_pdf.dart`.

## Decision

1. **We write the OOXML ourselves** (`features/notes/data/note_docx.dart`): a string builder
   with an escape helper produces `document.xml`, `styles.xml`, `numbering.xml`, `settings.xml`,
   `fontTable.xml`, two headers, two footers, the relationships, `docProps` and `word/media/*`,
   and `archive`'s `ZipEncoder` packs them. `archive` and `image` were already in the tree
   transitively and are now declared; no DOCX package is added.
2. **One print style, two writers.** Every colour, size, margin, indent, spacing and picture
   bound moved out of `note_pdf.dart` into `note_print_style.dart` as plain values; the PDF
   writer converts them to points, the Word writer to twips / half-points / eighths / EMUs.
   A change to the page is made once and lands in both files.
3. **Word's own structures where they exist:** real `Heading1–3` and `Title` styles (navigation
   pane works), `numbering.xml` lists with one abstract definition per ordered run (so every list
   counts from its own 1), a `w:tblHeader` row, `w:hyperlink` with external relationships,
   `PAGE / NUMPAGES` fields, `w:titlePg` for the header-less first page.
4. **Approximations where Word has no equivalent**, chosen to match the PDF on the page:
   panel padding is a border in the panel's own colour; the drawn checkbox is ☐ / ☑ in the
   PDF's colours; leading is an "at least" line height with the PDF's between-line gap taken
   back off the space after; table columns are weighted by their widest cell like `pw.Table`'s
   intrinsic widths; Roboto is declared with Arial as its substitute.
5. **Pictures:** PNG and JPEG go in as they are (size read from the header); anything else is
   re-encoded to PNG with `image`; undecodable bytes print the PDF's placeholder.
6. **Exports stay in the app (rule 12 reason).** PDF and DOCX are laid out on the device, from
   bytes only the device has (fetched media, rasterized figures). The public API keeps
   `GET /notes/:id/export?format=md`; MCP keeps no file bytes (AI.md §7).

## Alternatives considered

- **A pub.dev DOCX package.** The ones that exist fill a `.docx` template (we would ship and
  maintain a binary template and still could not express numbering per list or panel borders)
  or generate a thin subset without numbering definitions, headers/footers or inline pictures.
  Either way the fidelity bar would sit in someone else's backlog.
- **Server-side conversion (Pandoc/LibreOffice).** An external binary in the API image, a
  network round trip for an offline-first app, and the server has neither the rasterized
  figures nor (for presigned media) a reason to fetch the pictures. Rejected for the same
  reason the PDF is client-side.
- **HTML saved as `.doc`.** Opens in Word with a compatibility banner, loses lists and page
  furniture in LibreOffice and Pages, and is not a format users can rely on.

## Consequences

- Word is strict about child element order; `note_docx.dart` writes every property block in
  ECMA-376 order and says so. `note_docx_test.dart` unzips the output and parses every part;
  a LibreOffice round trip was used to compare the pages with the PDF.
- The writer covers exactly the block kinds `markdownToBlocks` produces. A new block kind is a
  compile error in both writers' exhaustive switches, which is the point.
- Checklist items are not indented by nesting depth — matching the PDF, which does not indent
  them either. Fixing that is a change to both writers through the shared style.
- MD export: the app now writes the `.md` itself (the API's title rule), so it works offline.
