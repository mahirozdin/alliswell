# MARKDOWN.md — the markdown workspace

> Son güncelleme: 2026-08-18 — OPH-274 (ADR-0033: markdown is the only format).
> Önceki: 2026-08-09 — round 17 planning (Epic 24, OPH-246…OPH-252)
> Kaynak: feedback round 17 #3 · Binding UI rules: [DESIGN.md §29](DESIGN.md) ·
> Backlog: [TASKS.md Epic 24](TASKS.md) · Predecessor: [DESIGN.md §28](DESIGN.md) (OPH-241)

This is the binding document for **reading, writing and owning markdown** in
AllisWell — the same role [NOTIFICATIONS.md](NOTIFICATIONS.md) plays for alarms
and [ATTACHMENTS.md](ATTACHMENTS.md) for files.

It exists because round 17 asked for something the notes feature is not today: a
markdown **viewer and editor** good enough that a person on a Mac stops reaching
for Typora or Obsidian to read a `.md` file. That is a product bet, so it gets a
survey, an explicit scope, and — most importantly — a written answer to the one
question that decides everything else: **what is a note actually made of?**

---

## 1. What exists today (measured, 2026-08-18)

| Piece | File | Reality |
| --- | --- | --- |
| Editor | `features/notes/ui/note_editor_screen.dart` + `ui/modes/source_mode.dart` | markdown source with **live syntax** (D24), one toolbar at every width, slash menu, ⌘K palette, find & replace, split preview, 1.5 s debounced autosave |
| Live syntax | `markdown/md_highlight.dart` | `MdSourceController.buildTextSpan` — headings sized in the field, bold bold, marks dimmed off the caret's line. **Never hidden**: a `TextEditingController` must return exactly the characters of `text` |
| Canonical content | `notes.content_markdown` | the only source of truth (ADR-0033). `content_format` is `'markdown'` on every row |
| Renderer | `markdown/aw_markdown.dart` (+ 11 modules, `mermaid/`) | our own widget tree over `markdown` 7.3.1, carrying a node → source-line map. GFM tables, task lists, footnotes, alerts, KaTeX, Mermaid, outline, folding |
| Delta → MD | `features/notes/data/delta_markdown.dart` | **transitional.** Converts writes from clients that predate 2026-08-18, and the replica's old rows (drift v19). Goes when they do |
| MD → blocks | `features/notes/data/markdown_blocks.dart` | the PDF exporter's structure — tables, nested lists and dividers included, none of which Delta could hold |
| Search text | `core/markdown_text.dart` | `plainTextFromMarkdown`, the twin of the server's `markdownToPlainText`, character for character |
| Import viewer | `features/notes/ui/markdown_import_screen.dart` | the file's own markdown, rendered by the one renderer — byte-faithful, stored as-is |
| OS registration | Android `ACTION_VIEW` (mime + `pathPattern`), iOS/macOS `CFBundleDocumentTypes` | shipped in v1.3.0 |
| Export | `note_export.dart` → `markdown_blocks.dart` → `note_pdf.dart`; `GET /notes/:id/export` | PDF (Roboto + DejaVu fallback) and `.md` |

**The two limits §1 used to open with are gone**, and they are worth naming
because they were the argument for this change:

- *"Delta is flat, so nested lists are out"* (DESIGN §28) — markdown's are not.
  `markdownToBlocks` carries an `indent`, and the PDF prints it.
- *"Unknown markup survives as plain text"* (DESIGN §28 M2) — a table pasted
  into a note used to come back out as literal pipe characters. It is a table.

The measurement that decided it stands: **`flutter_quill` 11.5.1 has no table
node in its core document model.** Tables, footnotes, math and diagrams had no
Delta representation at all, so half of what a note could DISPLAY, it could
not BE.

---

## 2. Field survey — thirteen products

Read for **features to steal**, not for pricing. Each row ends in a verdict so
the next agent does not re-litigate it.

| # | Product | What it does that we do not | Verdict for AllisWell |
| --- | --- | --- | --- |
| 1 | **Obsidian** | Three explicit modes — **Source / Live Preview / Reading**; Outline panel with auto-scroll-to-current-section; backlinks shown in-document; `[[wikilinks]]`; callouts (`> [!TIP]`) with a context menu to remove the formatting; YAML front-matter surfaced as typed **Properties**; command palette (⌘P) that puts recently used commands on top; right-click a table to add/move/sort rows and columns | **Take:** three modes, outline, callouts, command palette, table row/col menu. **Later:** backlinks, graph. **Reject:** plugin ecosystem (not our product). |
| 2 | **Typora** | Inline WYSIWYG with **no preview toggle at all** — syntax hides itself as you leave the line; famously fast launch and typing | **Take** the "syntax hides itself" behaviour as our Live mode. Do **not** copy "no source mode ever" — power users want the raw text. |
| 3 | **iA Writer** | **Focus mode** dims everything but the current sentence; a syntax highlighter that colours parts of speech; the cleanest typographic surface in the category | **Take** focus mode + typography controls. **Reject** parts-of-speech highlighting (English-only lexicons; we ship Turkish). |
| 4 | **Bear** | `#hashtag`-driven organisation, themes, long-document handling | We already have tags and one design system. **Reject** themes (Rule 11). |
| 5 | **Ulysses** | Writing **goals** (word/char count, deadline); styled export to PDF/DOCX/ePub | **Take** live word/character count. **Later:** goals. **Reject** ePub. |
| 6 | **Zettlr** | Split view: raw markdown left, rendered HTML right, **in real time**; Pandoc export; footnote-first workflow; citations | **Take** split view + synced scroll + footnotes. **Reject** Pandoc/citations (academic niche, external binary). |
| 7 | **Mark Text** | Inline WYSIWYG with **tables, KaTeX math and Mermaid diagrams**; PDF/HTML export. *Unmaintained since 2022* | **Take** the feature set (tables/math/mermaid) as the bar to clear. **Take the warning too:** an abandoned WYSIWYG markdown editor is the normal outcome; scope accordingly. |
| 8 | **Notion** | Block model, slash commands, real-time collaboration, markdown import/export | **Take** slash commands. **Reject** the block model (it is a different product) and collaboration (v2 parking lot). |
| 9 | **Logseq** | Outliner over plain files, bidirectional links, graph view, queries, PDF annotation | **Reject** the outliner model. **Later:** bidirectional links between notes. |
| 10 | **Joplin** | Notebooks + tags + search, E2E-encrypted sync, rich **import/export**, web clipper | We have the first three. **Take** the breadth of export targets as a direction (HTML today, DOCX later). |
| 11 | **VS Code** (+ *Markdown All in One*) | Editor↔preview **scroll sync both ways** with a toolbar toggle; Outline view built from the heading hierarchy; heading **folding** in the editor; auto TOC generation; a copy button on every fenced code block (extension) | **Take** all of it: scroll sync, outline, folding, copy-code button, auto TOC. This is the "developer reads a README" experience the round is about. |
| 12 | **GitHub (GFM)** | The de-facto dialect everyone's files are written in: tables, task lists, strikethrough, autolinks, footnotes, syntax-highlighted fences, **alerts** (`[!NOTE] [!TIP] [!IMPORTANT] [!WARNING] [!CAUTION]`), **Mermaid** fences, `$…$`/`$$…$$` **KaTeX math** | **This is the target dialect.** If a README renders on GitHub it must render in AllisWell. Everything else in this table is optional; this row is not. |
| 13 | **Marked-class viewers** (Marked 2, mdview, macmdviewer) | Pure *reading*: fast open, typographic themes, outline sidebar, live reload when the file changes on disk, print/PDF with a real stylesheet | **Take** live reload for external files and a genuine reading typography. This is the row that matches "open a `.md` with AllisWell". |

**Sources** are listed in §9.

---

## 3. Feature inventory — take, later, reject

Forty-one candidates, each with a decision. "Later" means the parking lot in
`TASKS.md`, with the reason attached; it does not mean silently forgotten.

### 3.1 Reading (the viewer)

| Feature | Decision | Note |
| --- | --- | --- |
| GFM tables | **Take** | The #1 thing a README has that we drop today |
| Task list checkboxes, **tickable in the reading view** | **Take** | And they write back to the document |
| Footnotes | **Take** | Zettlr/GFM; tap jumps down and back |
| Alerts / callouts (`> [!NOTE]`) | **Take** | GFM + Obsidian; renders as a tinted glass card |
| Fenced code with **syntax highlighting** + language label + **copy button** | **Take** | VS Code/GitHub baseline |
| Inline & block **math** (KaTeX subset) | **Take** | GFM ships it; Turkish STEM notes need it |
| **Mermaid** diagrams | **Take (behind a gate)** | GFM ships it; see §5 for how, and the honest fallback |
| Nested lists (any depth) | **Take** | Today's hard limit; fixing it is a model change, not a renderer tweak |
| Strikethrough, autolinks, `==highlight==`, emoji shortcodes | **Take** | Cheap once the parser is real |
| Images: sized, captioned, **tap to zoom** | **Take** | Shares the viewer built in OPH-245 |
| Outline / TOC panel, jump-to-heading | **Take** | Obsidian + VS Code |
| Heading **folding** | **Take** | VS Code; essential over a 2 000-line README |
| Reading typography: measure cap, line height, adjustable text size | **Take** | The Marked-class row; DESIGN §29 |
| Anchor links / heading permalinks | **Take** | `#heading` links inside a document must work |
| Front-matter (YAML) shown as a properties header, not as garbage text | **Take** | Every Jekyll/Hugo file starts with one |
| HTML blocks inside markdown | **Take, inert** | Rendered as escaped source, never as live HTML — the AI-surface rule (DESIGN §24 AI6) applies to any untrusted document |
| Sync scroll between source and preview | **Take** | VS Code's two-way version |
| Live reload when an external file changes on disk | **Take** | Marked 2's signature behaviour |
| Backlinks / `[[wikilinks]]` between notes | **Later** | Needs a link index; a real feature of its own |
| Graph view | **Reject** | Different product |
| PDF annotation | **Reject** | Different product |
| Citations / BibTeX | **Reject** | Academic niche |

### 3.2 Writing (the editor)

| Feature | Decision | Note |
| --- | --- | --- |
| **Three modes: Source / Live / Reading** | **Take** | Obsidian's exact triple; the spine of §5 |
| Split view with synced scroll (wide screens only) | **Take** | Zettlr; phones get mode switching instead |
| Markdown **source** editing with the source itself syntax-highlighted | **Take** | Today there is no way to edit raw markdown at all |
| Find & replace (regex optional) | **Take** | The toolbar's search button is *disabled* today |
| List auto-continuation + smart renumbering + Tab/Shift-Tab nesting | **Take** | The single biggest typing-comfort win |
| Keyboard shortcuts (⌘B/I/K, heading levels, code) | **Take** | Desktop and web are first-class targets |
| Table editor UI: add/move/delete row & column, align | **Take** | Obsidian's right-click menu |
| Slash commands (`/table`, `/code`, `/todo`) | **Take** | Notion; also the mobile answer to "where is the toolbar" |
| Command palette (⌘P/⌘K) | **Take** | Obsidian; desktop/web only |
| Word / character count + reading time | **Take** | Ulysses |
| Focus mode (dim all but current paragraph) + typewriter scrolling | **Take** | iA Writer |
| Paste: HTML → markdown; URL over a selection → link; image from clipboard → uploaded attachment | **Take** | `flutter_quill_delta_from_html` is already in the tree |
| Drag & drop a file onto the editor | **Take** | Desktop/web |
| Auto-save (exists) + explicit save state indicator | **Take** | The indicator is missing; autosave silence is a trust problem |
| Undo/redo across a mode switch | **Take** | A mode switch must not clear history |
| Writing goals / deadlines | **Later** | Ulysses; nice, not load-bearing |
| Vim / Emacs keybindings | **Reject** | Audience does not justify the surface |
| Custom CSS / user themes | **Reject** | Rule 11 — one design system, forever |
| Real-time collaboration | **Reject (v2)** | Already parked |
| Version history / snapshots | **Later** | Wants a server-side design of its own |
| AI: "continue writing", "rewrite" inside the editor | **Later** | Epic 20 has the plumbing; a deliberate product decision, not a freebie |

### 3.3 Owning the file

| Feature | Decision | Note |
| --- | --- | --- |
| Open a `.md` from the OS | **Shipped** (v1.3.0) | |
| Import it as a note | **Shipped** (v1.3.0) | |
| **Edit and save back to the original file** | **Take** | Round 17's explicit ask: *"görme ve değiştirme"* |
| The external file is visibly external | **Take** | DESIGN §28 M3 extends into a persistent banner while editing |
| "Save permanently to notes" from that banner | **Shipped** — must survive the redesign | |
| Attach the external file to a project | **Take** | Round 17: *"isterse projeye ekle"* |
| Recent external files list | **Take** | Otherwise a file opened once is unreachable again |
| Watch a folder / vault | **Reject** | That is Obsidian; we are a task app that reads markdown well |

---

## 4. The crux: Delta cannot hold half of §3

Every "Take" in §3.1 that is a **block type** — tables, math, mermaid, callouts,
footnotes, nested lists — has no representation in Quill Delta, and
`flutter_quill` 11.5.1 ships no table node. So this is not a rendering task with
a UI in front of it. It is a question about the note model, and it has exactly
three honest answers.

### Option A — keep Delta canonical, add custom embeds

Add a Delta embed per new block (`{"insert":{"table":…}}`, `{"math":…}`).

- **For:** no migration; existing notes untouched; the WYSIWYG stays.
- **Against:** we would be inventing a private document format and writing an
  editor for each block by hand. Both converters
  (`delta_markdown` / `markdown_delta`) grow a branch per block type, and the
  round-trip guarantee that OPH-241 leans on gets harder every time. Mark Text
  is the cautionary tale in row 7.

### Option B — make markdown canonical, Delta derived

`notes.content_markdown` becomes the source of truth; Delta is regenerated for
the WYSIWYG session and thrown away.

- **For:** the file on disk and the note in the database become the *same
  thing*, which is exactly what "open, edit, save back" wants. Every §3 feature
  becomes a renderer/parser feature instead of a model feature.
- **Against:** a data migration on every existing note, and WYSIWYG editing of
  markdown is lossy in the other direction (round-tripping a hand-formatted file
  through a rich editor reflows it). Sync conflict semantics
  (`AGENTS.md` §6: document-level optimistic lock + conflict copy) need a
  re-read.

### Option C — split by intent (recommended starting position)

**Reading is markdown. Editing is a mode the user chooses.**

- `content_markdown` becomes the **canonical** text for a note that came from a
  file or that the user has switched to markdown; Delta stays canonical for
  notes authored in the WYSIWYG.
- One flag per note records which one is authoritative (`content_format`).
- The **Reading view is always a real markdown renderer** over the canonical
  markdown — full §3.1, no Delta involved.
- The **Source view** edits that markdown as text.
- The **Live view** is the Quill WYSIWYG, offered only for notes whose canonical
  form is Delta, or after an explicit, warned, one-way conversion.

- **For:** no migration for existing notes; markdown files stay byte-faithful,
  which is the only way §3.3 "save back to the original file" can be honest;
  every §3.1 feature lands in one renderer instead of in two converters.
- **Against:** two formats in one table, and a conversion door that must be
  explained in one sentence to a non-technical user.

> **REVERSED — [ADR-0033](adr/0033-markdown-is-the-only-note-format.md),
> 2026-08-18: Option B.** A note is markdown. There is no second form, no
> `NoteFormat`, no conversion door, and `content_format` is `'markdown'` on
> every row. The rich editor is gone from the tree.
>
> Option C's winning argument was that its migration touched **zero rows**, and
> that was true. What it did not price was that TWO canonical fields fork every
> write path — saving, exporting, versioning, merging and the search index —
> and that the fork gets more expensive each round rather than less. Two
> measurements settled it: OPH-247…252 shipped tables, footnotes, math and
> diagrams in the RENDERER, so half of what a note could display it could not
> be; and Epic 25's three-way merge answered `NOT_MARKDOWN` on Delta notes,
> which is to say it declined the only kind of note anybody had.
>
> B's cost was named correctly in 2026-08-10 and paid in OPH-274: every note
> migrates. What was *wrong* in the objection is "reflows hand-formatted files
> through the rich editor" — there is no rich editor to reflow anything, so
> §6's "save back byte-faithfully" is now structurally true rather than
> carefully arranged. The conflict unit (AGENTS §6) still does not change.
>
> **DECIDED — [ADR-0028](adr/0028-markdown-document-model-and-renderer.md),
> 2026-08-10: Option C** *(superseded; kept for the record)*. A note was either
> Delta-canonical or markdown-canonical, recorded in a `content_format` column
> defaulting to `'delta'`. Reading was always a real markdown renderer; Source
> edited the markdown as text; Live (Quill) was offered only to Delta-canonical
> notes, and moving between them was an explicit, warned, one-way conversion.

---

## 5. Renderer choice

> **DECIDED — [ADR-0028](adr/0028-markdown-document-model-and-renderer.md),
> 2026-08-10: our own widget tree over the `markdown` Dart package** (7.3.1,
> already in the tree transitively). Measured with
> `scripts/markdown/measure_coverage.dart` against
> `apps/app/test/fixtures/markdown_conformance.md`:
>
> - **19 of 22** D6 items are ready out of the box with
>   `ExtensionSet.gitHubWeb` — including tables *with alignment*, task-list
>   checkboxes, **footnotes** and **GFM alerts**, which the table below assumed
>   we would have to build. Three gaps remain, each a small custom syntax:
>   math (`$…$`), `==highlight==`, front matter.
> - The decisive one: `markdown`'s AST carries **no source positions at any
>   level**, and **neither does any candidate below**. D4, D13/D14, D16 and D5
>   all need a node → source-line map, so that layer is ours no matter what —
>   which removes the main reason to take a packaged renderer. A prototype
>   stamped **109 of 110** top-level nodes and verified **29 of 29** heading
>   positions against the source, **without forking** the package.
>
> The candidate table below is kept as the record of what was weighed.

`flutter_markdown` was **discontinued by the Flutter team on 30 April 2025**;
Google formally designated **`flutter_markdown_plus`** (Foresight Mobile) as its
continuation. The candidates that were measured in OPH-246:

| Candidate | Brings | Costs |
| --- | --- | --- |
| `flutter_markdown_plus` (+ `_latex`) | Direct lineage, familiar API, LaTeX companion package | No mermaid; extending block types means widget-level work |
| `markdown_widget` | Built-in **TOC**, code highlighting, all platforms | Smaller ecosystem |
| `gpt_markdown` | Full LaTeX, built for streaming AI output | Tuned for chat, not documents |
| `flutter_smooth_markdown` | Highlighting, LaTeX, tables, footnotes, SVG, **mermaid**, streaming | Youngest of the four; must be read before it is trusted |
| Own renderer over the `markdown` Dart package | Total control, one AST, no surprises | The most work; we would own every edge case |

Two rules constrain the choice regardless of which wins:

1. **Rule 11 applies to rendered markdown.** Headings, code panels, tables and
   callouts are styled from `AwTokens`, not from a package's defaults, and
   `python3 scripts/design/contrast.py` must pass in both themes.
2. **A document is untrusted input.** Raw HTML is never live, `javascript:` and
   `data:` URIs never become taps, and remote images obey the same rules note
   embeds already follow. Mermaid, if it lands, renders from a parsed AST — we
   do not put a web view with a JS engine on the reading path. If a diagram
   cannot be drawn, DESIGN §10 F3 applies: an honest placeholder, never a blank.

> **DECIDED — ADR-0028 §3 and §4, 2026-08-10.**
>
> **Math is drawn** (owner's decision). The engine must paint in pure Flutter —
> no JS, no web view — on all six platforms and take its colours from
> `AwTokens`; OPH-247 picks between `flutter_math_fork` and
> `flutter_markdown_plus_latex` against the fixture and **records the measured
> APK/IPA size delta of the KaTeX font assets**.
>
> **Mermaid is drawn, for two diagram types** (owner's decision, scoped by
> measurement). v1 draws `flowchart`/`graph` and `sequenceDiagram`; class,
> state, ER, gantt, pie and journey fall to the honest placeholder. The costs
> differ by an order of magnitude — a sequence diagram is columns and rows, a
> flowchart is layered graph drawing (rank → crossing reduction → coordinates →
> edge routing). It gets **its own task, OPH-254**, so it cannot quietly consume
> OPH-247, and it has a written exit: if the layout is not good enough to ship,
> it falls back to the placeholder and amends the ADR.
>
> Mermaid needs no parser extension — it arrives as a fenced code block with a
> `mermaid` info string, which the coverage measurement confirms is already
> captured.

---

## 6. External files: what "değiştirme" costs

Saving back to a user's own file is the one feature here that can destroy data,
so it gets its own rules (bound in DESIGN §29 W1–W6):

- **Byte-faithful or nothing.** If the canonical form for that document is not
  markdown text, the app must not offer to write it back.
- **The write is explicit.** Autosave stays inside AllisWell's own notes;
  an external file is saved by a deliberate action.
- **Sandboxes are real.** iOS hands us a security-scoped URL that expires;
  Android hands us a `content://` URI whose write permission may be
  read-only. Both must be probed *before* the editor claims the file is
  editable, and a read-only file says so in its banner.
- **Conflict is possible.** The file can change on disk under us (§3.1 live
  reload). A changed-underneath file is never silently overwritten.
- **A recent-files list is part of the feature**, not a nicety — a file opened
  through the OS once is otherwise unreachable forever.

---

## 7. Mobile

The phone is where markdown apps usually give up. The three that do not
(Obsidian, Bear, iA Writer) all do the same thing: **a scrolling markdown
toolbar pinned above the keyboard**. That, plus slash commands, is the mobile
plan; the desktop's command palette and split view do not come along.

Reading on a phone gets the same renderer, a collapsible outline reached from
the app bar, and horizontal scrolling **inside** wide tables and code blocks —
never a page that scrolls sideways.

---

## 8. Marketing surface (round 17's explicit ask)

The owner named five things to lead with, in this order. They belong on the
landing page and in the README with real screenshots:

1. **Tasks and projects** — tasks attach to projects.
2. **Notes with a real markdown viewer/editor** — create, read, and open the
   `.md` files already on your computer, edit them, import them.
3. **Alarmed tasks** — the app that does not let you forget.
4. **Every file in one place** — everything related to a project or task lives
   with it.
5. **Recurring tasks** — configured in detail.

Screenshot obligations, gaps and the harness to shoot them are OPH-252.

---

## 9. The engine is a package: `markdown_forge`

OPH-274 extracted the renderer and the editor into
[`apps/app/packages/markdown_forge`](../apps/app/packages/markdown_forge) —
MIT-licensed, destined for `github.com/bubiapps/markdown_forge` and pub.dev,
because nothing in it is AllisWell-specific once three seams are injected:

| AllisWell had | The package asks for | We hand it |
| --- | --- | --- |
| `AwTokens` (Rule 11) | `MarkdownTheme` | `awMarkdownTheme()` |
| `'key'.tr()` | `MarkdownStrings` (incl. the ADR-0013 fold hook) | `awMarkdownStrings()` |
| riverpod's `fileUrlProvider` | `MarkdownImageResolver` | `alliswell://file/{id}` → minted URL |

The adapters live in ONE file —
`apps/app/lib/src/features/notes/markdown/markdown_forge_adapters.dart` — and
the compiler enforces the boundary: the package cannot see `AwTokens`, `.tr()`
or `ProviderScope`, so a change that reaches for them fails to build rather
than quietly re-coupling. `AwMarkdownScope` mounts the seams once, at the app
root.

Publishing (owner's two steps, nothing in-repo blocks on them): create the
`bubiapps` GitHub organisation + `markdown_forge` repo, copy the package
directory there, `dart pub publish`. Until then the app consumes it by path.

## 11. Round 19: what the page shows, and what the field shows

Two reports, and they are the same question asked from opposite ends: **which
surface renders formatting, and which one shows you the source?**

### The page renders everything (OPH-275, ADR-0034)

Export lost images and flattened diagrams. Two causes.

`markdownToBlocks` promoted an image to a figure only when it was the sole child
of its paragraph. An image written mid-sentence — which is what the app's own
"insert image" button produces, since it writes `![](alliswell://file/{id})` at
the caret — reached the inline-span walker, whose `default:` branch recurses
into an element's children. An `img` has none, so it produced nothing and
vanished. Paragraphs now **split** around images: text before, figure, text
after. On screen the renderer keeps them inline as a `WidgetSpan`; at page width
a figure reads better and loses nothing.

Mermaid and display math had no `pdf` widget at all, so they printed their own
source. They are now **rasterized off-screen** with the same widgets the reading
view uses and embedded as images — only those blocks, so every heading,
paragraph, list, table and link stays real, selectable PDF text. ADR-0034 has
the mechanics and the alternatives. Inline math stays inline as code-marked
text: splitting a sentence around `$x^2$` reads worse than the LaTeX does.

The honest fallback is unchanged (DESIGN §10 F3): if no picture can be made, the
page prints the block's source — the diagram's own mermaid, or the LaTeX — which
is strictly more use to a reader than "unsupported block".

### The field shows source (OPH-280)

Bolding a selection in Source mode inserted `**…**` **and** drew the text bold.
Both readings of that are legitimate — Obsidian and Typora paint, a code editor
does not — so it stopped being a hardcoded taste and became a setting.

`MdSourceController` had a `bool liveSyntax` that could express only the two
ends of this, and it was **wired to nothing**: a switch with no handle, always
on. It is now `MdSyntaxStyling`:

| Level | What the field does |
| --- | --- |
| `plain` | no colour at all — the raw text |
| `markersOnly` **(default)** | **colour only.** `#`, `**`, `>` and a link's target step back in `onSurfaceVariant`; a heading takes the accent ink. Nothing changes weight, size, slant, background or decoration. |
| `live` | the Obsidian treatment: headings large, bold bold, highlight highlighted |

`markersOnly`'s contract is asserted over every token kind in
`md_highlight_test.dart`, so "the editor stopped being a preview" cannot come
back one case at a time. The picker in Settings ▸ General renders the same
markdown line in each level using the **real** controller — a preview that can
disagree with the editor is worse than no preview.

### The toolbar never destroys text (OPH-279)

`_insertBlock` used `replaceRange(start, end, …)`, so the code-block button
replaced a selected paragraph with an empty fence. `/table` and `/divider`
shared the helper, and every future block action would have inherited it. The
code button now wraps (and unwraps) the selection; the other two land after it.

The durable part is the guard, not the fix: one test runs **every** entry in
`mdActions()` against a selection and fails if the selected substring, the text
before it, or the text after it is missing from the result.

## 10. Sources

Field survey: [Best Markdown Editors 2026 — hands-on comparison](https://mdclaudy.com/blog/best-markdown-editors-2026) ·
[Best Markdown Editors in 2026: VS Code, Obsidian, Typora and more](https://mdtolink.com/blog/best-markdown-editors/) ·
[Obsidian 1.8 desktop changelog](https://obsidian.md/changelog/2025-01-30-desktop-v1.8.3/) ·
[Markdown and Visual Studio Code](https://code.visualstudio.com/docs/languages/markdown) ·
[VS Code scroll-sync issue #19459](https://github.com/microsoft/vscode/issues/19459) ·
[Markdown preview code copy button](https://github.com/barnim/vscode-ext-markdown-code-copy-button) ·
[GitHub Markdown / GFM guide 2026](https://macmdviewer.com/blog/github-markdown-guide) ·
[GFM cheat sheet — every element](https://www.markdowntools.io/github-markdown-cheat-sheet) ·
[Best markdown note-taking apps 2026 (Joplin, Logseq)](https://anarlog.so/blog/markdown-note-taking-apps/) ·
[Logseq — Markdown Guide](https://www.markdownguide.org/tools/logseq/)

Renderer landscape: [flutter_markdown planned to be discontinued (flutter#162966)](https://github.com/flutter/flutter/issues/162966) ·
[flutter_markdown_plus: how we took over from Google](https://foresightmobile.com/blog/flutter-markdown-plus-google-handover) ·
[flutter_markdown_plus](https://pub.dev/packages/flutter_markdown_plus) ·
[markdown_widget](https://pub.dev/packages/markdown_widget) ·
[gpt_markdown](https://pub.dev/packages/gpt_markdown) ·
[flutter_smooth_markdown](https://pub.dev/packages/flutter_smooth_markdown) ·
[Flutter Gems — markdown packages](https://fluttergems.dev/markdown/)
