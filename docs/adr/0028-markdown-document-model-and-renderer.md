# ADR-0028 — Markdown: the note model, the renderer, and how far diagrams go

- **Status:** Accepted
- **Date:** 2026-08-10
- **Related task:** OPH-246 (gate for OPH-247, OPH-254, OPH-248…OPH-252)
- **Binding documents:** [MARKDOWN.md](../MARKDOWN.md) · [DESIGN.md §29](../DESIGN.md)
- **Amends:** nothing. [ADR-0013](0013-local-first-search.md) (app-owned Turkish
  folding) is **reused** by this decision, not changed.

## Context

Feedback round 17 asked for a markdown viewer/editor good enough that a person
stops leaving AllisWell to read a `README.md`. MARKDOWN.md surveyed thirteen
products and produced forty-one take/later/reject decisions, then stopped at the
one question that decides everything downstream: **what is a note actually made
of?**

The constraint that makes this a model question rather than a rendering question
was measured during round 17 planning: **`flutter_quill` 11.5.1 has no table node
in its core document model**, and Delta has no representation for footnotes,
math, diagrams or nested lists. DESIGN §28 already says nested lists are out
"because Quill's own model is flat." Half of DESIGN §29's D6 target simply cannot
be stored in what a note is today.

Three further constraints apply regardless of the answer:

- **Rule 11 has no third-party carve-out** (AGENTS §1.11). Headings, code panels,
  tables and callouts are styled from `AwTokens`, and `contrast.py` must pass in
  both themes.
- **A document is untrusted input** (DESIGN §29 D10). Raw HTML never goes live,
  `javascript:`/`data:` URIs never become taps, and diagrams never render through
  a web view with a JS engine.
- **Writing back to a user's own file must be byte-faithful or refused**
  (DESIGN §29 W4) — OPH-251 is the only feature in the round that can destroy
  data.

## Decision

### 1. The note model — split by intent (MARKDOWN.md §4 Option C)

A note is **either** Delta-canonical **or** markdown-canonical, recorded per note
in a new `content_format` column defaulting to `'delta'`.

- **Reading view is always a real markdown renderer** over the canonical
  markdown. No Delta on the reading path.
- **Source view** edits that markdown as text.
- **Live view** (the Quill WYSIWYG) is offered only for Delta-canonical notes.
- Moving a note from Delta to markdown is an **explicit, warned, one-way**
  conversion — never automatic, never silent.

**Migration is zero rows.** The column defaults to `'delta'`, so every existing
note is correct by construction.

**The conflict unit does not change.** AGENTS §6's "document-level optimistic
lock + conflict copy for notes" still holds; this decision changes only *which
field carries the canonical bytes*, not what a conflict is.

**OPH-241's ROUND TRIP guarantee survives.** `delta_markdown.dart` ↔
`markdown_delta.dart` remain the tested inverse pair, now serving the *import*
path and the one-way conversion door. They are no longer on the reading path,
which is precisely what stops them from growing a branch per block type.

### 2. The renderer — our own widget tree over the `markdown` Dart package

Measured, not assumed. `scripts/markdown/measure_coverage.dart` parses
`apps/app/test/fixtures/markdown_conformance.md` and reports:

> **KAPSAM: 22 kalemden 19 HAZIR**, 3 eksik → matematik (`$…$`),
> vurgu (`==highlight==`), front matter şeridi

`markdown` 7.3.1 with `ExtensionSet.gitHubWeb` already ships tables (with
alignment), task-list checkboxes, **footnotes**, **GFM alerts** (`[!NOTE]`),
strikethrough, emoji shortcodes, autolinks, heading ids, fenced code with a
language class, and HTML blocks as inspectable nodes. Three gaps remain, and each
is a small custom syntax rather than a model change.

The decisive measurement is the second one, because four D-rules depend on it:

> **Konum haritası (fork YOK):** üst düzey düğüm 110, kaynak satırı damgalanan
> **109**; başlık damgası doğrulaması **29 / 29**

`markdown`'s AST carries **no source positions at any level** — neither `Element`
nor `Line` has an offset. D4 (a checkbox ticked in the reading view writes to the
document), D13/D14 (outline, folding), D16 (anchors) and D5 (two-way scroll sync)
all need a node → source-line map. **No candidate renderer exposes one**, so this
layer is ours to build no matter which parser wins — which removes the main
reason to prefer a packaged renderer.

It is buildable **without forking**, and the prototype above proves it, using
four public seams:

| Seam | Why it is enough |
| ---- | ---------------- |
| `Line` is a plain subclassable class | `IndexedLine extends Line` carries its own index |
| `Document.parseLineList(List<Line>)` is public | we hand in the indexed lines |
| `BlockParser.lines` / `.current` are public | a wrapping syntax can read the current index |
| `Document(withDefaultBlockSyntaxes: false)` | lets us supply the **whole** syntax list, each one decorated |
| `Element.attributes` is a mutable `Map<String,String>` | the decorator stamps `data-line` / `data-line-end` |

Packaged renderers (`flutter_markdown_plus` (+`_latex`), `markdown_widget`,
`gpt_markdown`, `flutter_smooth_markdown`) lose on the same two counts: none
gives the position map, and all would need their default styles overridden
wholesale to satisfy D7. Owning the widget tree costs one layer we were going to
write anyway and buys D8 (per-box horizontal scroll), D9 (copy button), D10
(inert HTML and URI policy) and D11 (honest per-node fallback) as ordinary
widget work.

### 3. Math — a rendering package, chosen against the fixture

Math is drawn for real (owner's decision, round 17 follow-up). The engine must
paint in pure Flutter with **no JS engine and no web view** (D10), work on all
six platforms, and take its colours from `AwTokens`. A new dependency category →
this ADR is its justification (AGENTS §1.6).

**Resolved in OPH-247 by resolution, not by reading feature lists:**
`flutter pub add --dry-run flutter_markdown_plus_latex` pulls **ten** new
packages and brings `flutter_math_fork` in *anyway*, on top of
`flutter_markdown_plus` — the renderer §2 already declined. The companion is a
bridge to a renderer we do not use, so we take the engine directly: **eight**
new packages instead of ten.

The cost is written down rather than glossed: `flutter_math_fork` drags
`flutter_svg`, `vector_graphics` (×3), `provider`, `nested` and `tuple` along.
The measured bundle contribution is recorded under OPH-247 in TASKS.

### 3b. Syntax highlighting — `highlight` as a lexer, colours ours

Added 2026-08-10 during OPH-247. The original ADR settled math and forgot this,
even though D9 requires it; the gap is closed here rather than decided silently
in a widget file.

**`highlight` (the pure-Dart lexer), not `flutter_highlight`.** All the latter
adds is a widget plus ready-made theme maps, and D7 forbids a package's own
colours outright — so the theme half is dead weight and the widget half is work
we are doing anyway. The lexer's ~30 class names collapse onto **six**
`AwTokens.code*` inks; a palette nobody can tell apart is worse than one colour,
and six is what stayed distinguishable *and* above 4.5:1 on the code panel in
both themes.

**Grammars are registered explicitly**, through `highlight_core.dart`. The
all-in-one entry point registers all 190 languages — **1.9 MB** of Dart source
that cannot be tree-shaken, because every grammar is referenced by its own
registration. The nineteen we ship come to **128 KB**, a 15× difference for a
list that covers what a task app's users actually paste.

The package has no public way to ask whether a language is registered, and
`parse()` silently falls back to plaintext for a name it does not know — so an
unregistered grammar would produce a *successful but colourless* result that
nobody would notice. We keep our own set of registered names and check that.

### 4. Diagrams — flowchart and sequence are drawn; the rest degrade honestly

Mermaid is drawn from a parsed AST (owner's decision). v1 draws
**`flowchart`/`graph`** (TD/TB/LR/RL/BT) and **`sequenceDiagram`**. Every other
diagram type — class, state, ER, gantt, pie, journey — renders as D11's honest
placeholder: the source plus the reason.

The line is drawn there because the costs differ by an order of magnitude: a
sequence diagram is participants-as-columns and messages-as-rows, essentially
linear; a flowchart is a layered graph-drawing problem (rank assignment →
crossing-reduction ordering → coordinate assignment → edge routing). Mermaid
needs no parser extension — it arrives as a fenced code block with a `mermaid`
info string, which the measurement confirms is already captured
(`language-mermaid`). This is render-time work, and it gets its own task
(**OPH-254**) so it cannot quietly consume OPH-247.

**Written exit:** if the flowchart layout is not good enough to ship, OPH-254
falls back to the D11 placeholder and amends this ADR with the reason. It is not
left half-finished.

## Alternatives considered

**Option A — Delta canonical, custom embeds per block.** Rejected. It means
inventing a private document format, hand-writing an editor per block type, and
growing a branch per block in *both* converters, with OPH-241's round-trip
guarantee getting harder each time. MARKDOWN.md row 7 is the cautionary tale: an
abandoned WYSIWYG markdown editor is the normal outcome. It also cannot satisfy
W4 — every note would be Delta, so writing back to somebody's file would always
risk a reflow.

**Option B — markdown canonical everywhere.** Rejected for v1, and it is the
closest call. It makes the note and the file the same thing, which is exactly
what "open, edit, save back" wants. But it migrates every existing note, and
round-tripping a hand-formatted file through a rich text editor reflows it — the
lossy direction users notice. Option C keeps B's win where it matters (files stay
byte-faithful) without the migration.

**A packaged renderer.** Rejected on the position map, not on features. See §2.

**Mermaid through a web view.** Rejected outright by D10 and never measured. An
untrusted document plus a JS engine on the reading path is the exact shape §24
AI6 exists to prevent.

## Consequences

**Easier.** Every D6 feature becomes renderer work in one place instead of model
work in two converters. Files opened from disk stay byte-identical, so W4 is
satisfiable. Existing notes are untouched. The `markdown` package covers 19 of 22
measured items on day one.

**Harder.** Two formats live in one table, and the conversion door needs one
honest sentence a non-technical user can read. The position-map layer is ours to
build and maintain. Three custom syntaxes (math, `==highlight==`, front matter)
are ours. A flowchart layout engine is ours.

**Follow-ups this creates.**

- OPH-247 promotes `markdown` to a **direct** dependency, builds the parse +
  position layer, and picks the math engine.
- OPH-254 builds the mermaid subset.
- OPH-248 adds the `content_format` column (API migration + drift v17) and the
  three modes. **DESIGN §29 D1 is amended in that task:** under this model a note
  exposes two of the three modes, and the third is reached through the named
  conversion action rather than a disabled button (§22 forbids dead
  affordances).
- OPH-251 gates "Save to file" on `content_format == 'markdown'` (W4).

## Enforcement

- `apps/app/test/fixtures/markdown_conformance.md` is the referee for OPH-246 and
  the regression net for OPH-247; every feature in it gets a **structural**
  assert (which widget was built), not a golden.
- `scripts/markdown/measure_coverage.dart` reproduces the numbers in §2. **OPH-247
  converts it into `test/features/notes/markdown_coverage_test.dart`** once
  `markdown` is a direct dependency, so a package upgrade that drops a syntax
  fails CI instead of silently narrowing the viewer.
- `content_format` is constrained at the schema level with a default of `'delta'`.
- D7 is enforced the way Rule 11 already is: no raw hex and no `Colors.*` in the
  renderer, and `python3 scripts/design/contrast.py` prints `FAILURES: 0` in both
  themes.
- D10 is enforced by running Epic 20's `test/fixtures/ai_redteam.json` corpus
  embedded **inside a markdown document**: zero live HTML, zero tappable
  `javascript:`.
