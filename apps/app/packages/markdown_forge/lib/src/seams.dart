/// The three things this package refuses to decide for you.
///
/// A markdown renderer that reaches for a host application's design tokens,
/// its localization layer and its dependency-injection container is not a
/// package — it is a folder that happens to live somewhere else. These are the
/// seams that make the difference, and each one has a default so the package
/// works out of the box with `MarkdownForge()` around nothing at all.
///
///  * [MarkdownTheme] — colours and type. Defaults to the ambient
///    `ColorScheme`/`TextTheme`, so it inherits whatever Material you already
///    configured. AllisWell substitutes its own tokens (Rule 11).
///  * [MarkdownStrings] — every word the widgets show. Defaults to English.
///  * [MarkdownImageResolver] — how `![](something)` becomes bytes. Defaults
///    to "http(s) only", so a custom scheme is opt-in rather than a hole.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colours and type for rendered markdown.
///
/// Every value the widgets paint with comes from here, which is what lets a
/// host enforce its own contrast rules: AllisWell's `contrast.py` measures the
/// pairs it supplies, and the package never writes a hex of its own.
@immutable
class MarkdownTheme {
  const MarkdownTheme({
    required this.body,
    required this.h1,
    required this.h2,
    required this.h3,
    required this.h4,
    required this.code,
    required this.codePanel,
    required this.tableHeaderFill,
    required this.hairline,
    required this.link,
    required this.muted,
    required this.accent,
    required this.surface,
    required this.onSurface,
    required this.info,
    required this.success,
    required this.warning,
    required this.danger,
    required this.mark,
    required this.codeKeyword,
    required this.codeString,
    required this.codeComment,
    required this.codeNumber,
    required this.codeName,
    required this.codeMeta,
  });

  /// The theme a host gets for free: Material's own scheme, read once.
  factory MarkdownTheme.of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_MarkdownScope>()
        ?.theme;
    if (inherited != null) return inherited;
    return MarkdownTheme.fromMaterial(Theme.of(context));
  }

  /// Derived from an ambient [ThemeData] — the zero-configuration path.
  factory MarkdownTheme.fromMaterial(ThemeData theme) {
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    return MarkdownTheme(
      // A document is body text, so the base is a reading size; headings come
      // off the type scale rather than from ad-hoc numbers.
      body: text.bodyLarge!.copyWith(height: 1.55),
      h1: text.headlineMedium!.copyWith(fontWeight: FontWeight.w700),
      h2: text.headlineSmall!.copyWith(fontWeight: FontWeight.w700),
      h3: text.titleLarge!.copyWith(fontWeight: FontWeight.w600),
      h4: text.titleMedium!.copyWith(fontWeight: FontWeight.w600),
      code: text.bodyMedium!.copyWith(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
        height: 1.45,
      ),
      codePanel: scheme.surfaceContainerHighest,
      tableHeaderFill: scheme.surfaceContainerLow,
      hairline: scheme.outlineVariant,
      link: scheme.primary,
      muted: scheme.onSurfaceVariant,
      accent: scheme.onSurface,
      surface: scheme.surface,
      onSurface: scheme.onSurface,
      info: scheme.primary,
      success: scheme.tertiary,
      warning: scheme.secondary,
      danger: scheme.error,
      mark: scheme.secondary.withValues(alpha: 0.22),
      // Six roles, not a full editor palette. A syntax scheme a reader cannot
      // tell apart is decoration; six categories is what distinguishes code
      // from prose without pretending to be an IDE.
      codeKeyword: scheme.primary,
      codeString: scheme.tertiary,
      codeComment: scheme.onSurfaceVariant,
      codeNumber: scheme.secondary,
      codeName: scheme.onSurface,
      codeMeta: scheme.onSurfaceVariant,
    );
  }

  final TextStyle body;
  final TextStyle h1;
  final TextStyle h2;
  final TextStyle h3;
  final TextStyle h4;
  final TextStyle code;
  final Color codePanel;
  final Color tableHeaderFill;
  final Color hairline;
  final Color link;
  final Color muted;

  /// Heading ink, and the strong ink live syntax uses in the editor.
  final Color accent;
  final Color surface;
  final Color onSurface;

  /// The five GFM alert accents (`> [!NOTE]` … `> [!CAUTION]`).
  ///
  /// They colour the ICON and the EDGE, never the body text. That is not a
  /// style preference: a warning amber on its own tinted card measures under
  /// 3:1 in a light theme, which is why the card's text stays [onSurface].
  final Color info;
  final Color success;
  final Color warning;
  final Color danger;

  /// The fill behind `==highlighted==` text.
  final Color mark;

  final Color codeKeyword;
  final Color codeString;
  final Color codeComment;
  final Color codeNumber;
  final Color codeName;
  final Color codeMeta;
}

/// Every word the package can put on screen.
///
/// One flat class rather than a delegate: a host that wants to translate this
/// already has a translation layer, and asking it to implement an interface
/// buys nothing over handing it a bag of strings.
@immutable
class MarkdownStrings {
  const MarkdownStrings({
    this.copy = 'Copy',
    this.copied = 'Copied',
    this.outline = 'Outline',
    this.noHeadings = 'No headings',
    this.find = 'Find',
    this.replace = 'Replace',
    this.replaceAll = 'Replace all',
    this.close = 'Close',
    this.next = 'Next',
    this.previous = 'Previous',
    this.commands = 'Commands',
    this.searchCommands = 'Search commands…',
    this.words = 'words',
    this.characters = 'characters',
    this.sourceHint = 'Write in Markdown…',
    this.focusOn = 'Focus mode',
    this.focusOff = 'Focus mode on',
    this.splitOn = 'Split view',
    this.splitOff = 'Split view on',
    this.unsupportedBlock = 'This block cannot be drawn here',
    this.brokenImage = 'Image',
    this.relativeImage = 'Relative image',
    this.frontMatter = 'Properties',
    this.badMath = 'This formula could not be read',
    this.rawHtml = 'HTML, shown as source',
    this.diagramUnreadable = 'This diagram could not be read',
    this.noMatches = 'No matches',
    this.noCommands = 'No commands',
    this.tableHeader = 'Heading',
    this.diagramUnsupportedTemplate =
        'Diagrams of type {type} are not drawn here',
    this.actionLabels = const {},
    this.alertLabels = const {
      'note': 'Note',
      'tip': 'Tip',
      'important': 'Important',
      'warning': 'Warning',
      'caution': 'Caution',
    },
    this.matchCountTemplate = '{index} of {total}',
    this.countsTemplate = '{words} words · {characters} characters',
    this.fold = defaultFold,
  });

  factory MarkdownStrings.of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MarkdownScope>()?.strings ??
      const MarkdownStrings();

  final String copy;
  final String copied;
  final String outline;
  final String noHeadings;
  final String find;
  final String replace;
  final String replaceAll;
  final String close;
  final String next;
  final String previous;
  final String commands;
  final String searchCommands;
  final String words;
  final String characters;
  final String sourceHint;
  final String focusOn;
  final String focusOff;
  final String splitOn;
  final String splitOff;
  final String unsupportedBlock;
  final String brokenImage;
  final String relativeImage;
  final String frontMatter;
  final String badMath;
  final String rawHtml;
  final String diagramUnreadable;
  final String noMatches;
  final String noCommands;

  /// The header cell a `/table` insert types into the user's DOCUMENT — the
  /// one string here that is not shown in a widget, and therefore the one a
  /// hardcoded-string linter cannot catch. It shipped as Turkish in an
  /// English app for a whole round for exactly that reason.
  final String tableHeader;

  /// `{type}` is replaced with the diagram kind we could not draw.
  final String diagramUnsupportedTemplate;

  String diagramUnsupported(String type) =>
      diagramUnsupportedTemplate.replaceAll('{type}', type);

  /// Toolbar/slash labels by action id (`bold`, `h1`, `table`…). Anything
  /// missing falls back to the id, which is ugly on purpose — a silently
  /// English button in a translated app is harder to notice than a wrong one.
  final Map<String, String> actionLabels;

  /// GFM alert headers, by `> [!KIND]` name.
  final Map<String, String> alertLabels;

  /// How the command palette compares what you typed against a label.
  ///
  /// A seam because case folding is not universal: AllisWell folds Turkish
  /// (ADR-0013), where `I`/`ı` and `İ`/`i` pair the opposite way from every
  /// other locale, and neither SQLite nor MySQL gets it right. The default is
  /// plain lowercase, which is correct for most languages and wrong quietly
  /// for a few — hence the hook.
  final String Function(String) fold;

  /// `{index}` / `{total}` — the find bar's position readout.
  final String matchCountTemplate;

  /// `{words}` / `{characters}` — the always-available count strip (D22).
  final String countsTemplate;

  String matchCount(int index, int total) => matchCountTemplate
      .replaceAll('{index}', '$index')
      .replaceAll('{total}', '$total');

  String counts(int words, int characters) => countsTemplate
      .replaceAll('{words}', '$words')
      .replaceAll('{characters}', '$characters');

  String action(String id) => actionLabels[id] ?? id;
  String alert(String kind) => alertLabels[kind] ?? kind;
}

String defaultFold(String value) => value.toLowerCase().trim();

/// What an image source resolves to.
sealed class MarkdownImage {
  const MarkdownImage();
}

/// Fetch it over the network.
class MarkdownImageUrl extends MarkdownImage {
  const MarkdownImageUrl(this.url);
  final String url;
}

/// The host will paint it — a file it owns, a cached asset, anything.
class MarkdownImageWidget extends MarkdownImage {
  const MarkdownImageWidget(this.builder);
  final WidgetBuilder builder;
}

/// Nothing can be shown; the renderer draws an honest labelled chip.
class MarkdownImageUnresolvable extends MarkdownImage {
  const MarkdownImageUnresolvable();
}

/// Turns a markdown image `![alt](source)` into something drawable.
///
/// The seam that keeps the package free of a DI container. AllisWell resolves
/// its own `alliswell://file/{id}` scheme through riverpod here; the default
/// resolves http(s) and refuses everything else, so a document from a stranger
/// cannot reach a scheme the host never opted into.
///
/// [alt] travels with it because a resolver that fails ASYNCHRONOUSLY has to
/// label its own placeholder, and the alt text is the only name the document
/// actually gives the picture.
typedef MarkdownImageResolver =
    MarkdownImage Function(String source, String alt);

MarkdownImage defaultImageResolver(String source, [String alt = '']) {
  final uri = Uri.tryParse(source.trim());
  if (uri == null || !uri.hasScheme) return const MarkdownImageUnresolvable();
  return uri.scheme == 'http' || uri.scheme == 'https'
      ? MarkdownImageUrl(source)
      : const MarkdownImageUnresolvable();
}

/// What a paste actually contains.
///
/// [imageBytes] is the case Flutter alone cannot give you: its clipboard
/// platform channel implements `text/plain` and nothing else, so
/// `Clipboard.getData('text/html')` returns null on EVERY platform — a branch
/// that reads like a feature and has never once run. A host that wants HTML or
/// images has to reach the pasteboard itself.
@immutable
class MarkdownPaste {
  const MarkdownPaste({this.html, this.text, this.imageBytes, this.imageName});

  /// HTML flavour, if the clipboard had one. Converted with `htmlToMarkdown`.
  final String? html;

  /// Plain text flavour.
  final String? text;

  /// Raw image bytes, if the clipboard held a picture.
  final Uint8List? imageBytes;

  /// A name to give it — the alt text and the uploaded file's name.
  final String? imageName;

  bool get isEmpty =>
      (html?.isEmpty ?? true) &&
      (text?.isEmpty ?? true) &&
      (imageBytes?.isEmpty ?? true);
}

/// Reads the clipboard for [SourceMode].
///
/// The seam exists because the useful flavours are out of Flutter's reach
/// (see [MarkdownPaste.imageBytes]) and reaching them is a PLATFORM-CHANNEL
/// decision the host has already made once — AllisWell pastes through its own
/// `alliswell_docref` plugin rather than adding a package that would drag a
/// Rust toolchain into six platform builds.
typedef MarkdownClipboardReader = Future<MarkdownPaste> Function();

/// What a host does with a pasted image: upload it, then return the markdown
/// to insert (`![alt](your-scheme://…)`), or null if it could not.
///
/// Two steps, because only the host can do either: the bytes have to go
/// somewhere, and only the host knows what URL scheme its renderer resolves.
///
/// Passed to [SourceMode] rather than to [MarkdownForge]: where an upload
/// LANDS depends on the document being edited, so this is per-instance state,
/// not ambient configuration.
typedef MarkdownImagePasteHandler =
    Future<String?> Function(Uint8List bytes, String? name);

/// The default: plain text, which is all Flutter's own channel provides.
Future<MarkdownPaste> defaultClipboardReader() async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  return MarkdownPaste(text: data?.text);
}

/// Supplies the seams to everything beneath it.
///
/// Optional: every widget falls back to a sane default, so a host that wants
/// the renderer and nothing else can skip this entirely.
class MarkdownForge extends StatelessWidget {
  const MarkdownForge({
    super.key,
    required this.child,
    this.theme,
    this.strings,
    this.imageResolver,
    this.linkSchemes,
    this.clipboardReader,
  });

  final Widget child;
  final MarkdownTheme? theme;
  final MarkdownStrings? strings;
  final MarkdownImageResolver? imageResolver;

  /// Where a paste's HTML and image flavours come from. Defaults to plain text.
  ///
  /// Ambient, unlike [SourceMode.onPasteImage]: reading the pasteboard is the
  /// same operation everywhere in an app, while UPLOADING a pasted image
  /// depends on which document you are in.
  final MarkdownClipboardReader? clipboardReader;

  /// Schemes a rendered document may turn into a TAPPABLE link. An allowlist,
  /// never a denylist — the next scheme nobody thought of (`vbscript:`,
  /// `intent:`, `blob:`) is the one that matters.
  final Set<String>? linkSchemes;

  @override
  Widget build(BuildContext context) => _MarkdownScope(
    theme: theme,
    strings: strings,
    imageResolver: imageResolver,
    linkSchemes: linkSchemes,
    clipboardReader: clipboardReader,
    child: child,
  );
}

class _MarkdownScope extends InheritedWidget {
  const _MarkdownScope({
    required super.child,
    this.theme,
    this.strings,
    this.imageResolver,
    this.linkSchemes,
    this.clipboardReader,
  });

  final MarkdownTheme? theme;
  final MarkdownStrings? strings;
  final MarkdownImageResolver? imageResolver;
  final Set<String>? linkSchemes;
  final MarkdownClipboardReader? clipboardReader;

  @override
  bool updateShouldNotify(_MarkdownScope old) =>
      theme != old.theme ||
      strings != old.strings ||
      imageResolver != old.imageResolver ||
      linkSchemes != old.linkSchemes ||
      clipboardReader != old.clipboardReader;
}

extension MarkdownForgeContext on BuildContext {
  MarkdownTheme get mdTheme => MarkdownTheme.of(this);
  MarkdownStrings get mdStrings => MarkdownStrings.of(this);
  MarkdownImageResolver get mdImageResolver =>
      dependOnInheritedWidgetOfExactType<_MarkdownScope>()?.imageResolver ??
      defaultImageResolver;
  MarkdownClipboardReader get mdClipboardReader =>
      dependOnInheritedWidgetOfExactType<_MarkdownScope>()?.clipboardReader ??
      defaultClipboardReader;
  Set<String> get mdLinkSchemes =>
      dependOnInheritedWidgetOfExactType<_MarkdownScope>()?.linkSchemes ??
      const {'http', 'https', 'mailto'};
}

/// The 4 px spacing scale the layout is built on.
///
/// Geometry, not colour — so unlike [MarkdownTheme] this is a constant rather
/// than a seam. A host that disagrees about spacing is really asking for a
/// different renderer; a host that disagrees about colour is just theming, and
/// that one is injectable.
abstract final class MdSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x12 = 48;
}

/// Corner radii, concentric: a nested shape's radius ≈ parent − padding.
abstract final class MdRadius {
  static const double s = 12;
  static const double m = 16;
  static const double l = 20;
  static const double xl = 28;
}
