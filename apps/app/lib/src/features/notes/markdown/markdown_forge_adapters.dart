/// Where AllisWell plugs into `markdown_forge` (OPH-274).
///
/// The renderer and the source editor moved into a package so other Flutter
/// apps can use them. What kept them from being a package was three things
/// they reached for out of the ambient application: the design tokens, the
/// localization layer and the riverpod container. This file is the whole of
/// what replaced those — everything AllisWell-specific about drawing a
/// markdown document now lives here, in one place a reader can hold.
///
/// The compiler enforces it: the package cannot see `AwTokens`, `.tr()` or
/// `ProviderScope`, so a future change that reaches for one of them fails to
/// build rather than quietly re-coupling.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_forge/markdown_forge.dart';

import '../../../core/fold.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../files/providers.dart';
import '../../files/ui/image_viewer.dart';
import '../../files/ui/note_media.dart' show fileIdFromEmbedSource;

/// Wraps a subtree with AllisWell's answers to the package's three questions.
///
/// A `ConsumerWidget` because one of the three — resolving
/// `alliswell://file/{id}` to a minted URL — genuinely needs the container.
/// The other two are pure reads.
class AwMarkdownScope extends ConsumerWidget {
  const AwMarkdownScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MarkdownForge(
    theme: awMarkdownTheme(context),
    strings: awMarkdownStrings(),
    imageResolver: (source, alt) => _resolveImage(ref, source, alt),
    // ADR-0016: `alliswell://` is in-app navigation, not the web, and it is on
    // the allowlist for that reason. An allowlist rather than a denylist —
    // the next scheme nobody thought of (`vbscript:`, `intent:`, `blob:`) is
    // the one that matters (DESIGN §29 D10).
    linkSchemes: const {'http', 'https', 'mailto', 'alliswell'},
    child: child,
  );
}

/// Rule 11, expressed as the package's theme.
///
/// Every colour a rendered document uses is resolved here, from `AwTokens` or
/// the `ColorScheme`, and `scripts/design/contrast.py` measures the pairs. The
/// alert accents colour the ICON and the EDGE, never the body text: an amber
/// warning on its own tinted card measures 2.96:1, which is why the card's
/// text stays `onSurface` and clears 13:1.
MarkdownTheme awMarkdownTheme(BuildContext context) {
  final theme = Theme.of(context);
  final tokens = context.awTokens;
  final scheme = theme.colorScheme;
  final text = theme.textTheme;

  return MarkdownTheme(
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
    hairline: tokens.hairline,
    link: tokens.link,
    muted: scheme.onSurfaceVariant,
    accent: scheme.onSurface,
    surface: scheme.surface,
    onSurface: scheme.onSurface,
    info: tokens.link,
    success: tokens.success,
    warning: tokens.warning,
    danger: scheme.error,
    mark: tokens.warning.withValues(alpha: 0.22),
    codeKeyword: tokens.codeKeyword,
    codeString: tokens.codeString,
    codeComment: tokens.codeComment,
    codeNumber: tokens.codeNumber,
    codeName: tokens.codeName,
    codeMeta: tokens.codeMeta,
  );
}

/// Every word the renderer and editor show, from our own locale files.
///
/// `fold` is the one that is not just a translation: ADR-0013's Turkish fold
/// maps `ı→i`, `İ→i`, `ş→s`… which neither SQLite nor MySQL does, and which a
/// package cannot assume. Without it, typing "baslik" in the command palette
/// would not find "Başlık".
MarkdownStrings awMarkdownStrings() => MarkdownStrings(
  copy: 'markdown.copyCode'.tr(),
  copied: 'markdown.copied'.tr(),
  outline: 'note.outline'.tr(),
  noHeadings: 'note.outlineEmpty'.tr(),
  find: 'note.find'.tr(),
  replace: 'note.replace'.tr(),
  replaceAll: 'note.replaceAll'.tr(),
  close: 'common.close'.tr(),
  next: 'common.next'.tr(),
  previous: 'common.previous'.tr(),
  searchCommands: 'note.paletteHint'.tr(),
  noCommands: 'note.paletteEmpty'.tr(),
  noMatches: 'note.noMatches'.tr(),
  sourceHint: 'note.sourceHint'.tr(),
  focusOn: 'note.focusOn'.tr(),
  focusOff: 'note.focusOff'.tr(),
  splitOn: 'note.splitOn'.tr(),
  splitOff: 'note.splitOff'.tr(),
  unsupportedBlock: 'markdown.unsupportedBlock'.tr(),
  brokenImage: 'markdown.image'.tr(),
  relativeImage: 'markdown.relativeImage'.tr(),
  frontMatter: 'markdown.frontMatter'.tr(),
  badMath: 'markdown.badMath'.tr(),
  rawHtml: 'markdown.rawHtml'.tr(),
  diagramUnreadable: 'markdown.mermaidUnreadable'.tr(),
  diagramUnsupportedTemplate: 'markdown.mermaidUnsupported'.tr(
    args: {'type': '{type}'},
  ),
  matchCountTemplate: 'note.matchCount'.tr(
    args: {'index': '{index}', 'total': '{total}'},
  ),
  countsTemplate: 'note.counts'.tr(
    args: {'words': '{words}', 'characters': '{characters}'},
  ),
  tableHeader: 'note.action.tableHeader'.tr(),
  actionLabels: {
    for (final action in mdActions())
      action.id: 'note.action.${action.id}'.tr(),
  },
  alertLabels: {
    for (final kind in MdAlertKind.values)
      kind.name: 'markdown.alert.${kind.name}'.tr(),
  },
  fold: foldSearchText,
);

/// `![](alliswell://file/{id})` → a minted URL (ADR-0011: a stable id, NEVER a
/// presigned URL — those expire). Offline or gone resolves to unresolvable, so
/// the renderer draws its honest placeholder instead of a broken-image glyph.
MarkdownImage _resolveImage(WidgetRef ref, String source, String alt) {
  final fileId = fileIdFromEmbedSource(source);
  if (fileId == null) {
    // http(s) is drawn here too, not left to the package's default. The
    // default builds a bare `NetworkImage`, which is correct for a package
    // with no opinions and wrong for us: every image in this app goes through
    // `networkImageProvider`, which is the seam the widget tests replace.
    // Letting one class of image slip past it means a test suite that quietly
    // makes real HTTP calls.
    final plain = defaultImageResolver(source, alt);
    if (plain is! MarkdownImageUrl) return plain;
    return MarkdownImageWidget(
      (context) => Consumer(
        builder: (context, ref, _) => Image(
          image: ref.watch(networkImageProvider)(plain.url),
          fit: BoxFit.contain,
          errorBuilder: (context, _, _) => MdImageChip(
            icon: Icons.broken_image_outlined,
            label: alt.isNotEmpty ? alt : context.mdStrings.brokenImage,
          ),
        ),
      ),
    );
  }
  // A widget rather than a URL, because minting one is ASYNCHRONOUS and the
  // resolver is not. Which also means "this file is gone" is discovered in
  // here, after the resolver has already answered — hence the chip.
  return MarkdownImageWidget(
    (context) => Consumer(
      builder: (context, ref, _) => ref
          .watch(fileUrlProvider(fileId))
          .maybeWhen(
            data: (url) => url == null
                ? MdImageChip(
                    icon: Icons.broken_image_outlined,
                    // The document's own word for the picture, which for an
                    // AllisWell embed is the file's name at insert time.
                    label: alt.isNotEmpty ? alt : context.mdStrings.brokenImage,
                  )
                : Image(
                    image: ref.watch(networkImageProvider)(url),
                    fit: BoxFit.contain,
                    // D11: a broken image says so where it stands. Without
                    // this the load failure escapes as an unhandled exception
                    // and the reader gets a red box.
                    errorBuilder: (context, _, _) => MdImageChip(
                      icon: Icons.broken_image_outlined,
                      label: alt.isNotEmpty
                          ? alt
                          : context.mdStrings.brokenImage,
                    ),
                  ),
            orElse: () => const SizedBox(
              height: 48,
              width: 48,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
    ),
  );
}

/// The app's own image viewer, opened from a tap in a rendered document
/// (DESIGN §30 A7/A11). The package hands over the gallery in document order
/// and the index that was tapped; deciding what a viewer looks like was never
/// its business.
void awOpenMarkdownGallery(BuildContext context, MdGallery gallery) {
  final refs = <AwImageRef>[];
  var index = 0;
  for (final source in gallery.sources) {
    if (gallery.sources.indexOf(source) == gallery.index) index = refs.length;
    final fileId = fileIdFromEmbedSource(source);
    refs.add(fileId != null ? AwImageRef.file(fileId) : AwImageRef.url(source));
  }
  if (refs.isEmpty) return;
  showAwImageViewer(context, images: refs, initialIndex: index);
}
