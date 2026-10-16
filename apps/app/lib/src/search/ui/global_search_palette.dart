import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/persisted_prefs.dart';
import '../../features/ee/providers.dart' show canProvider;
import '../../features/files/providers.dart';
import '../../features/files/ui/file_widgets.dart';
import '../../features/quick_access/data/quick_link.dart';
import '../../features/quick_access/ui/quick_access_navigation.dart';
import '../../features/tags/tags.dart';
import '../../features/tasks/ui/task_create_sheet.dart';
import '../../i18n/i18n.dart';
import '../../router.dart';
import '../../sections.dart';
import '../../theme/tokens.dart';
import '../../widgets/status_views.dart';
import '../global_search.dart';
import '../search_recents.dart';
import 'global_search_entry.dart' show globalSearchShortcutLabel;

/// What the palette was closed WITH. The palette only chooses; the caller
/// acts, after the dialog is gone (LESSONS flutter-app: a dialog's own
/// context is dead the moment it pops).
sealed class GlobalSearchChoice {
  const GlobalSearchChoice();
}

final class GlobalSearchOpen extends GlobalSearchChoice {
  const GlobalSearchOpen(this.item);
  final GlobalSearchItem item;
}

final class GlobalSearchCreate extends GlobalSearchChoice {
  const GlobalSearchCreate(this.title);
  final String title;
}

/// The palette that is up, if one is. A second ⌘K/Ctrl+K closes it rather
/// than stacking another on top (DESIGN §40 P1).
DialogRoute<GlobalSearchChoice>? _openPalette;

/// Whether the palette is on screen — tests and the host read it.
bool get isGlobalSearchOpen => _openPalette != null;

/// Opens the palette on the ROOT navigator (above the shell's glass bar,
/// LESSONS flutter-app), or closes it when it is already the top route.
///
/// [ref] must outlive the palette: it is used AFTER the dialog pops, to open
/// a file's sheet or set Home's tag filter. The host's ref is that.
Future<void> showGlobalSearch(BuildContext context, WidgetRef ref) async {
  final open = _openPalette;
  // `isActive`: a palette whose navigator went away (a sign-out, a test's
  // teardown) never completed its future, and must not block the next one.
  if (open != null && open.isActive) {
    if (open.isCurrent) open.navigator?.pop();
    return;
  }
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<GlobalSearchChoice>(
    context: navigator.context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(
      navigator.context,
    ).modalBarrierDismissLabel,
    settings: const RouteSettings(name: 'global-search'),
    builder: (_) => const GlobalSearchPalette(),
  );
  _openPalette = route;
  GlobalSearchChoice? choice;
  try {
    choice = await navigator.push(route);
  } finally {
    _openPalette = null;
  }
  if (choice == null) return;
  final rootContext = awRootNavigatorKey.currentContext;
  if (rootContext == null || !rootContext.mounted) return;
  await openGlobalSearchChoice(rootContext, ref, choice);
}

/// The one impure step: performs [choice] from the root navigator's context.
Future<void> openGlobalSearchChoice(
  BuildContext context,
  WidgetRef ref,
  GlobalSearchChoice choice,
) async {
  switch (choice) {
    case GlobalSearchCreate(:final title):
      // The normal create sheet, title prefilled — never a silent write.
      await showTaskCreateSheet(context, initialTitle: title);
    case GlobalSearchOpen(:final item):
      await _openItem(context, ref, item);
  }
}

Future<void> _openItem(
  BuildContext context,
  WidgetRef ref,
  GlobalSearchItem item,
) async {
  final router = GoRouter.of(context);
  if (item.kind == GlobalSearchKind.tag) {
    // An explicit navigation, not search state (ADR-0055): Home, filtered by
    // this tag. The filter only exists in the list view, so a board-view
    // Home is switched to the list — otherwise the tap would land on a
    // screen where the tag means nothing.
    ref.read(tagFilterProvider.notifier).select(item.id);
    if (ref.read(homeViewProvider) == 'board') {
      unawaited(ref.read(homeViewProvider.notifier).set('list'));
    }
    unawaited(
      ref
          .read(searchRecentsProvider.notifier)
          .record(SearchRecent(item.kind, item.id)),
    );
    router.go(AppSection.home.path);
    return;
  }
  final destination = quickDestinationForTarget(switch (item.kind) {
    GlobalSearchKind.task => QuickKind.task,
    GlobalSearchKind.project => QuickKind.project,
    GlobalSearchKind.note => QuickKind.note,
    GlobalSearchKind.file || GlobalSearchKind.tag => QuickKind.file,
  }, item.id);
  switch (destination) {
    case QuickGo(:final location):
      router.go(location);
    case QuickPush(:final location):
      unawaited(router.push(location));
    case QuickFileSheet(:final fileId):
      // Files have no address; their actions sheet is their page (the Quick
      // Access rule), so the route tracker cannot see this visit — record it.
      unawaited(
        ref
            .read(searchRecentsProvider.notifier)
            .record(SearchRecent(item.kind, item.id)),
      );
      final file = await ref.read(fileByIdProvider(fileId).future);
      if (file == null || !context.mounted) return;
      await showFileActionsSheet(context, ref, file);
    case QuickExternal() || QuickBroken():
      return;
  }
}

/// The palette itself (DESIGN §40): a SOLID dialog surface (G1), a filled
/// field (G3), results grouped by kind, full keyboard navigation.
class GlobalSearchPalette extends ConsumerStatefulWidget {
  const GlobalSearchPalette({super.key});

  @override
  ConsumerState<GlobalSearchPalette> createState() =>
      _GlobalSearchPaletteState();
}

/// One selectable row: a result, a recent, or the create row.
class _Entry {
  const _Entry.item(GlobalSearchItem this.item) : create = null;
  const _Entry.create(String this.create) : item = null;

  final GlobalSearchItem? item;
  final String? create;
}

class _GlobalSearchPaletteState extends ConsumerState<GlobalSearchPalette> {
  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'global-search-field');
  final _scroll = ScrollController();

  /// The debounced query — what the results are FOR.
  String _query = '';
  Timer? _debounce;

  /// S4: a progress line only when the wait is real.
  Timer? _progressTimer;
  bool _progressDue = false;

  /// The last answered results, kept on screen while the next query loads —
  /// a list that blinks empty on every keystroke is unreadable.
  List<GlobalSearchGroup> _shown = const [];
  String _shownFor = '';

  int _active = 0;
  final _rowKeys = <int, GlobalKey>{};
  bool _chosen = false;

  static const _debounceDelay = Duration(milliseconds: 150);

  @override
  void dispose() {
    _debounce?.cancel();
    _progressTimer?.cancel();
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () {
      if (!mounted) return;
      _progressTimer?.cancel();
      _progressTimer = Timer(_debounceDelay, () {
        if (mounted) setState(() => _progressDue = true);
      });
      setState(() {
        _query = _controller.text.trim();
        _progressDue = false;
        _active = 0;
      });
    });
    // The clear button and the create row follow the TEXT, not the debounce.
    setState(() {});
  }

  void _clear() {
    _controller.clear();
    _onChanged('');
    _focus.requestFocus();
  }

  void _choose(GlobalSearchChoice choice) {
    // Enter can arrive twice on some platforms (the key and the IME action).
    if (_chosen) return;
    _chosen = true;
    Navigator.of(context).pop(choice);
  }

  void _openEntry(_Entry entry) {
    final item = entry.item;
    _choose(
      item != null ? GlobalSearchOpen(item) : GlobalSearchCreate(entry.create!),
    );
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _active = (_active + delta) % count);
    final key = _rowKeys[_active];
    final rowContext = key?.currentContext;
    if (rowContext != null) {
      Scrollable.ensureVisible(
        rowContext,
        duration: AwMotion.fast,
        alignmentPolicy: delta > 0
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 600;
    final text = _controller.text.trim();
    final canCreate = ref.watch(canProvider('tasks.create'));

    // ── what to show ──────────────────────────────────────────────────────
    final searching = _query.isNotEmpty;
    var loading = false;
    List<GlobalSearchItem> recents = const [];
    if (searching) {
      final async = ref.watch(globalSearchProvider(_query));
      if (async.hasValue && !async.isLoading) {
        _shown = async.value!;
        _shownFor = _query;
      }
      loading = async.isLoading || _shownFor != _query;
    } else {
      recents = ref.watch(recentSearchItemsProvider).value ?? const [];
    }
    final groups = searching ? _shown : const <GlobalSearchGroup>[];

    final entries = <_Entry>[
      if (!searching) ...[for (final item in recents) _Entry.item(item)],
      for (final group in groups) ...[
        for (final item in group.items) _Entry.item(item),
      ],
      if (text.isNotEmpty && canCreate) _Entry.create(text),
    ];
    if (_active >= entries.length) _active = 0;

    final field = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _move(1, entries.length),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _move(-1, entries.length),
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (entries.isNotEmpty) _openEntry(entries[_active]);
        },
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () {
          if (entries.isNotEmpty) _openEntry(entries[_active]);
        },
      },
      child: TextField(
        key: const Key('global-search-field'),
        controller: _controller,
        focusNode: _focus,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: _onChanged,
        onSubmitted: (_) {
          if (entries.isNotEmpty) _openEntry(entries[_active]);
        },
        decoration: InputDecoration(
          hintText: 'search.global.hint'.tr(),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  key: const Key('global-search-clear'),
                  tooltip: 'common.clear'.tr(),
                  icon: const Icon(Icons.close),
                  onPressed: _clear,
                ),
        ),
      ),
    );

    // ── the rows ──────────────────────────────────────────────────────────
    var index = 0;
    _rowKeys.clear();
    Widget row(_Entry entry) {
      final i = index++;
      final key = _rowKeys[i] = GlobalKey();
      final item = entry.item;
      return _PaletteRow(
        key: key,
        active: i == _active,
        item: item,
        createTitle: entry.create,
        onHover: () {
          if (_active != i) setState(() => _active = i);
        },
        onTap: () => _openEntry(entry),
      );
    }

    final children = <Widget>[];
    if (!searching && recents.isNotEmpty) {
      children.add(_GroupHeader(label: 'search.global.recent'.tr()));
      for (final item in recents) {
        children.add(row(_Entry.item(item)));
      }
    }
    for (final group in groups) {
      final label = _groupLabel(group.kind);
      children.add(
        _GroupHeader(
          label: group.total > group.items.length
              ? '$label · ${'search.global.groupCount'.tr(args: {'shown': '${group.items.length}', 'total': '${group.total}'})}'
              : label,
        ),
      );
      for (final item in group.items) {
        children.add(row(_Entry.item(item)));
      }
    }
    final createEntry = entries.isNotEmpty && entries.last.create != null
        ? entries.last
        : null;

    final total = groups.fold<int>(0, (sum, g) => sum + g.total);
    final noHits = searching && !loading && groups.isEmpty;

    Widget body;
    if (noHits) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: AwEmptyState(
              key: const Key('global-search-empty'),
              icon: Icons.search_off,
              title: 'search.global.noResultsTitle'.tr(),
              message: 'search.global.noResultsBody'.tr(
                args: {'query': _query},
              ),
            ),
          ),
          if (createEntry != null) row(createEntry),
        ],
      );
    } else if (children.isEmpty && createEntry == null) {
      body = Padding(
        key: const Key('global-search-intro'),
        padding: const EdgeInsets.all(AwSpace.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'search.global.emptyHint'.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (wide) ...[
              const SizedBox(height: AwSpace.x2),
              Text(
                'search.global.shortcutTip'.tr(
                  args: {'shortcut': globalSearchShortcutLabel()},
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      );
    } else {
      if (createEntry != null) children.add(row(createEntry));
      body = ListView(
        key: const Key('global-search-results'),
        controller: _scroll,
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(
          AwSpace.x2,
          0,
          AwSpace.x2,
          AwSpace.x2,
        ),
        children: children,
      );
    }

    final count = Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AwSpace.x5,
          AwSpace.x1,
          AwSpace.x5,
          AwSpace.x3,
        ),
        child: Text(
          searching && !loading
              ? 'search.global.resultCount'.tr(args: {'count': '$total'})
              : '',
          key: const Key('global-search-count'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );

    final progress = SizedBox(
      height: 2,
      child: loading && _progressDue
          ? const LinearProgressIndicator(minHeight: 2)
          : null,
    );

    if (!wide) {
      return Dialog.fullscreen(
        backgroundColor: theme.dialogTheme.backgroundColor,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AwSpace.x1,
                  AwSpace.x2,
                  AwSpace.x4,
                  AwSpace.x2,
                ),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('global-search-close'),
                      tooltip: 'common.close'.tr(),
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: AwSpace.x1),
                    Expanded(child: field),
                  ],
                ),
              ),
              progress,
              Expanded(
                child: Align(alignment: Alignment.topCenter, child: body),
              ),
              count,
            ],
          ),
        ),
      );
    }

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(
        AwSpace.x6,
        72,
        AwSpace.x6,
        AwSpace.x6,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: (size.height * 0.7).clamp(240, 560),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.all(AwSpace.x4), child: field),
            progress,
            Flexible(child: body),
            count,
          ],
        ),
      ),
    );
  }
}

String _groupLabel(GlobalSearchKind kind) => switch (kind) {
  GlobalSearchKind.task => 'search.global.groups.tasks'.tr(),
  GlobalSearchKind.project => 'search.global.groups.projects'.tr(),
  GlobalSearchKind.note => 'search.global.groups.notes'.tr(),
  GlobalSearchKind.tag => 'search.global.groups.tags'.tr(),
  GlobalSearchKind.file => 'search.global.groups.files'.tr(),
};

String _kindLabel(GlobalSearchKind kind) => switch (kind) {
  GlobalSearchKind.task => 'search.global.kinds.task'.tr(),
  GlobalSearchKind.project => 'search.global.kinds.project'.tr(),
  GlobalSearchKind.note => 'search.global.kinds.note'.tr(),
  GlobalSearchKind.tag => 'search.global.kinds.tag'.tr(),
  GlobalSearchKind.file => 'search.global.kinds.file'.tr(),
};

IconData _kindIcon(GlobalSearchItem item) => switch (item.kind) {
  GlobalSearchKind.task =>
    item.done ? Icons.check_circle : Icons.radio_button_unchecked,
  GlobalSearchKind.project => Icons.folder_outlined,
  GlobalSearchKind.note => Icons.description_outlined,
  GlobalSearchKind.tag => Icons.sell_outlined,
  GlobalSearchKind.file => fileKindIcon(item.mime ?? ''),
};

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AwSpace.x3,
          AwSpace.x3,
          AwSpace.x3,
          AwSpace.x1,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// One result row: kind icon, one-line title, context line, and — on the
/// active row — a fill AND the ⏎ glyph, so the selection never rests on
/// colour alone (G5).
class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    super.key,
    required this.active,
    required this.item,
    required this.createTitle,
    required this.onHover,
    required this.onTap,
  });

  final bool active;
  final GlobalSearchItem? item;
  final String? createTitle;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = this.item;

    final String title;
    final String? subtitle;
    final IconData icon;
    final String semanticLabel;
    String? badge;
    if (item == null) {
      title = 'search.global.createTask'.tr(args: {'title': createTitle!});
      subtitle = null;
      icon = Icons.add_task;
      semanticLabel = title;
    } else {
      title = item.title;
      icon = _kindIcon(item);
      subtitle = item.kind == GlobalSearchKind.tag
          ? 'search.global.tagHint'.tr()
          : item.context;
      if (item.done) badge = 'search.global.completed'.tr();
      if (item.archived) badge = 'search.global.archived'.tr();
      semanticLabel = [
        '${_kindLabel(item.kind)}: ${item.title}',
        ?badge,
      ].join(', ');
    }

    return MouseRegion(
      onHover: (_) => onHover(),
      child: Semantics(
        button: true,
        selected: active,
        label: semanticLabel,
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: item == null
                ? const Key('global-search-create')
                : Key('global-search-${item.kind.name}-${item.id}'),
            borderRadius: const BorderRadius.all(Radius.circular(AwRadius.s)),
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                color: active ? scheme.surfaceContainerHighest : null,
                borderRadius: const BorderRadius.all(
                  Radius.circular(AwRadius.s),
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AwSpace.x3,
                    vertical: AwSpace.x2,
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 22, color: scheme.onSurfaceVariant),
                      const SizedBox(width: AwSpace.x3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: scheme.onSurface,
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
                      if (badge != null) ...[
                        const SizedBox(width: AwSpace.x2),
                        Text(
                          badge,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(width: AwSpace.x2),
                      SizedBox(
                        width: 20,
                        child: active
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
