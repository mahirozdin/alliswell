import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/date_format.dart';
import '../../core/error_messages.dart';
import '../../core/fold.dart';
import '../../core/list_sort.dart';
import '../../core/pending_deletes.dart';
import '../../core/persisted_prefs.dart';
import '../../i18n/i18n.dart';
import '../../notifications/alarm_banner.dart';
import '../../notifications/missed_alarm_card.dart';
import '../../screens/home_shell.dart';
import '../../sections.dart';
import '../../sync/refresh.dart';
import '../../theme/tokens.dart';
import '../../widgets/list_detail.dart';
import '../../widgets/refreshable.dart';
import '../../widgets/status_views.dart';
import '../../search/providers.dart';
import '../../search/search.dart';
import '../../widgets/search_field.dart';
import '../../widgets/snackbars.dart';
import '../../widgets/sort_menu.dart';
import '../../core/date_input.dart';
import '../ai/data/ai_quick_add.dart';
import '../ai/providers.dart';
import '../quick_access/ui/quick_access_rail_section.dart';
import '../calendar/providers.dart';
import '../calendar/ui/external_event_tile.dart';
import '../ee/providers.dart';
import '../onboarding/tour.dart' show TourAnchor, TourTarget;
import '../tags/tags.dart';
import '../tasks/data/task.dart';
import '../tasks/data/quick_add_apply.dart';
import '../tasks/data/task_sort.dart';
import '../tasks/providers.dart';
import '../tasks/ui/quick_add_bar.dart';
import '../tasks/ui/quick_add_text_controller.dart';
import '../tasks/ui/task_tile.dart';
import '../workspaces/workspaces.dart';
import 'home_board.dart';
import 'home_create.dart';
import 'home_view_menu.dart';
import 'month_calendar.dart';
import 'task_grouping.dart';
import '../ee/ui/home_ticket_cards.dart';
import '../ee/ui/team_address_views.dart' show EeTeamAddressBanner;
import '../../theme/typography.dart';

/// Home (feedback round 1): the one place everything shows. Chronological
/// task list (overdue → today → tomorrow → this week → later → no date) with
/// an Apple-style month calendar — right panel on wide layouts, collapsible
/// top half on phones (visibility persisted). Picking a day pulls its tasks
/// to a highlighted first group and dims the future groups (Overdue/Today/
/// No-date stay lit); hiding the calendar drops the selection so an invisible
/// filter can never keep dimming the list (feedback round 6).
///
/// **Round 9 (OPH-172, DESIGN §16):** on phones exactly ONE thing is pinned —
/// the app bar. The degradation banner, the Liste | Pano toggle, quick add, the
/// search field, the calendar and the calendar toggle are all slivers of the
/// one scroll view, so chrome never narrows the list it sits above. Wide
/// layouts keep their pinned chrome and side calendar (there is room), and the
/// phone BOARD keeps its toggle pinned — a horizontal pager cannot scroll it
/// away, and losing it would strand the user in the board (H3).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Whether Home's app-bar search field is expanded (OPH-305).
  ///
  /// The open field takes `screen - 220` of the bar, and that 220 is a reserve
  /// measured against the actions that existed when it was written. Adding the
  /// sort menu overflowed it on a phone by 24px. Hiding the menu while the
  /// field is open is not only what fits — it is what is true: search shows a
  /// RANKED result list, and an order control over a list nobody is looking at
  /// is a control that does nothing.
  bool _searchOpen = false;

  /// Quick add's text lives HERE, not in the bar (OPH-172/H4): the bar is a
  /// sliver now, and a sliver scrolled past the cache extent is disposed —
  /// which would silently eat what the user had typed.
  final _quickAddController = QuickAddTextController();
  final _quickAddFocus = FocusNode();
  final _quickAddKey = GlobalKey();

  /// OPH-398 (ADR-0062 §6): on a phone Home's local filter is a field the
  /// list reveals when pulled down — not a magnifier in the app bar beside
  /// the search orb. Its text lives here for the H4 reason: it is a sliver.
  final _filterController = TextEditingController();
  Timer? _filterDebounce;

  /// The field's sliver extent at the current text scale — the offset the
  /// phone list rests at, so the field waits just above the quick add.
  double _filterExtent = 0;
  late final _homeScroll = _HomeScrollController(
    () => ref.read(homeSearchQueryProvider).trim().isEmpty ? _filterExtent : 0,
  );

  /// The wide layout's list, so a quick-added row can be scrolled to there
  /// too (OPH-401).
  final _wideScroll = ScrollController();

  /// OPH-401 (U-13, DESIGN §47 Q7): the row a quick add just made — lit for a
  /// moment and scrolled into sight. [_flashKey] sits on that one row.
  String? _flashId;
  Timer? _flashTimer;
  final _flashKey = GlobalKey();

  /// Which section each task's row is in, as last built — so a reveal can
  /// open a folded section first.
  Map<String, String> _sectionOfTask = const {};

  void _onFilterChanged(String value) {
    _filterDebounce?.cancel();
    _filterDebounce = Timer(
      const Duration(milliseconds: 250),
      () => ref.read(homeSearchQueryProvider.notifier).set(value.trim()),
    );
    setState(() {}); // the clear (×) follows the text
  }

  void _clearFilter() {
    _filterDebounce?.cancel();
    _filterController.clear();
    ref.read(homeSearchQueryProvider.notifier).set('');
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _quickAddFocus.addListener(_keepQuickAddVisible);
    // OPH-333: the widget's "+". `fireImmediately` covers the cold start, where
    // the request is already waiting when Home is first built; the listener
    // covers a warm "+" while Home is mounted (possibly on another tab).
    ref.listenManual<bool>(homeCreateRequestProvider, (_, wanted) {
      if (wanted) _openCreateFromRequest();
    }, fireImmediately: true);
  }

  /// Guards against a second notification landing before the first frame's
  /// callback has run — two sheets from one tap.
  bool _createRequestScheduled = false;

  /// OPH-333: `alliswell://add` → `/home?add=1` → [homeCreateRequestProvider]
  /// → the Home FAB's sheet.
  ///
  /// The request is consumed FIRST, so it is one-shot whatever happens next.
  /// Nothing is written here — the link only navigates; the task exists when
  /// the person saves (ADR-0016).
  ///
  /// Same permission as the FAB (EE-052): a role without `tasks.create` never
  /// sees the FAB, so a link must not hand it a sheet it cannot save. It lands
  /// on Home instead — the URL is untrusted input, not an instruction.
  void _openCreateFromRequest() {
    if (_createRequestScheduled) return;
    _createRequestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _createRequestScheduled = false;
      if (!mounted) return;
      if (!ref.read(homeCreateRequestProvider.notifier).take()) return;
      // OPH-356: `canProvider` says no until the permissions are known, and a
      // cold start asks before they are — wait for the answer, not a guess.
      if (ref.read(eePermissionsProvider).isLoading) {
        try {
          await ref.read(eePermissionsProvider.future);
        } catch (_) {}
      }
      if (!mounted) return;
      if (!ref.read(canProvider('tasks.create'))) return;
      showHomeTaskCreateSheet(context, ref);
    });
  }

  @override
  void dispose() {
    _quickAddFocus.removeListener(_keepQuickAddVisible);
    _quickAddController.dispose();
    _quickAddFocus.dispose();
    _filterDebounce?.cancel();
    _filterController.dispose();
    _homeScroll.dispose();
    _wideScroll.dispose();
    _flashTimer?.cancel();
    super.dispose();
  }

  /// Focusing a bar that is half off the top edge (or about to sit behind the
  /// keyboard) must not leave the user typing blind — scroll it back (H4).
  void _keepQuickAddVisible() {
    if (!_quickAddFocus.hasFocus) return;
    final context = _quickAddKey.currentContext;
    if (context == null) return; // wide layout: nothing can scroll it away
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;
    // OPH-398: already in full view — leave the list where it is. The phone
    // list rests one filter-field down; aligning the bar at 10 % would pull
    // the filter into sight (and move the bar under the finger) on every tap.
    final box = context.findRenderObject();
    final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
    if (box != null && viewport != null) {
      final pixels = scrollable.position.pixels;
      final atTop = viewport.getOffsetToReveal(box, 0).offset;
      final atBottom = viewport.getOffsetToReveal(box, 1).offset;
      if (pixels <= atTop && pixels >= atBottom) return;
    }
    Scrollable.ensureVisible(
      context,
      duration: AwMotion.base,
      alignment: 0.1,
      curve: Curves.easeOutCubic,
    );
  }

  /// Quick add from Home: lands on the selected calendar day at the user's
  /// default task time (Settings; factory 23:59 — OPH-161) when one is picked,
  /// otherwise dateless — either way it appears in the list right away
  /// (feedback round 2).
  ///
  /// OPH-373 (DESIGN §39 Q4): when the text already says when ("yarın 9'da",
  /// "başla pazartesi", "her cuma"), that wins — no picker, and the selected
  /// calendar day does not override it (relative words are relative to the
  /// real now). Tags, project and priority typed in the text apply either way.
  Future<void> _quickAdd(QuickAddSubmission submission) async {
    final workspaceId = await ref.read(activeWorkspaceIdProvider.future);
    if (workspaceId == null) throw StateError('No workspace available');
    final parse = submission.parse;
    if (parse.hasSchedule) {
      final id = await createFromQuickParse(
        ref.read,
        parse: parse,
        withDefaults: true,
      );
      final due = parse.dueAt ?? parse.whenDay;
      _afterQuickAdd(
        id,
        parse.title,
        due,
        withTime: parse.dueAt != null && parse.dueHasTime,
      );
      return;
    }
    final selectedDay = ref.read(selectedDayProvider);
    if (!mounted) return;
    // Round 14: quick add asks for the deadline every time — the create
    // sheet's own date+time picker, opening on the selected calendar day.
    // Backing out is the "skip" path and keeps the old semantics: the
    // selected day at the default task time, or no date at all.
    DateTime? dueAt = await awPickDateTime(context, ref, anchor: selectedDay);
    dueAt ??= selectedDay == null
        ? null
        : applyDefaultTaskTime(selectedDay, ref.read(defaultTaskTimeProvider));
    // In the workspace on screen — and, in an organisation's, on the person
    // who added it: a task added from Home is that person's work. Round-14
    // defaults: medium priority, urgent alarm on, and a reminder an hour
    // before the deadline whenever one was picked.
    final id = await createFromQuickParse(
      ref.read,
      parse: parse,
      withDefaults: true,
      dueAt: dueAt,
    );
    _afterQuickAdd(id, parse.title, dueAt, withTime: true);
  }

  /// OPH-401 (U-13, A-67, DESIGN §47 Q6–Q7): say what was added and when,
  /// offer it back for 3 s, light the new row and bring it into sight. The
  /// field had just emptied with no other sign — and the row could be under
  /// the calendar or at the end of a long list — so people typed it twice.
  void _afterQuickAdd(
    String? id,
    String title,
    DateTime? due, {
    required bool withTime,
  }) {
    if (id == null || !mounted) return;
    final when = due == null
        ? HomeBucket.noDate.label
        : awFormatShort(
            due,
            format: ref.read(dateFormatProvider),
            withTime: withTime,
          );
    final messenger = ScaffoldMessenger.of(context);
    // Resolved now: Undo may land after this screen has rebuilt.
    final store = ref.read(taskStoreProvider);
    final seriesStore = ref.read(seriesStoreProvider);
    messenger.hideCurrentSnackBar();
    showAwActionSnackBar(
      messenger,
      key: const Key('quick-add-added'),
      content: Text('home.added'.tr(args: {'title': title, 'when': when})),
      actionLabel: 'common.undo'.tr(),
      duration: const Duration(seconds: 3),
      onAction: () async {
        _flashTimer?.cancel();
        if (mounted) setState(() => _flashId = null);
        // A typed repeat made a series; taking the task back without it
        // would let the series make the next one.
        final task = ref
            .read(openTasksProvider)
            .value
            ?.where((t) => t.id == id)
            .firstOrNull;
        if (task != null && task.seriesId != null) {
          await seriesStore.stop(
            workspaceId: task.workspaceId,
            seriesId: task.seriesId!,
            fromDay: task.occurrenceDate,
          );
        }
        await store.delete(id);
      },
    );
    setState(() => _flashId = id);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _flashId = null);
    });
    unawaited(_revealFlash(id));
  }

  /// Brings the quick-added row into sight. A list builds only the rows near
  /// the viewport, so a row far below has no context to scroll to yet: move a
  /// screen at a time until it is built, then settle it in view. A row the
  /// current filters hide is simply never found — nothing moves.
  Future<void> _revealFlash(String id) async {
    for (var i = 0; i < 60; i++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _flashId != id) return;
      final section = _sectionOfTask[id];
      if (section == null) continue; // not in the list (yet)
      if (ref.read(homeCollapsedSectionsProvider).contains(section)) {
        ref.read(homeCollapsedSectionsProvider.notifier).expand(section);
        continue;
      }
      final row = _flashKey.currentContext;
      if (row != null) {
        if (!row.mounted) return;
        _ensureRowVisible(row);
        return;
      }
      final controller = MediaQuery.sizeOf(context).width < kAwWideBreakpoint
          ? _homeScroll
          : _wideScroll;
      if (!controller.hasClients) return;
      final position = controller.position;
      if (position.pixels >= position.maxScrollExtent) return;
      position.jumpTo(
        math.min(
          position.pixels + position.viewportDimension * 0.8,
          position.maxScrollExtent,
        ),
      );
    }
  }

  void _ensureRowVisible(BuildContext row) {
    final box = row.findRenderObject();
    final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
    final scrollable = Scrollable.maybeOf(row);
    if (box == null || viewport == null || scrollable == null) return;
    final pixels = scrollable.position.pixels;
    // What floats over the list's end (bar, buttons, fade) hides a row as
    // surely as the edge does.
    final covered = awListPadding(context, extraBottom: 72).bottom;
    final atTop = viewport.getOffsetToReveal(box, 0).offset;
    final atBottom = viewport.getOffsetToReveal(box, 1).offset + covered;
    if (pixels <= atTop && pixels >= atBottom) return;
    final reduce = MediaQuery.disableAnimationsOf(context);
    Scrollable.ensureVisible(
      row,
      alignment: 0.3,
      duration: reduce ? Duration.zero : AwMotion.base,
      curve: AwMotion.enter,
    );
  }

  /// OPH-222, redone in round 14 — the ✨ rider is optimistic: the task
  /// appears immediately (plain quick-add semantics), the AI fills fields in
  /// asynchronously, and any failure leaves the plain task standing. No
  /// confirm card on this path.
  Future<void> _parseWithAi(String text) async {
    final workspaceId = await ref.read(activeWorkspaceIdProvider.future);
    if (workspaceId == null) return;
    await ref
        .read(aiQuickAddProvider)
        .start(workspaceId: workspaceId, text: text);
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(openTasksProvider);
    final selectedDay = ref.watch(selectedDayProvider);
    // A workspace with no calendar connected has none — not an error state.
    final events =
        ref.watch(externalEventsProvider).value ?? const <ExternalEvent>[];

    // OPH-167 (DESIGN §12): per-screen search — tasks, captures and the
    // user's calendar in one ranked list. Never mutates the list state it
    // covers (S5). Watched at build top, NOT inside the async when-branch.
    final searching = ref.watch(homeSearchQueryProvider).trim().isNotEmpty;
    // OPH-168 (K1): Liste | Pano — the board is a VIEW of the same task set,
    // device-local and persistent. Search belongs to the list view.
    final isBoard = ref.watch(homeViewProvider) == 'board';
    // Watched here (not inside the LayoutBuilder) so a layout pass never
    // subscribes providers.
    final calendarVisible = ref.watch(homeCalendarVisibleProvider);
    // OPH-401 (U-04): a phone's calendar is a week strip until the person
    // opens the month; the choice is kept.
    final calendarMode = awHomeCalendarMode(
      ref.watch(homeCalendarModeProvider),
      MediaQuery.sizeOf(context).width,
    );
    final dateFormat = ref.watch(dateFormatProvider);
    // OPH-398 (ADR-0062 §6): a phone — no rail — gets the three-target bar
    // and the pull-down filter; wide windows keep the bar below unchanged.
    final phone = MediaQuery.sizeOf(context).width < kAwWideBreakpoint;
    final sort = AwSortState.parse(
      ref.watch(tasksSortProvider),
      kTaskSortChoices,
    );
    void setView(String view) {
      // OPH-306: leaving for the board drops the tag filter. The board is
      // the one Home view with nowhere to put the filter's bar, and an
      // active filter whose bar nobody can see is exactly what Epic 17's
      // rule forbids — the same reason hiding the calendar clears the
      // selected day.
      if (view == 'board') ref.read(tagFilterProvider.notifier).clear();
      ref.read(homeViewProvider.notifier).set(view);
    }

    void toggleCalendar() {
      // Hiding the calendar clears the selection: a filter you can no
      // longer see must not keep dimming Home (feedback round 6).
      if (calendarVisible) {
        ref.read(selectedDayProvider.notifier).select(null);
      }
      ref.read(homeCalendarVisibleProvider.notifier).toggle();
    }

    final textScaler = MediaQuery.textScalerOf(context);
    _filterExtent = _HomeFilterField.extentFor(textScaler);

    // OPH-213 (DESIGN §16 H1, revised): the view controls left the scroll and
    // became app-bar icons — the Notes pattern. An icon shows the view it will
    // SWITCH TO, so what you tap is what you get. The board's column editor
    // stays beside it, since it only means anything in the board.
    final viewActions = <Widget>[
      // Round 13 #5: search is an app-bar action too, so the list keeps its
      // line. Closing it clears the query (see AwSearchAction).
      AwSearchAction(
        // Keyed: the actions before it change while it is open (the ⚡
        // steps aside), and an unkeyed field would lose its open state.
        key: const ValueKey('home-search-action'),
        fieldKey: const Key('home-search'),
        hintText: 'home.searchHint'.tr(),
        onQuery: (q) => ref.read(homeSearchQueryProvider.notifier).set(q),
        onOpenChanged: (open) => setState(() => _searchOpen = open),
      ),
      IconButton(
        key: const Key('home-view-toggle'),
        tooltip: isBoard ? 'board.viewList'.tr() : 'board.viewBoard'.tr(),
        icon: Icon(
          isBoard ? Icons.view_agenda_outlined : Icons.view_kanban_outlined,
        ),
        onPressed: () => setView(isBoard ? 'list' : 'board'),
      ),
      if (isBoard)
        IconButton(
          key: const Key('board-edit-columns'),
          tooltip: 'board.editColumns'.tr(),
          icon: const Icon(Icons.tune),
          onPressed: () => showBoardColumnsSheet(context, ref),
        ),
      // OPH-305: the order INSIDE each day group. Not on the board — its
      // columns carry their own order, and a menu that silently applied to
      // something else would be worse than no menu. Not while the search field
      // is open either, for the same reason and because that is the one state
      // the bar has no room for (see `_searchOpen`).
      if (!isBoard && !_searchOpen)
        AwSortMenuButton(
          key: const Key('home-sort'),
          choices: kTaskSortChoices,
          sort: sort,
          onChanged: (next) =>
              ref.read(tasksSortProvider.notifier).set(next.encode()),
        ),
      if (!isBoard)
        IconButton(
          key: const Key('toggle-calendar'),
          tooltip: calendarVisible
              ? 'home.hideCalendar'.tr()
              : 'home.showCalendar'.tr(),
          icon: Icon(
            calendarVisible
                ? Icons.calendar_month
                : Icons.calendar_month_outlined,
          ),
          onPressed: toggleCalendar,
        ),
    ];

    // OPH-398 (ADR-0062 §6, R-05): a phone's bar is ⚡ + this + Settings.
    // The magnifier is gone — the orb beside the tab bar is the one search
    // glyph (ADR-0055) — and view, calendar, order and the board's columns
    // are one labelled menu.
    final phoneActions = <Widget>[
      HomeViewMenuButton(
        isBoard: isBoard,
        calendarVisible: calendarVisible,
        sortChoices: kTaskSortChoices,
        sort: sort,
        onView: setView,
        onToggleCalendar: toggleCalendar,
        onSort: (next) =>
            ref.read(tasksSortProvider.notifier).set(next.encode()),
        onEditColumns: () => showBoardColumnsSheet(context, ref),
      ),
    ];

    // The create FAB is rendered by HomeShell's own Scaffold (OPH-101), so it
    // clears the glass bottom bar; this screen only supplies the list + quick
    // add + calendar.
    return Scaffold(
      appBar: buildSectionAppBar(
        context,
        'nav.home'.tr(),
        onRefresh: () => refreshSection(ref, AppSection.home),
        // OPH-200: the entry point when the floating button is switched off —
        // the widget hides itself everywhere else (DESIGN §23 Q5).
        // The ⚡ steps aside while the search field is open, like the sort
        // menu: a phone's bar has no room for both (OPH-396 — with the
        // bubble off by default, ADR-0062 #5, this is the common case).
        leadingActions: [if (!_searchOpen) const QuickAccessAppBarButton()],
        // OPH-213: the view + calendar controls, left of settings.
        trailingActions: phone ? phoneActions : viewActions,
      ),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(openTasksProvider),
        ),
        data: (rawItems) {
          // OPH-184: rows hide themselves while undoable, but the GROUPING is
          // computed from the raw list — without this a group whose only task
          // was just deleted would render a header above nothing.
          final items = awWithoutPending(
            rawItems,
            ref.watch(pendingDeletesProvider),
            (t) => t.id,
          );
          // OPH-306: the filter narrows the SET; the grouping and the order
          // (OPH-305) then run on it unchanged, which is what makes "tap a tag,
          // see it by priority" one gesture instead of a second mode.
          final tagFilter = ref.watch(tagFilterProvider);
          // Tapping the tag you are already on clears it — the selected
          // calendar day's gesture, so one habit covers both.
          void onTagTap(Tag tag) =>
              ref.read(tagFilterProvider.notifier).toggle(tag.id);
          final visible = tagFilter == null
              ? items
              : [
                  for (final t in items)
                    if (t.tagIds.contains(tagFilter)) t,
                ];
          final groups = groupTasksForHome(
            visible,
            now: DateTime.now(),
            selectedDay: selectedDay,
            events: events,
            // OPH-305: the grouping is Home's spine and never a preference;
            // this only decides the order WITHIN each group.
            sort: AwSortState.parse(
              ref.watch(tasksSortProvider),
              kTaskSortChoices,
            ),
          );
          _sectionOfTask = {
            for (final group in groups)
              for (final item in group.items)
                if (item is TaskItem) item.task.id: homeSectionKey(group),
          };
          final markedDays = {
            ...daysWithTasks(items),
            ...daysWithEvents(events),
          };
          // The wide panel has room for the month and keeps it (no swap).
          final calendar = MonthCalendar(
            // A day with a meeting is not an empty day.
            markedDays: markedDays,
            selectedDay: selectedDay,
            onDaySelected: (day) =>
                ref.read(selectedDayProvider.notifier).select(day),
          );
          final phoneCalendar = MonthCalendar(
            key: const Key('home-calendar'),
            markedDays: markedDays,
            selectedDay: selectedDay,
            onDaySelected: (day) =>
                ref.read(selectedDayProvider.notifier).select(day),
            mode: calendarMode == 'week'
                ? AwCalendarMode.week
                : AwCalendarMode.month,
            onModeChanged: (mode) =>
                ref.read(homeCalendarModeProvider.notifier).set(mode.name),
          );

          // OPH-222: the ✨ parse rider — only when AI is configured.
          final aiConfigured =
              ref.watch(aiStatusProvider).value?.configured ?? false;
          final quickAdd = TourAnchor(
            target: TourTarget.quickAdd,
            child: QuickAddBar(
              key: const Key('home-quick-add'),
              // Hoisted state (H4) — see [_quickAddController].
              controller: _quickAddController,
              focusNode: _quickAddFocus,
              // A-13: the example does not fit at a large text size.
              hintText: selectedDay == null
                  ? (MediaQuery.textScalerOf(context).scale(1) > 1.3
                            ? 'home.quickAddHintShort'
                            : 'home.quickAddHint')
                        .tr()
                  : 'home.quickAddForDay'.tr(
                      args: {
                        'date': awFormatDate(selectedDay, format: dateFormat),
                      },
                    ),
              onAdd: _quickAdd,
              onParse: aiConfigured ? _parseWithAi : null,
            ),
          );

          // Honest alarm-degradation banner (OPH-143): only shown when the OS
          // can't ring urgent alarms reliably; nothing otherwise. Below it, the
          // alarm that already went unanswered (round 19 #2) — which used to
          // seize the whole screen and ring, days after its moment.
          // OPH-356 (UI-AUDIT #7): and, for a team member signed in on the
          // service's own address, where their team actually is.
          const banner = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EeTeamAddressBanner(),
              // OPH-409 (U-22): requests on Home for an organisation's
              // people; nothing on a plain build or a personal space.
              EeHomeTicketCards(),
              AlarmDegradationBanner(),
              MissedAlarmCard(),
            ],
          );

          final collapsed = ref.watch(homeCollapsedSectionsProvider);
          return LayoutBuilder(
            builder: (context, constraints) {
              // OPH-405 (DESIGN §51 D3): with a task open in the desktop pane
              // the list keeps its wide form — it only gives the calendar
              // panel's room to the pane — instead of turning into the phone
              // layout (and losing its scroll position) on every open.
              final paneOpen = AwListDetailScope.isOpen(context, kAwTaskPane);
              final isWide = paneOpen || awWideContent(context, constraints);

              // H2 — wide layouts are unchanged: there is room for pinned
              // chrome, and the calendar is a side panel.
              if (isWide) {
                return Column(
                  children: [
                    banner,
                    if (isBoard)
                      const Expanded(child: HomeBoard())
                    else
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  quickAdd,
                                  Expanded(
                                    // OPH-171: the list pulls here too; the
                                    // calendar panel beside it is not a list.
                                    child: AwRefresh(
                                      indicatorKey: const Key('home-refresh'),
                                      onRefresh: () =>
                                          refreshSection(ref, AppSection.home),
                                      child: searching
                                          // Search renders slivers (so phones
                                          // can pull it too) — give them a
                                          // scroll view of their own here.
                                          ? const CustomScrollView(
                                              physics:
                                                  AlwaysScrollableScrollPhysics(),
                                              slivers: [_HomeSearchResults()],
                                            )
                                          : AwListOrder(
                                              ids: [
                                                for (final group in groups)
                                                  if (!collapsed.contains(
                                                    homeSectionKey(group),
                                                  ))
                                                    for (final item
                                                        in group.items)
                                                      if (item is TaskItem)
                                                        item.task.id,
                                              ],
                                              child: _GroupedTaskList(
                                                groups: groups,
                                                onTagTap: onTagTap,
                                                dateFormat: dateFormat,
                                                controller: _wideScroll,
                                                flashId: _flashId,
                                                flashKey: _flashKey,
                                                quickAddFocus: _quickAddFocus,
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!paneOpen)
                              SizedBox(
                                width: 356,
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    AwSpace.x1,
                                    AwSpace.x2,
                                    AwSpace.x4,
                                    AwSpace.x4,
                                  ),
                                  child: Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(AwSpace.x3),
                                      child: calendar,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              }

              // H3 — phone + board: the board is a horizontal pager, so the
              // toggle CANNOT ride a vertical scroll. It stays pinned, or the
              // way back to Liste disappears.
              if (isBoard) {
                return Column(
                  children: [
                    banner,
                    const Expanded(child: HomeBoard()),
                  ],
                );
              }

              // H1 — phone + list: ONE scroll view. Everything above the rows
              // scrolls with them (OPH-103's philosophy, finished); only the
              // app bar is pinned. The search field's sliver position is the
              // same in both modes, so it never remounts mid-typing (OPH-167).
              // OPH-398: on a phone the list rests with the filter field just
              // above it (`_homeScroll`); a pull reveals it, and the same pull
              // carried on past the top refreshes (`anywhere`).
              final filterExtent = _filterExtent;
              return AwRefresh(
                indicatorKey: const Key('home-refresh'),
                onRefresh: () => refreshSection(ref, AppSection.home),
                triggerMode: phone
                    ? RefreshIndicatorTriggerMode.anywhere
                    : RefreshIndicatorTriggerMode.onEdge,
                child: CustomScrollView(
                  key: const Key('home-scroll'),
                  controller: phone ? _homeScroll : null,
                  // A short list (or the empty state) must still be pullable.
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (phone)
                      SliverToBoxAdapter(
                        child: _HomeFilterField(
                          controller: _filterController,
                          height: filterExtent,
                          onChanged: _onFilterChanged,
                          onClear: _clearFilter,
                        ),
                      ),
                    const SliverToBoxAdapter(child: banner),
                    SliverToBoxAdapter(
                      // The key rides a KeyedSubtree so `ensureVisible` has a
                      // context INSIDE the scroll view (H4).
                      child: KeyedSubtree(key: _quickAddKey, child: quickAdd),
                    ),
                    if (searching) const _HomeSearchResults(),
                    if (!searching && calendarVisible)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AwSpace.x4,
                          ),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AwSpace.x2),
                              child: phoneCalendar,
                            ),
                          ),
                        ),
                      ),
                    if (!searching && groups.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        // Inside the scroll view already: its own scroll view
                        // must not eat the pull.
                        child: _HomeEmpty(
                          physics: const NeverScrollableScrollPhysics(),
                          quickAddFocus: _quickAddFocus,
                        ),
                      ),
                    if (!searching && groups.isNotEmpty)
                      SliverPadding(
                        padding: awListPadding(context, extraBottom: 72),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate(
                            buildHomeGroupRows(
                              context,
                              groups,
                              onTagTap: onTagTap,
                              dateFormat: dateFormat,
                              flashId: _flashId,
                              flashKey: _flashKey,
                            ),
                          ),
                        ),
                      ),
                    // A short list still rests with the field out of sight:
                    // the content is made at least one field taller than the
                    // viewport, so the resting offset exists.
                    if (phone)
                      SliverLayoutBuilder(
                        builder: (context, c) => SliverToBoxAdapter(
                          child: SizedBox(
                            height: math.max(
                              0,
                              c.viewportMainAxisExtent +
                                  filterExtent -
                                  c.precedingScrollExtent,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// The wide-layout task list: a plain ListView of the shared group rows.
/// (The narrow layout renders the same rows inside a CustomScrollView so the
/// calendar scrolls with them — OPH-103.)
class _GroupedTaskList extends StatelessWidget {
  const _GroupedTaskList({
    required this.groups,
    this.onTagTap,
    required this.dateFormat,
    this.controller,
    this.flashId,
    this.flashKey,
    this.quickAddFocus,
  });

  final List<HomeGroup> groups;
  final ValueChanged<Tag>? onTagTap;
  final String dateFormat;
  final ScrollController? controller;
  final String? flashId;
  final GlobalKey? flashKey;

  /// The quick-add field the first-run empty state's button focuses.
  final FocusNode? quickAddFocus;

  @override
  Widget build(BuildContext context) {
    // Both branches are the scrollable the pull gesture needs (OPH-171).
    if (groups.isEmpty) {
      return _HomeEmpty(
        physics: const AlwaysScrollableScrollPhysics(),
        quickAddFocus: quickAddFocus,
      );
    }
    return ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: awListPadding(context, extraBottom: 72),
      children: buildHomeGroupRows(
        context,
        groups,
        onTagTap: onTagTap,
        dateFormat: dateFormat,
        flashId: flashId,
        flashKey: flashKey,
      ),
    );
  }
}

/// Home's "nothing to do" state — shared by both layouts so it reads the same
/// in the wide ListView and the narrow SliverFillRemaining.
class _HomeEmpty extends ConsumerWidget {
  const _HomeEmpty({this.physics, this.quickAddFocus});

  /// See [AwEmptyState.physics]: always-scrollable in the wide layout (it IS
  /// the scrollable), never-scrollable inside the narrow sliver (the
  /// CustomScrollView above it owns the gesture).
  final ScrollPhysics? physics;

  /// See [_GroupedTaskList.quickAddFocus].
  final FocusNode? quickAddFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // OPH-306: "you are all caught up" is a lie while a filter is hiding the
    // rest of the day. An empty FILTERED list has to say which filter emptied
    // it and offer the way out, or the user is looking at a beach umbrella
    // wondering where their work went.
    final tagId = ref.watch(tagFilterProvider);
    final tag = tagId == null ? null : ref.watch(tagsByIdProvider)[tagId];
    if (tag != null) {
      return Column(
        key: const Key('tag-filter-empty'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const _TagFilterBar(),
          Expanded(
            child: AwEmptyState(
              icon: Icons.filter_alt_off_outlined,
              title: 'tag.filteredBy'.tr(args: {'tag': tag.name}),
              message: 'tag.filterEmpty'.tr(args: {'tag': tag.name}),
              physics: physics,
            ),
          ),
        ],
      );
    }
    // OPH-404 (U-28, A-12, DESIGN §50 F3): "all caught up" said to someone
    // who has never added a task is the wrong sentence. An account with no
    // task of any status gets a first-run state with the way in; one whose
    // work is done gets a done state. Unknown (the query has not answered)
    // reads as done — the first-run face appearing a frame later is fine,
    // telling a busy user "no tasks yet" is not.
    if (ref.watch(hasAnyTaskProvider).value == false) {
      final canCreate = ref.watch(canProvider('tasks.create'));
      return AwEmptyState(
        key: const Key('home-empty-first-run'),
        icon: Icons.add_task,
        title: 'home.firstRunTitle'.tr(),
        message: 'home.firstRunBody'.tr(),
        physics: physics,
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canCreate)
              FilledButton.icon(
                key: const Key('home-empty-add-first'),
                onPressed: () => quickAddFocus?.requestFocus(),
                icon: const Icon(Icons.add),
                label: Text('home.firstRunAdd'.tr()),
              ),
            const SizedBox(height: AwSpace.x2),
            TextButton(
              key: const Key('home-empty-import'),
              onPressed: () => context.push('/settings/import'),
              child: Text('home.firstRunImport'.tr()),
            ),
          ],
        ),
      );
    }
    return AwEmptyState(
      key: const Key('home-empty-done'),
      icon: Icons.check_circle_outline,
      title: 'home.allCaughtUp'.tr(),
      message: 'home.allCaughtUpBody'.tr(),
      physics: physics,
    );
  }
}

/// The visible half of the tag filter (OPH-306).
///
/// Epic 17's rule, and §16's: a filter you can no longer see must not keep
/// filtering. So it is never silent — it names the tag and carries its own way
/// out, exactly as the selected calendar day does.
class _TagFilterBar extends ConsumerWidget {
  const _TagFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagId = ref.watch(tagFilterProvider);
    if (tagId == null) return const SizedBox.shrink();
    final tag = ref.watch(tagsByIdProvider)[tagId];
    // A filter whose tag has been deleted would be invisible AND active — the
    // exact state the rule forbids. Drop it rather than render nothing.
    if (tag == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const Key('tag-filter-bar'),
      padding: const EdgeInsets.only(bottom: AwSpace.x2),
      child: Row(
        children: [
          Icon(Icons.filter_alt_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: AwSpace.x2),
          Expanded(
            child: Text(
              'tag.filteredBy'.tr(args: {'tag': tag.name}),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          TextButton.icon(
            key: const Key('tag-filter-clear'),
            onPressed: () => ref.read(tagFilterProvider.notifier).clear(),
            icon: const Icon(Icons.close, size: 18),
            label: Text('tag.clearFilter'.tr()),
          ),
        ],
      ),
    );
  }
}

/// Home's folded sections (OPH-401, DESIGN §47 S2), by [homeSectionKey].
///
/// For this session only: a section folded last week and forgotten would hide
/// Overdue work behind a header the next morning.
class HomeCollapsedSections extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String key) =>
      state = state.contains(key) ? ({...state}..remove(key)) : {...state, key};

  void expand(String key) {
    if (state.contains(key)) state = {...state}..remove(key);
  }
}

final homeCollapsedSectionsProvider =
    NotifierProvider<HomeCollapsedSections, Set<String>>(
      HomeCollapsedSections.new,
    );

/// A Home section's identity: its bucket, plus the day for a split one.
String homeSectionKey(HomeGroup group) {
  final day = group.day;
  return day == null
      ? group.bucket.name
      : '${group.bucket.name}-${day.year}-${day.month}-${day.day}';
}

/// The header + row widgets for Home's groups, shared by the wide ListView and
/// the narrow CustomScrollView (OPH-103) so the group/row logic lives in ONE
/// place. Each group is a labelled header followed by its chronological rows
/// (§12): a 10:00 meeting sits above a 16:00 task, each rendered as what it is.
///
/// The rows stay a flat list — a folded section folds row by row — so the
/// phone's sliver list still builds only what is near the screen.
List<Widget> buildHomeGroupRows(
  BuildContext context,
  List<HomeGroup> groups, {
  ValueChanged<Tag>? onTagTap,
  String dateFormat = kAwSystemDateFormat,
  String? flashId,
  GlobalKey? flashKey,
}) {
  return [
    // OPH-306: the filter names itself directly above the list it is filtering.
    // Both layouts render these rows, so one insertion covers the wide ListView
    // and the narrow CustomScrollView.
    const _TagFilterBar(),
    for (final group in groups) ...[
      _HomeSectionHeader(
        group: group,
        // OPH-307: a split group is named by its day, not by the bucket it
        // came from — "Perşembe · 16 Tem" rather than a fourth "Bu hafta".
        label: group.day == null
            ? group.bucket.label
            : awFormatDayHeading(group.day!, format: dateFormat),
      ),
      for (final item in group.items)
        _HomeSectionRow(
          section: homeSectionKey(group),
          child: switch (item) {
            TaskItem(:final task) when task.id == flashId => _FlashRow(
              key: flashKey,
              id: task.id,
              child: TaskTile(
                task: task,
                dimmed: group.dimmed,
                highlighted: group.bucket == HomeBucket.selectedDay,
                onTagTap: onTagTap,
              ),
            ),
            TaskItem(:final task) => TaskTile(
              task: task,
              dimmed: group.dimmed,
              highlighted: group.bucket == HomeBucket.selectedDay,
              onTagTap: onTagTap,
            ),
            EventItem(:final event) => ExternalEventTile(
              event: event,
              dimmed: group.dimmed,
            ),
          },
        ),
    ],
  ];
}

/// A Home section header (OPH-401, DESIGN §47 S1–S3): the name in the
/// section role (15/20 w700) and, 8 pt after it, the count in its own text —
/// `onSurfaceVariant`, tabular — so the number reads as a number and not as a
/// word of the name. The whole 48 pt row folds and opens the section; the
/// chevron on the right turns 180°.
class _HomeSectionHeader extends ConsumerWidget {
  const _HomeSectionHeader({required this.group, required this.label});

  final HomeGroup group;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final key = homeSectionKey(group);
    final collapsed = ref.watch(
      homeCollapsedSectionsProvider.select((s) => s.contains(key)),
    );
    final reduce = MediaQuery.disableAnimationsOf(context);
    final role = context.awText.sectionLabel;
    final count = '${group.count}';
    return Padding(
      padding: const EdgeInsets.only(top: AwSpace.x2),
      child: Semantics(
        header: true,
        button: true,
        expanded: !collapsed,
        excludeSemantics: true,
        label: (collapsed ? 'home.expandSection' : 'home.collapseSection').tr(
          args: {'section': label, 'count': count},
        ),
        onTap: () =>
            ref.read(homeCollapsedSectionsProvider.notifier).toggle(key),
        child: InkWell(
          key: Key('home-section-$key'),
          borderRadius: BorderRadius.circular(AwRadius.s),
          onTap: () =>
              ref.read(homeCollapsedSectionsProvider.notifier).toggle(key),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                const SizedBox(width: AwSpace.x1),
                Flexible(
                  child: Text(
                    label,
                    // OPH-301/OPH-399: no header dim; the SELECTED day's
                    // header is the one that differs (the accent). The
                    // header sits on the page, not a card, so Overdue takes
                    // the page-safe red; Today and the rest the page ink.
                    style: role.copyWith(
                      color: switch (group.bucket) {
                        HomeBucket.overdue => context.awTokens.errorOnPage,
                        HomeBucket.selectedDay => context.awTokens.link,
                        _ => theme.colorScheme.onSurface,
                      },
                    ),
                  ),
                ),
                const SizedBox(width: AwSpace.x2),
                Text(
                  count,
                  style: role.copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 48,
                  child: AnimatedRotation(
                    turns: collapsed ? -0.5 : 0,
                    duration: reduce ? Duration.zero : AwMotion.base,
                    curve: AwMotion.enter,
                    child: Icon(
                      Icons.expand_less,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of a foldable section: its height animates to nothing (220 ms, at
/// once with reduced motion) while the section is folded.
class _HomeSectionRow extends ConsumerWidget {
  const _HomeSectionRow({required this.section, required this.child});

  final String section;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(
      homeCollapsedSectionsProvider.select((s) => s.contains(section)),
    );
    return AnimatedSize(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AwMotion.base,
      curve: AwMotion.enter,
      alignment: Alignment.topCenter,
      child: collapsed ? const SizedBox(width: double.infinity) : child,
    );
  }
}

/// The quick-added row's moment of light (OPH-401, DESIGN §47 Q7): a
/// `primary` wash that fades out over 1.2 s — and simply stays for its two
/// seconds with reduced motion.
class _FlashRow extends StatelessWidget {
  const _FlashRow({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return KeyedSubtree(
      key: Key('home-flash-$id'),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: reduce ? 1 : 0),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeIn,
        builder: (context, t, child) => DecoratedBox(
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.16 * t),
            borderRadius: BorderRadius.circular(AwRadius.m),
          ),
          child: child,
        ),
        child: child,
      ),
    );
  }
}

/// Search-mode body (OPH-167): one ranked list — tasks (planning + inbox
/// captures) and calendar events — ordered by tier (title > tag > body),
/// each row its screen-normal self (S3/S5). The context line under a row
/// says WHERE a non-title hit matched.
///
/// **Returns a SLIVER** (OPH-172): search results are part of Home's one scroll
/// view, so pull-to-refresh works over them on phones too — a nested scrollable
/// would have swallowed the drag.
class _HomeSearchResults extends ConsumerWidget {
  const _HomeSearchResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(homeSearchQueryProvider).trim();
    final results = ref.watch(homeSearchResultsProvider);
    final open = ref.watch(openTasksProvider).value ?? const [];
    final inbox = ref.watch(inboxTasksProvider).value ?? const [];
    final events =
        ref.watch(externalEventsProvider).value ?? const <ExternalEvent>[];
    final tasksById = {
      for (final t in [...open, ...inbox]) t.id: t,
    };
    final eventsById = {for (final e in events) e.id: e};
    final words = SearchService.queryWords(query);

    return results.when(
      loading: () => const SliverToBoxAdapter(child: _DelayedProgress()),
      error: (error, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(homeSearchResultsProvider),
          physics: const NeverScrollableScrollPhysics(),
        ),
      ),
      data: (data) {
        if (data == null) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        final rows = <(int, Widget)>[];
        for (final hit in data.tasks) {
          final task = tasksById[hit.id];
          if (task == null) continue;
          rows.add((hit.tier, _TaskResult(task: task, hit: hit, words: words)));
        }
        for (final hit in data.events) {
          final event = eventsById[hit.id];
          if (event == null) continue;
          rows.add((
            hit.tier,
            Padding(
              padding: kAwListRowPadding,
              child: ExternalEventTile(event: event),
            ),
          ));
        }
        if (rows.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: AwEmptyState(
              icon: Icons.search_off,
              title: 'home.searchEmptyTitle'.tr(),
              message: 'home.searchEmptyBody'.tr(args: {'query': query}),
              physics: const NeverScrollableScrollPhysics(),
            ),
          );
        }
        // Stable merge by tier: tasks already tier-ordered, events too.
        rows.sort((a, b) => a.$1.compareTo(b.$1));
        return SliverPadding(
          key: const Key('home-search-results'),
          padding: awListPadding(context),
          sliver: SliverList(
            delegate: SliverChildListDelegate([for (final row in rows) row.$2]),
          ),
        );
      },
    );
  }
}

/// A task hit + its honest match context (S3): `#tag` for a tag hit, a
/// description snippet for a body hit; a title hit needs no explanation.
class _TaskResult extends ConsumerWidget {
  const _TaskResult({
    required this.task,
    required this.hit,
    required this.words,
  });

  final Task task;
  final SearchHit hit;
  final List<String> words;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    String? contextLine;
    if (hit.tier == 1) {
      final tagsById = ref.watch(tagsByIdProvider);
      for (final id in task.tagIds) {
        final tag = tagsById[id];
        if (tag == null) continue;
        final folded = foldSearchText(tag.name);
        if (words.every(folded.contains)) {
          contextLine = '#${tag.name}';
          break;
        }
      }
    } else if (hit.tier == 2 && (task.description?.isNotEmpty ?? false)) {
      contextLine = searchSnippet(task.description!, words.first);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TaskTile(task: task),
        if (contextLine != null)
          Padding(
            padding: const EdgeInsets.only(
              left: AwSpace.x6,
              right: AwSpace.x4,
              bottom: 6,
            ),
            child: Text(
              contextLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// S4: loading only when it's real — the bar appears after 150 ms, so a
/// millisecond-fast local query never flashes chrome.
class _DelayedProgress extends StatefulWidget {
  const _DelayedProgress();

  @override
  State<_DelayedProgress> createState() => _DelayedProgressState();
}

class _DelayedProgressState extends State<_DelayedProgress> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) => _show
      ? const Align(
          alignment: Alignment.topCenter,
          child: LinearProgressIndicator(minHeight: 2),
        )
      : const SizedBox.shrink();
}

/// The scroll controller of Home's phone list (OPH-398): it starts with the
/// filter field scrolled away, unless a query is live — then the field the
/// query is typed in stays in sight. Not kept in PageStorage: a remount
/// (board → list) comes back to the resting place, not to a stale offset.
class _HomeScrollController extends ScrollController {
  _HomeScrollController(this._restingOffset) : super(keepScrollOffset: false);

  final double Function() _restingOffset;

  @override
  double get initialScrollOffset => _restingOffset();
}

/// Home's local filter on a phone (OPH-398, DESIGN §12 S1, §16 H5): the
/// body-level field — never in the glass bar (G1) — that the list reveals
/// when pulled down. Its glyph is a filter, not a magnifier: the magnifier
/// means "search everywhere" (the orb, ADR-0055), and one glyph with two
/// scopes is what R-05 measured.
class _HomeFilterField extends StatelessWidget {
  const _HomeFilterField({
    required this.controller,
    required this.height,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;

  /// The sliver's whole extent ([extentFor]).
  final double height;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  static const double _top = AwSpace.x2;

  /// The field box grows with the text (one 16/24 line + 12 above and
  /// below), never below the 48 dp target.
  static double extentFor(TextScaler scaler) =>
      _top + math.max(48.0, scaler.scale(16) * 1.5 + AwSpace.x6);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AwSpace.x4, _top, AwSpace.x4, 0),
      child: SizedBox(
        height: height - _top,
        child: TextField(
          key: const Key('home-search'),
          controller: controller,
          textInputAction: TextInputAction.search,
          textAlignVertical: TextAlignVertical.center,
          maxLines: 1,
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            hintText: 'home.searchHint'.tr(),
            prefixIcon: const Icon(Icons.filter_list),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    key: const Key('home-search-clear'),
                    tooltip: 'common.clear'.tr(),
                    icon: const Icon(Icons.close),
                    onPressed: onClear,
                  ),
          ),
        ),
      ),
    );
  }
}
