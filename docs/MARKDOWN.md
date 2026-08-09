# MARKDOWN.md — the markdown workspace

> Son güncelleme: 2026-08-09 — round 17 planning (Epic 24, OPH-246…OPH-252)
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

## 1. What exists today (measured, 2026-08-09)

| Piece | File | Reality |
| --- | --- | --- |
| Editor | `features/notes/ui/note_editor_screen.dart` | `flutter_quill` WYSIWYG, `QuillSimpleToolbar` with alignment/indent/direction/search **disabled**, debounced 1.5 s autosave |
| Canonical content | `notes.content_delta` (+ derived `content_markdown`) | Quill Delta JSON is the source of truth; markdown is an **export** |
| Delta → MD | `features/notes/data/delta_markdown.dart` | headers, bold/italic/strike/code, links, bullet/ordered/checked lists, blockquote, code fences, image/video embeds |
| MD → Delta | `features/notes/data/markdown_delta.dart` | exact inverse of the above; round-trip tested (OPH-241) |
| "Preview" | `_showMarkdownPreview()` | a `SelectableText` of the **raw markdown source** in monospace — not a rendered view |
| Import viewer | `features/notes/ui/markdown_import_screen.dart` | read-only `QuillEditor` over the delta an import would write (DESIGN §28 M1) |
| OS registration | Android `ACTION_VIEW` (mime + `pathPattern`), iOS/macOS `CFBundleDocumentTypes` | shipped in v1.3.0 |
| Export | `note_pdf.dart` + `note_export.dart` | PDF only (Roboto + DejaVu fallback) |

Two limits are already written down and both bite this round:

- **Delta is flat.** DESIGN §28: *"nested lists are out because Quill's own
  model is flat."*
- **Unknown markup survives as plain text.** DESIGN §28 M2. A table pasted into
  a note today comes back out as the literal pipe characters it went in as.

And one that is not written down yet, measured for this doc:
**`flutter_quill` 11.5.1 has no table node in its core document model.** Tables,
footnotes, math and diagrams have no Delta representation at all.

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

**ADR-0028 decides this (OPH-246) and nothing downstream starts before it.**
Recorded here so the decision is made with the trade-offs on the table rather
than discovered halfway through OPH-248.

---

## 5. Renderer choice

`flutter_markdown` was **discontinued by the Flutter team on 30 April 2025**;
Google formally designated **`flutter_markdown_plus`** (Foresight Mobile) as its
continuation. The realistic candidates, all to be measured in OPH-246:

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

## 9. Sources

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
