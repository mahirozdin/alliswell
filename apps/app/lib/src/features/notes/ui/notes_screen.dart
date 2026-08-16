import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/date_format.dart';
import '../../../core/error_messages.dart';
import '../../../core/list_sort.dart';
import '../../../core/persisted_prefs.dart';
import '../../quick_access/data/quick_link.dart';
import '../../quick_access/ui/quick_access_add.dart';
import '../../../i18n/i18n.dart';
import '../../../sections.dart';
import '../../../sync/refresh.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/refreshable.dart';
import '../../../widgets/search_field.dart';
import '../../../widgets/sort_menu.dart';
import '../../../widgets/status_views.dart';
import '../../../widgets/swipe_actions.dart';
import '../../projects/providers.dart';
import 'external_open_menu.dart';
import 'note_export.dart';
import '../data/note.dart';
import '../providers.dart';

/// Note metadata dates in the user's chosen format (OPH-174, DESIGN §17).
String _shortDate(DateTime? value, String dateFormat) =>
    value == null ? '—' : awFormatDate(value, format: dateFormat);

/// Notes section (OPH-043 + feedback round 1): search, All/Pinned/Archived
/// chips, list ↔ A4-card grid view toggle (persisted), quick pin stars and
/// archive actions.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(notesQueryProvider);
    final notes = ref.watch(notesListProvider);
    final viewMode = ref.watch(notesViewModeProvider);
    final isGrid = viewMode == 'grid';
    final projects = ref.watch(projectsControllerProvider).value ?? const [];
    final projectNames = {for (final p in projects) p.id: p.name};
    Future<bool> refresh() => refreshSection(ref, AppSection.notes);
    // Notes builds its own app bar (the view toggle lives there), so it carries
    // the pointer-only refresh action itself (§15 R5).
    final wide = MediaQuery.sizeOf(context).width >= 800;

    return Scaffold(
      appBar: AppBar(
        title: Text('nav.notes'.tr()),
        actions: [
          if (wide) AwRefreshAction(onRefresh: refresh),
          // Round 13 #5: search moved into the bar, so the list starts one
          // line higher (the §16 H1 argument, applied everywhere).
          AwSearchAction(
            fieldKey: const Key('notes-search'),
            hintText: 'note.searchHint'.tr(),
            onQuery: (q) => ref.read(notesQueryProvider.notifier).setSearch(q),
          ),
          // OPH-258 (§34 L2): view and order are one menu, not two icons. The
          // bar was already at the phone's limit — that is why the file
          // actions became a menu in OPH-251 — and L1's point is that choosing
          // an order must not cost a row of the list either.
          AwSortMenuButton(
            choices: kNoteSortChoices,
            sort: ref.watch(notesSortStateProvider),
            onChanged: (next) =>
                ref.read(notesSortProvider.notifier).set(next.encode()),
            groups: [
              AwMenuChoiceGroup(
                titleKey: 'sort.viewSection',
                choices: const [
                  AwSortChoice(id: 'list', labelKey: 'sort.viewList'),
                  AwSortChoice(id: 'grid', labelKey: 'sort.viewGrid'),
                ],
                selectedId: viewMode,
                onSelected: (id) =>
                    ref.read(notesViewModeProvider.notifier).set(id),
              ),
            ],
          ),
          // Round 16 follow-up: AllisWell reads .md files. Reachable from
          // inside the app too, not only when the OS hands us one — a feature
          // only the OS can start is a feature most people never find
          // (DESIGN §22).
          // OPH-251 (W6): one affordance, three things behind it — edit the
          // file itself, import it as a note, or go back to one we already
          // hold a handle for. A file the OS gave us once is otherwise
          // unreachable forever.
          const ExternalOpenMenu(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'shell.settingsTooltip'.tr(),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      // FAB hoisted to HomeShell (OPH-101).
      body: Column(
        children: [
          // Horizontally scrollable so the filter strip never overflows on
          // phones (and survives extra chips like OPH-109's 'READMEs').
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (filter, label) in [
                  (NotesFilter.all, 'note.filterAll'.tr()),
                  (NotesFilter.pinned, 'note.filterPinned'.tr()),
                  (NotesFilter.archived, 'note.filterArchived'.tr()),
                  (NotesFilter.readmes, 'note.filterReadmes'.tr()),
                ]) ...[
                  ChoiceChip(
                    label: Text(label),
                    selected: query.filter == filter,
                    onSelected: (_) =>
                        ref.read(notesQueryProvider.notifier).setFilter(filter),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            // OPH-171: both views pull (§15) — the grid is a scrollable too.
            child: AwRefresh(
              indicatorKey: const Key('notes-refresh'),
              onRefresh: refresh,
              child: notes.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => AwErrorState(
                  message: localizedError(error),
                  onRetry: () => ref.invalidate(notesListProvider),
                  physics: const AlwaysScrollableScrollPhysics(),
                ),
                data: (items) => items.isEmpty
                    ? _EmptyNotes(
                        archived: query.filter == NotesFilter.archived,
                        physics: const AlwaysScrollableScrollPhysics(),
                      )
                    : isGrid
                    ? _NotesGrid(notes: items, projectNames: projectNames)
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: awListPadding(context, extraBottom: 72),
                        itemCount: items.length,
                        itemBuilder: (context, index) => NoteTile(
                          note: items[index],
                          projectName: projectNames[items[index].projectId],
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared note row (also used by the project Notes tab): quick-pin star in
/// front, metadata line (edited/created/project), archive menu.
class NoteTile extends ConsumerWidget {
  const NoteTile({super.key, required this.note, this.projectName});

  final NoteRow note;
  final String? projectName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFormat = ref.watch(dateFormatProvider);
    final meta = [
      'note.edited'.tr(args: {'date': _shortDate(note.updatedAt, dateFormat)}),
      'note.created'.tr(args: {'date': _shortDate(note.createdAt, dateFormat)}),
      ?projectName,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      // OPH-184: a note could only be deleted from inside its editor — the
      // list offered archive and nothing else.
      child: AwSwipeToDelete(
        id: note.id,
        semanticLabel: 'note.deleteTooltip'.tr(),
        onDelete: () => deleteNoteWithUndo(context, ref, note),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: AwSpace.x2),
            leading: IconButton(
              key: Key('pin-${note.id}'),
              tooltip: note.isPinned ? 'note.unpin'.tr() : 'note.pin'.tr(),
              icon: Icon(
                note.isPinned ? Icons.star : Icons.star_border,
                color: note.isPinned ? context.awTokens.warning : null,
              ),
              onPressed: () => toggleNotePinned(ref, note),
            ),
            title: Text(
              note.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              note.snippet.isEmpty ? meta : '${note.snippet}\n$meta',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _NoteMenu(note: note),
            onTap: () => context.go('/notes/${note.id}'),
          ),
        ),
      ),
    );
  }
}

/// Delete a note the recoverable way (OPH-184) — shared by the row swipe, the
/// row menu and the grid card, so all three behave identically.
Future<void> deleteNoteWithUndo(
  BuildContext context,
  WidgetRef ref,
  NoteRow note,
) {
  // Resolved while mounted — the commit fires from a timer long after this row
  // has left the list (see the note on [deleteTaskWithUndo]).
  final store = ref.read(noteStoreProvider);
  return awDeleteWithUndo(
    context,
    ref,
    id: note.id,
    message: 'note.deleted'.tr(args: {'title': note.title}),
    commit: () => store.delete(note.id),
  );
}

/// Exports a note straight from its row (OPH-272).
///
/// The list only holds a snippet, so the body is read from the replica first —
/// the same watch the editor opens with, taken once.
Future<void> _exportRow(
  BuildContext context,
  WidgetRef ref,
  NoteRow note,
) async {
  final detail = await ref.read(noteStoreProvider).watchDetail(note.id).first;
  if (!context.mounted) return;
  await exportNoteAsPdf(
    context,
    ref,
    title: detail.title.trim().isEmpty
        ? 'note.untitled'.tr()
        : detail.title.trim(),
    deltaJson: detail.contentDelta ?? const [],
    updatedAt: detail.updatedAt,
  );
}

class _NoteMenu extends ConsumerWidget {
  const _NoteMenu({required this.note});

  final NoteRow note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      key: Key('note-menu-${note.id}'),
      tooltip: 'note.actions'.tr(),
      onSelected: (action) {
        if (action == 'archive') setNoteArchived(ref, note, !note.isArchived);
        if (action == 'delete') deleteNoteWithUndo(context, ref, note);
        // OPH-272: the export existed only inside the editor's overflow, and
        // the owner went looking for it "where archive and delete are" — which
        // is here. The row carries no body, so it loads the note first.
        if (action == 'export-pdf') unawaited(_exportRow(context, ref, note));
        if (action == 'quick') {
          toggleQuickAccess(
            context,
            ref,
            kind: QuickKind.note,
            targetId: note.id,
            suggestedTitle: note.title,
          );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          key: Key('note-row-export-${note.id}'),
          value: 'export-pdf',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text('note.exportPdf'.tr()),
          ),
        ),
        quickAccessMenuItem(
          value: 'quick',
          isSaved: isInQuickAccess(ref, QuickKind.note, note.id),
        ),
        PopupMenuItem(
          value: 'archive',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              note.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
            ),
            title: Text(
              note.isArchived ? 'note.unarchive'.tr() : 'note.archive'.tr(),
            ),
          ),
        ),
        // DESIGN §19 D2: the swipe's visible equivalent — a mouse never swipes.
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline),
            title: Text('note.deleteFromList'.tr()),
          ),
        ),
      ],
    );
  }
}

/// A4-proportioned cards, Google-Docs-home style.
class _NotesGrid extends ConsumerWidget {
  const _NotesGrid({required this.notes, required this.projectNames});

  final List<NoteRow> notes;
  final Map<String, String> projectNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dateFormat = ref.watch(dateFormatProvider);
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: awListPadding(context, top: AwSpace.x4, extraBottom: 72),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 210 / 297, // A4
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.go('/notes/${note.id}'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            note.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: note.isPinned
                            ? 'note.unpin'.tr()
                            : 'note.pin'.tr(),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => toggleNotePinned(ref, note),
                        icon: Icon(
                          note.isPinned ? Icons.star : Icons.star_border,
                          size: 18,
                          color: note.isPinned
                              ? context.awTokens.warning
                              : null,
                        ),
                      ),
                      // The card grid had NO actions menu at all — no archive,
                      // no delete. A horizontal swipe is ambiguous inside a
                      // grid, so the menu is this view's affordance (D2).
                      _NoteMenu(note: note),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        note.snippet,
                        overflow: TextOverflow.fade,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'note.edited'.tr(
                          args: {
                            'date': _shortDate(note.updatedAt, dateFormat),
                          },
                        ) +
                        (projectNames[note.projectId] != null
                            ? ' · ${projectNames[note.projectId]}'
                            : ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes({required this.archived, this.physics});

  final bool archived;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return AwEmptyState(
      icon: archived ? Icons.archive_outlined : Icons.description,
      title: archived ? 'note.archiveEmpty'.tr() : 'note.empty'.tr(),
      message: archived ? 'note.archivedHere'.tr() : 'note.captureFirst'.tr(),
      physics: physics,
    );
  }
}
