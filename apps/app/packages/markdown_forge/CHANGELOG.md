# Changelog

## 0.1.0

First extraction, from [AllisWell](https://github.com/mahirozdin/alliswell)
(OPH-274 / ADR-0033), where every part of this package shipped and was tested
in production screens first.

- `MarkdownView` — a hand-written GFM widget tree over the `markdown` parser,
  carrying a node → source-line map: tables, task lists, footnotes, alerts,
  fenced code with copy buttons, KaTeX math, Mermaid flowcharts and sequence
  diagrams, front-matter strips, heading folding.
- `ReadingMode` — the renderer plus an outline (side panel ≥ 900 px, sheet
  below), scroll-synced current-section highlight and `#anchor` jumps.
- `MdSourceController` — live syntax in an ordinary `TextField`: headings
  sized in the field, bold bold, markers dimmed off the caret's line. Never
  hidden — the controller returns every character of `text`, by contract.
- `SourceMode` — the editor surface: split preview with two-way scroll sync,
  focus mode, find & replace, slash menu, ⌘K command palette, list
  auto-continuation, smart paste.
- `MarkdownForge` seams: `MarkdownTheme`, `MarkdownStrings` (with a fold hook
  for locales the default lowercase gets wrong), `MarkdownImageResolver`, and
  a link-scheme allowlist.
