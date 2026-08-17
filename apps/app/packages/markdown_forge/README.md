# markdown_forge

A GitHub-Flavored Markdown **renderer** and **source editor** for Flutter —
the notes engine of [AllisWell](https://alliswell.space), extracted so any app
can use it.

## Why another markdown package?

Because every block knows the **source line it came from**. The widget tree is
hand-written over the `markdown` package's parser precisely to keep that map,
and it is what makes the features that need positions possible at all:

- **Scroll-synced outline** — a heading tree that follows the reader, as a
  side panel or a sheet, with `#anchor` jumps.
- **Heading folding** — session-only; folding never mutates the document.
- **Split view** — source and preview, scroll-synced both ways.
- **Live syntax while you type** (Obsidian/Typora style) inside an ordinary
  `TextField`: headings sized in the field, bold bold, `**` markers quiet
  unless the caret is on their line. Markers are dimmed, never hidden — a
  `TextEditingController` must return exactly the characters of its text, or
  every caret offset after the first difference points at the wrong character.

Also in the box: GFM tables, task lists, footnotes, alerts (`> [!NOTE]`),
fenced code with language labels and copy buttons, KaTeX math (pure Flutter,
no web view), Mermaid flowcharts and sequence diagrams (parsed AST, no JS
engine), YAML front-matter as a properties strip, a scrolling toolbar, slash
commands, a ⌘K command palette, find & replace, focus mode, and word counts.

**A document is untrusted input.** Raw HTML renders as inert source, link
schemes are an allowlist, and nothing on the reading path executes anything.

## Use

```dart
import 'package:markdown_forge/markdown_forge.dart';

// Rendering:
MarkdownView(document: parseMarkdown(source));

// Reading view with outline + folding:
ReadingMode(markdown: source);

// Editing with live syntax:
final controller = MdSourceController(text: source);
SourceMode(controller: controller);
```

It works with zero configuration — theme from your `ColorScheme`, English
labels, http(s) images. To supply your own, wrap once:

```dart
MarkdownForge(
  theme: MarkdownTheme.fromMaterial(Theme.of(context)), // or hand-built
  strings: MarkdownStrings(
    outline: 'İçindekiler',
    fold: myTurkishFold, // ı→i, İ→i… the default lowercase can't know this
  ),
  imageResolver: (source, alt) {
    final id = myScheme(source);
    if (id != null) return MarkdownImageWidget((_) => MyImage(id));
    return defaultImageResolver(source, alt);
  },
  linkSchemes: {'http', 'https', 'mailto', 'myapp'},
  child: ...,
)
```

The three seams are deliberate: a renderer that reaches for a host's design
tokens, localization layer or DI container is not a package. `markdown_forge`
depends on `markdown`, `highlight` and `flutter_math_fork` — nothing else.

## License

MIT © BUBIAPSS BILGI TEKNOLOJILERI ARGE LIMITED SIRKETI
