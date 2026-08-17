/// Rendered markdown, styled from tokens (DESIGN §29 D7, OPH-247).
///
/// Rule 11 has no carve-out for third-party widgets, and this file is where
/// that is enforced: every colour a rendered document uses is resolved here,
/// from `MarkdownTheme` or the `ColorScheme`. Nothing downstream writes a hex.
///
/// The alert palette is the part worth reading twice. The five GFM types reuse
/// EXISTING roles rather than growing the palette — but the accent colours the
/// **icon and the edge**, never the body text. That is not a style preference:
/// an amber warning (#C77700) on its own tinted card measures **2.96:1**,
/// which is why its own doc comment calls it an icon colour. Body text stays
/// `onSurface` and clears 13:1. The tint is the accent at [kMdAlertTintAlpha]
/// over the surface, and `scripts/design/contrast.py` carries every one of
/// those pairs.
library;

import 'package:flutter/material.dart';
import '../seams.dart';

/// How strongly an alert card is tinted by its accent.
///
/// 10%, not 14%: at 14% the light-theme warning icon lands on 2.96:1 against
/// its own card and fails the >= 3:1 icon threshold. Measured, not chosen.
const double kMdAlertTintAlpha = 0.10;

/// The five GFM alert types (`> [!NOTE]` … `> [!CAUTION]`).
enum MdAlertKind { note, tip, important, warning, caution }

/// Everything a rendered document needs to draw itself, resolved once per
/// build instead of at every node.
@immutable
class MdStyles {
  const MdStyles({
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
    required this.tokens,
    required this.scheme,
  });

  factory MdStyles.of(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.mdTheme;
    final scheme = theme.colorScheme;
    final text = theme.textTheme;

    // A document is body text, so the base is the reading size the rest of the
    // app uses; headings come off the type scale rather than from ad-hoc sizes.
    return MdStyles(
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
      tokens: tokens,
      scheme: scheme,
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
  final MarkdownTheme tokens;
  final ColorScheme scheme;

  TextStyle headingFor(int level) => switch (level) {
    1 => h1,
    2 => h2,
    3 => h3,
    _ => h4,
  };

  /// The accent that colours an alert's icon and left edge (>= 3:1 on its own
  /// card). Never used for body text — see the library comment.
  Color alertAccent(MdAlertKind kind) => switch (kind) {
    MdAlertKind.note => scheme.primary,
    MdAlertKind.tip => tokens.success,
    MdAlertKind.important => scheme.secondary,
    MdAlertKind.warning => tokens.warning,
    MdAlertKind.caution => scheme.error,
  };

  Color alertTint(MdAlertKind kind) => Color.alphaBlend(
    alertAccent(kind).withValues(alpha: kMdAlertTintAlpha),
    scheme.surface,
  );

  IconData alertIcon(MdAlertKind kind) => switch (kind) {
    MdAlertKind.note => Icons.info_outline,
    MdAlertKind.tip => Icons.lightbulb_outline,
    MdAlertKind.important => Icons.priority_high,
    MdAlertKind.warning => Icons.warning_amber_outlined,
    MdAlertKind.caution => Icons.report_gmailerrorred_outlined,
  };

  /// i18n key for an alert's label. The type is never carried by colour alone —
  /// the card says "Not" / "Uyarı" in words as well.
  String alertLabel(BuildContext context, MdAlertKind kind) =>
      MarkdownStrings.of(context).alert(kind.name);

  /// highlight.js emits around thirty class names; they collapse onto six inks
  /// (see [MarkdownTheme.codeKeyword] and friends). A palette nobody can tell apart
  /// is worse than a single colour, and every one of the six is contrast-checked
  /// against [codePanel] in both themes.
  Color? codeInk(String? className) {
    if (className == null) return null;
    return switch (className) {
      'keyword' ||
      'literal' ||
      'type' ||
      'built_in' ||
      'selector-tag' => tokens.codeKeyword,
      'string' ||
      'regexp' ||
      'symbol' ||
      'quote' ||
      'addition' ||
      'template-variable' => tokens.codeString,
      'comment' || 'doctag' => tokens.codeComment,
      'number' || 'bullet' => tokens.codeNumber,
      'title' ||
      'name' ||
      'class' ||
      'function' ||
      'tag' ||
      'attr' ||
      'attribute' ||
      'variable' ||
      'selector-id' ||
      'selector-class' => tokens.codeName,
      'meta' ||
      'params' ||
      'deletion' ||
      'link' ||
      'section' ||
      'formula' => tokens.codeMeta,
      _ => null,
    };
  }
}

/// Reads the alert type out of the element the parser produced.
///
/// `AlertBlockSyntax` emits `<div class="markdown-alert markdown-alert-note">`
/// whose FIRST child is a `<p class="markdown-alert-title">` holding the
/// English word "Note". We take the type from the class and **drop that
/// paragraph**: this app ships Turkish, and a card that says "Note" above a
/// Turkish document is the kind of raw-English leak `check:i18n` cannot see
/// (round 10's lesson — its blind spot is text that never passes through a key).
MdAlertKind? mdAlertKindFrom(String? classAttribute) {
  if (classAttribute == null) return null;
  for (final kind in MdAlertKind.values) {
    if (classAttribute.contains('markdown-alert-${kind.name}')) return kind;
  }
  return null;
}

/// The class the parser puts on an alert's own English title paragraph.
const String kMdAlertTitleClass = 'markdown-alert-title';
