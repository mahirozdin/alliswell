import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../i18n/i18n.dart';
import '../../../search/global_search.dart';
import '../../../search/search_recents.dart';
import '../../../theme/tokens.dart';
import '../../files/ui/file_widgets.dart';
import '../data/ai_attachments.dart';
import 'ai_bubble_state.dart';

/// The "@" attach picker, the composer chips and the sent-message chips of
/// the AI chat (OPH-377, ADR-0058, DESIGN §41). The bubble owns the field and
/// the keyboard; these widgets only draw.

/// The kinds the picker offers, in its order (tags are not attachable).
const kAiMentionKinds = [
  GlobalSearchKind.note,
  GlobalSearchKind.file,
  GlobalSearchKind.task,
  GlobalSearchKind.project,
];

/// Recent rows shown for a bare "@".
const int kAiMentionRecentLimit = 8;

/// The picker's rows for [query]: the OPH-374 search everywhere (offline, the
/// fold registry, desk files and archived notes already excluded), regrouped
/// note → file → task → project; a bare "@" shows the recents instead.
final aiMentionItemsProvider = FutureProvider.autoDispose
    .family<List<GlobalSearchItem>, String>((ref, rawQuery) async {
      final query = rawQuery.trim();
      if (query.isEmpty) {
        final recents = await ref.watch(recentSearchItemsProvider.future);
        return [
          ...recents.where((i) => kAiMentionKinds.contains(i.kind)),
        ].take(kAiMentionRecentLimit).toList();
      }
      final groups = await ref.watch(globalSearchProvider(query).future);
      return [
        for (final kind in kAiMentionKinds)
          for (final group in groups)
            if (group.kind == kind) ...group.items,
      ];
    });

AiAttachmentKind? aiAttachmentKindOf(GlobalSearchKind kind) => switch (kind) {
  GlobalSearchKind.note => AiAttachmentKind.note,
  GlobalSearchKind.file => AiAttachmentKind.file,
  GlobalSearchKind.task => AiAttachmentKind.task,
  GlobalSearchKind.project => AiAttachmentKind.project,
  GlobalSearchKind.tag => null,
};

AiAttachmentRef? aiAttachmentRefFor(GlobalSearchItem item) {
  final kind = aiAttachmentKindOf(item.kind);
  if (kind == null) return null;
  return AiAttachmentRef(
    kind: kind,
    id: item.id,
    title: item.title,
    mime: item.mime,
  );
}

/// A file row is attachable only when it is text (ADR-0058: no extraction).
bool aiSearchItemIsText(GlobalSearchItem item) =>
    item.kind != GlobalSearchKind.file ||
    aiFileIsTextLike(item.title, item.mime ?? '');

IconData aiAttachKindIcon(AiAttachmentKind kind, String? mime) =>
    switch (kind) {
      AiAttachmentKind.note => Icons.sticky_note_2_outlined,
      AiAttachmentKind.task => Icons.check_circle_outline,
      AiAttachmentKind.project => Icons.folder_outlined,
      AiAttachmentKind.file => fileKindIcon(mime ?? ''),
    };

String _kindLabel(AiAttachmentKind kind) => switch (kind) {
  AiAttachmentKind.note => 'search.global.kinds.note'.tr(),
  AiAttachmentKind.file => 'search.global.kinds.file'.tr(),
  AiAttachmentKind.task => 'search.global.kinds.task'.tr(),
  AiAttachmentKind.project => 'search.global.kinds.project'.tr(),
};

String _groupLabel(GlobalSearchKind kind) => switch (kind) {
  GlobalSearchKind.task => 'search.global.groups.tasks'.tr(),
  GlobalSearchKind.project => 'search.global.groups.projects'.tr(),
  GlobalSearchKind.note => 'search.global.groups.notes'.tr(),
  GlobalSearchKind.tag => 'search.global.groups.tags'.tr(),
  GlobalSearchKind.file => 'search.global.groups.files'.tr(),
};

String _refusalText(AiAttachmentRefusal refusal) => switch (refusal) {
  AiAttachmentRefusal.notText => 'ai.attach.refused.notText'.tr(),
  AiAttachmentRefusal.tooLarge => 'ai.attach.refused.tooLarge'.tr(),
  AiAttachmentRefusal.unavailable => 'ai.attach.refused.unavailable'.tr(),
  AiAttachmentRefusal.empty => 'ai.attach.refused.empty'.tr(),
};

String _count(int n) =>
    NumberFormat.decimalPattern(AwI18n.instance.locale.toString()).format(n);

// ── the composer's pending chips ──────────────────────────────────────────

class AiPendingChips extends StatelessWidget {
  const AiPendingChips({
    super.key,
    required this.pending,
    required this.onRemove,
  });

  final List<AiAttachment> pending;
  final ValueChanged<AiAttachmentRef> onRemove;

  @override
  Widget build(BuildContext context) {
    if (pending.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final refused = pending.where((a) => a.refusal != null).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: AwSpace.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AwSpace.x2,
            runSpacing: AwSpace.x1,
            children: [for (final a in pending) _chip(context, a)],
          ),
          for (final a in refused)
            Padding(
              padding: const EdgeInsets.only(top: AwSpace.x1),
              child: Text(
                '${a.ref.title}: ${_refusalText(a.refusal!)}',
                key: Key('ai-attach-refusal-${a.ref.id}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, AiAttachment a) {
    final scheme = Theme.of(context).colorScheme;
    final Widget avatar;
    switch (a.status) {
      case AiAttachmentStatus.loading:
        avatar = Semantics(
          label: 'ai.attach.loading'.tr(),
          child: const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case AiAttachmentStatus.refused:
        avatar = Icon(Icons.error_outline, size: 18, color: scheme.error);
      case AiAttachmentStatus.ready:
        avatar = Icon(aiAttachKindIcon(a.ref.kind, a.ref.mime), size: 18);
    }
    final label = a.truncated
        ? '${a.ref.title} · ${'ai.attach.truncated'.tr()}'
        : a.ref.title;
    return Semantics(
      label: '${_kindLabel(a.ref.kind)}: $label',
      child: InputChip(
        key: Key('ai-attach-chip-${a.ref.id}'),
        avatar: avatar,
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        onDeleted: () => onRemove(a.ref),
        deleteButtonTooltipMessage: 'ai.attach.remove'.tr(),
      ),
    );
  }
}

// ── the "@" picker panel ──────────────────────────────────────────────────

/// Inline above the composer — not a modal, so typing continues in the same
/// field (DESIGN §41 M2). A solid surface: glass never sits under text.
class AiMentionPanel extends StatelessWidget {
  const AiMentionPanel({
    super.key,
    required this.items,
    required this.active,
    required this.query,
    required this.loading,
    required this.attached,
    required this.limitReached,
    required this.onPick,
    required this.onHover,
    required this.maxHeight,
  });

  final List<GlobalSearchItem> items;
  final int active;
  final String query;
  final bool loading;
  final Set<AiAttachmentRef> attached;
  final bool limitReached;
  final ValueChanged<GlobalSearchItem> onPick;
  final ValueChanged<int> onHover;
  final double maxHeight;

  /// Whether [item] can be picked right now.
  static bool pickable(
    GlobalSearchItem item, {
    required Set<AiAttachmentRef> attached,
    required bool limitReached,
  }) {
    final ref = aiAttachmentRefFor(item);
    if (ref == null || limitReached) return false;
    if (!aiSearchItemIsText(item)) return false;
    return !attached.contains(ref);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String? hint;
    if (limitReached) {
      hint = 'ai.attach.limit'.tr();
    } else if (items.isEmpty && !loading) {
      hint = query.trim().isEmpty
          ? 'ai.attach.emptyHint'.tr()
          : 'ai.attach.noResults'.tr(args: {'query': query.trim()});
    }

    final rows = <Widget>[];
    GlobalSearchKind? lastKind;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (query.trim().isNotEmpty && item.kind != lastKind) {
        rows.add(_Header(label: _groupLabel(item.kind)));
        lastKind = item.kind;
      }
      rows.add(
        _MentionRow(
          item: item,
          active: i == active,
          enabled: pickable(
            item,
            attached: attached,
            limitReached: limitReached,
          ),
          isAttached: attached.contains(aiAttachmentRefFor(item)),
          onTap: () => onPick(item),
          onHover: () => onHover(i),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(AwSpace.x3, AwSpace.x2, AwSpace.x3, 0),
      child: Container(
        key: const Key('ai-mention-panel'),
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: AwSpace.x1),
            children: [
              Semantics(
                header: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AwSpace.x3,
                    AwSpace.x2,
                    AwSpace.x3,
                    AwSpace.x1,
                  ),
                  child: Text(
                    'ai.attach.panelTitle'.tr(),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              if (hint != null)
                Padding(
                  key: const Key('ai-mention-hint'),
                  padding: const EdgeInsets.fromLTRB(
                    AwSpace.x3,
                    AwSpace.x1,
                    AwSpace.x3,
                    AwSpace.x2,
                  ),
                  child: Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ...rows,
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AwSpace.x3,
          AwSpace.x2,
          AwSpace.x3,
          0,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// One picker row — the §40 P3 anatomy: kind icon, one-line title, context
/// line; the active row has a fill AND the ⏎ glyph (never colour alone). A
/// binary file row is drawn disabled with the reason as its context line.
class _MentionRow extends StatelessWidget {
  const _MentionRow({
    required this.item,
    required this.active,
    required this.enabled,
    required this.isAttached,
    required this.onTap,
    required this.onHover,
  });

  final GlobalSearchItem item;
  final bool active;
  final bool enabled;
  final bool isAttached;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ref = aiAttachmentRefFor(item);
    final isText = aiSearchItemIsText(item);
    final subtitle = !isText
        ? 'ai.attach.refused.notText'.tr()
        : isAttached
        ? 'ai.attach.attached'.tr()
        : item.context;
    final titleColor = enabled ? scheme.onSurface : scheme.onSurfaceVariant;
    final kind = ref?.kind ?? AiAttachmentKind.note;

    return MouseRegion(
      onHover: (_) => onHover(),
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: active,
        label: ['${_kindLabel(kind)}: ${item.title}', ?subtitle].join(', '),
        onTap: enabled ? onTap : null,
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: Key('ai-mention-${item.kind.name}-${item.id}'),
            onTap: enabled ? onTap : null,
            child: Ink(
              color: active ? scheme.surfaceContainerHighest : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AwSpace.x3,
                    vertical: AwSpace.x2,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        aiAttachKindIcon(kind, item.mime),
                        size: 22,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AwSpace.x3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: titleColor,
                              ),
                            ),
                            if (subtitle != null && subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AwSpace.x2),
                      SizedBox(
                        width: 20,
                        child: isAttached
                            ? Icon(
                                Icons.check,
                                size: 18,
                                color: scheme.onSurfaceVariant,
                              )
                            : active && enabled
                            ? Icon(
                                Icons.keyboard_return,
                                size: 18,
                                color: scheme.onSurfaceVariant,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── the sent message's attachments ────────────────────────────────────────

/// What rode along with a sent turn: small chips, then — when an item was cut
/// or left out — a plain line saying so (the user sees what the model saw).
class AiSentAttachments extends StatelessWidget {
  const AiSentAttachments({super.key, required this.entry});

  final AiChatEntry entry;

  @override
  Widget build(BuildContext context) {
    if (entry.attachments.isEmpty && entry.droppedAttachments.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notices = <String>[
      for (final a in entry.attachments)
        if (a.truncated)
          'ai.attach.truncatedNotice'.tr(
            args: {
              'title': a.ref.title,
              'shown': _count(a.sentChars),
              'total': _count(a.totalChars),
            },
          ),
      for (final d in entry.droppedAttachments)
        'ai.attach.droppedNotice'.tr(args: {'title': d.title}),
    ];
    return Padding(
      padding: const EdgeInsets.only(left: AwSpace.x8, bottom: AwSpace.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (entry.attachments.isNotEmpty)
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AwSpace.x1,
              runSpacing: AwSpace.x1,
              children: [
                for (final a in entry.attachments)
                  Semantics(
                    label: 'ai.attach.sentLabel'.tr(
                      args: {'title': a.ref.title},
                    ),
                    excludeSemantics: true,
                    child: Chip(
                      key: const Key('ai-sent-attachment'),
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(
                        aiAttachKindIcon(a.ref.kind, a.ref.mime),
                        size: 16,
                      ),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text(
                          a.truncated
                              ? '${a.ref.title} · ${'ai.attach.truncated'.tr()}'
                              : a.ref.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          for (final notice in notices)
            Padding(
              padding: const EdgeInsets.only(top: AwSpace.x1),
              child: Text(
                notice,
                key: const Key('ai-attach-notice'),
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
