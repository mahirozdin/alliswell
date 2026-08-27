/// A GitHub-Flavored Markdown renderer and source editor for Flutter.
///
/// Two halves that are meant to be used together but do not require each
/// other: [MarkdownView] renders a parsed document, and [MdSourceController]
/// puts live syntax into an ordinary `TextField`.
///
/// What makes this different from the renderers already on pub.dev is that
/// every block knows the source LINE it came from ([MdBlock.startLine]).
/// Scroll sync, the outline, heading folding and tappable task lists all need
/// that map, and no package exposes one — which is why this widget tree is
/// hand-written over the `markdown` package's parser rather than borrowed.
///
/// It refuses to decide three things for you; see `seams.dart`.
library;

export 'src/seams.dart';

export 'src/render/md_parse.dart';
export 'src/render/md_syntaxes.dart';
export 'src/render/md_security.dart';
export 'src/render/md_theme.dart';
export 'src/render/md_outline.dart';
export 'src/render/md_scroll.dart';
export 'src/render/md_code_block.dart';
export 'src/render/md_table.dart';
export 'src/render/md_callout.dart';
export 'src/render/md_unsupported.dart';
export 'src/render/markdown_view.dart';
export 'src/render/reading_mode.dart';
export 'src/render/mermaid/mermaid_parse.dart';
export 'src/render/mermaid/mermaid_view.dart';
// The layout maths is exported because it is measured directly: a diagram
// engine whose only test is "does the widget build" is not tested.
export 'src/render/mermaid/flow_layout.dart';
export 'src/render/mermaid/sequence_layout.dart';

export 'src/edit/md_actions.dart';
export 'src/edit/md_bottom_room.dart';
export 'src/edit/md_editing.dart';
export 'src/edit/md_highlight.dart';
export 'src/edit/md_toolbar.dart';
export 'src/edit/md_command_palette.dart';
export 'src/edit/find_replace_bar.dart';
export 'src/edit/source_mode.dart';
