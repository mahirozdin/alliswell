import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/fab_clearance.dart';
import '../../../widgets/status_views.dart';
import '../providers.dart' show canProvider;
import '../data/sla_admin_models.dart';
import '../sla_admin_providers.dart';
import '../../../widgets/swipe_actions.dart' show awConfirmDelete;
import 'report_format.dart';
import '../../../widgets/route_leading.dart';

/// What an admin may edit about a promise (EE-099).
///
/// Three editors, ONE screen with three tabs, because they are one job: a
/// policy is meaningless without the calendar it counts against, and a monitor
/// exists to open work a policy then measures. Three routes would have meant
/// three settings rows and three chances to leave one unreachable — which this
/// codebase has already paid for once (DESIGN §22).
///
/// ── The one thing a calendar editor must say out loud ────────────────────
///
/// A shift may end past midnight: `endMinute` runs to 2880 and 22:00 → 06:00
/// is stored as `[1320, 1800)` on the day it STARTS (ADR-0012 §1). The ADR
/// wrote that down as a UI debt, and this is where it is paid: an interval
/// that crosses midnight says "(ertesi gün)" beside its end time. Without
/// that, "22:00 – 06:00" reads as a sixteen-hour gap rather than an
/// eight-hour night, and an admin would 'fix' a calendar that was right.
///
/// ── Colour is a mark, meaning is a word (EE-097's rule) ─────────────────
///
/// A monitor's state is drawn as an icon in the state colour plus its own
/// label. `AwTokens.warning` measures 3.46 on the light surface — enough for a
/// mark, short of what a label needs — so nothing here writes text in it.
class EeSlaAdminScreen extends ConsumerWidget {
  const EeSlaAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(eeSlaAdminProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: awRouteLeading(context),
          title: Text('ee.slaAdmin.title'.tr()),
          bottom: TabBar(
            tabs: [
              Tab(
                key: const Key('sla-tab-policies'),
                text: 'ee.slaAdmin.policies'.tr(),
              ),
              Tab(
                key: const Key('sla-tab-calendars'),
                text: 'ee.slaAdmin.calendars'.tr(),
              ),
              Tab(
                key: const Key('sla-tab-monitors'),
                text: 'ee.slaAdmin.monitors'.tr(),
              ),
            ],
          ),
        ),
        body: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AwErrorState(
            message: localizedError(error),
            onRetry: () => ref.invalidate(eeSlaAdminProvider),
          ),
          data: (value) {
            if (value == null) {
              // "Not yours to shape" — the row should not have been reachable,
              // but a stale link can still land here.
              return AwEmptyState(
                icon: Icons.gavel_outlined,
                title: 'ee.slaAdmin.unavailable'.tr(),
                message: 'ee.slaAdmin.unavailableBody'.tr(),
              );
            }
            return TabBarView(
              children: [
                _PolicyList(data: value),
                _CalendarList(data: value),
                _MonitorList(data: value),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "09:00", and "06:00 (ertesi gün)" once it has crossed.
String formatShiftMinute(int minute) {
  final wrapped = minute % 1440;
  final h = (wrapped ~/ 60).toString().padLeft(2, '0');
  final m = (wrapped % 60).toString().padLeft(2, '0');
  final label = '$h:$m';
  return minute >= 1440 ? '$label ${'ee.slaAdmin.nextDay'.tr()}' : label;
}

String weekdayLabel(int weekday) => 'ee.slaAdmin.weekday.$weekday'.tr();

// ── policies ──────────────────────────────────────────────────────────────

class _PolicyList extends ConsumerWidget {
  const _PolicyList({required this.data});
  final EeSlaAdminData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (data.policies.isEmpty) {
      return AwEmptyState(
        icon: Icons.gavel_outlined,
        title: 'ee.slaAdmin.noPolicies'.tr(),
        message: 'ee.slaAdmin.noPoliciesBody'.tr(),
        action: FilledButton(
          key: const Key('sla-policy-new-empty'),
          onPressed: () => _editPolicy(context, ref, data, null),
          child: Text('ee.slaAdmin.newPolicy'.tr()),
        ),
      );
    }
    return Scaffold(
      // OPH-356 (UI-AUDIT #61): a create button exists on a yes only.
      floatingActionButton: !ref.watch(canProvider('sla.manage'))
          ? null
          : FloatingActionButton(
              key: const Key('sla-policy-new'),
              tooltip: 'ee.slaAdmin.newPolicy'.tr(),
              onPressed: () => _editPolicy(context, ref, data, null),
              child: const Icon(Icons.add),
            ),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: awScrollEndPadding(context, AwSpace.x4, fab: true),
        ),
        children: [
          for (final p in data.policies)
            ListTile(
              key: Key('sla-policy-${p.id}'),
              title: Row(
                children: [
                  Flexible(
                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                  ),
                  if (p.isDefault) ...[
                    const SizedBox(width: AwSpace.x2),
                    // A word, not a colour: there is exactly one of these per
                    // team and it decides what an unlabelled service promises.
                    Chip(
                      key: Key('sla-policy-default-${p.id}'),
                      label: Text('ee.slaAdmin.default'.tr()),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                [
                  data.calendarName(p.calendarId) ?? 'ee.slaAdmin.always'.tr(),
                  'ee.slaAdmin.warnAt'.tr(
                    args: {'percent': '${p.warnPercent}'},
                  ),
                  'ee.slaAdmin.targetCount'.tr(
                    args: {'n': '${p.targets.length}'},
                  ),
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
              onTap: () => _editPolicy(context, ref, data, p),
            ),
        ],
      ),
    );
  }
}

/// Runs an admin edit and puts a refusal in front of the person (UI-AUDIT
/// #22): the server's coded sentence, translated — "mark another policy as
/// the default first" — while the lists stay on screen.
Future<void> _guarded(
  BuildContext context,
  Future<void> Function() edit,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await edit();
  } catch (error) {
    messenger?.showSnackBar(SnackBar(content: Text(localizedError(error))));
  }
}

/// The priorities a target can be set for, most urgent first — the order the
/// desk reads them in.
const kSlaPriorities = ['urgent', 'high', 'normal', 'low'];

/// What the policy sheet hands back: the edit to save, or a wish to delete.
/// The sheet owns its text fields (and disposes them when it closes), so
/// only plain values leave it.
class _PolicyEdit {
  const _PolicyEdit({
    this.delete = false,
    this.name = '',
    this.calendarId,
    this.isDefault = false,
    this.warnPercent = 80,
    this.targets = const {},
  });

  final bool delete;
  final String name;
  final String? calendarId;
  final bool isDefault;
  final int warnPercent;

  /// Only the rows that changed: an untouched priority keeps whatever the
  /// server holds, and a cleared one travels as nulls (no promise).
  final Map<String, EeSlaTarget> targets;
}

Future<void> _editPolicy(
  BuildContext context,
  WidgetRef ref,
  EeSlaAdminData data,
  EeSlaPolicy? policy,
) async {
  final edit = await showModalBottomSheet<_PolicyEdit>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PolicySheet(data: data, policy: policy),
  );
  if (edit == null || !context.mounted) return;
  final controller = ref.read(eeSlaAdminProvider.notifier);
  if (!edit.delete) {
    await _guarded(
      context,
      () => controller.savePolicyAndTargets(
        id: policy?.id,
        name: edit.name,
        calendarId: edit.calendarId,
        isDefault: edit.isDefault,
        warnPercent: edit.warnPercent,
        targets: edit.targets,
      ),
    );
    return;
  }
  if (policy == null) return;
  // UI-AUDIT #22: the default is not deleted from here at all — it is
  // replaced. Saying so before the tap beats a refusal after it, and an older
  // server that would have deleted it is never asked.
  if (policy.isDefault) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        semanticLabel: 'ee.slaAdmin.defaultDeleteTitle'.tr(),
        title: Text('ee.slaAdmin.defaultDeleteTitle'.tr()),
        content: Text('error.SLA_POLICY_DEFAULT'.tr()),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('common.ok'.tr()),
          ),
        ],
      ),
    );
    return;
  }
  final ok = await awConfirmDelete(
    context,
    title: 'ee.slaAdmin.deletePolicyTitle'.tr(args: {'name': policy.name}),
    body: 'ee.slaAdmin.deletePolicyBody'.tr(),
    cancelLabel: 'ee.slaAdmin.keep'.tr(),
    confirmKey: const Key('sla-policy-delete-confirm'),
  );
  if (ok && context.mounted) {
    await _guarded(context, () => controller.deletePolicy(policy.id));
  }
}

class _PolicySheet extends StatefulWidget {
  const _PolicySheet({required this.data, this.policy});

  final EeSlaAdminData data;
  final EeSlaPolicy? policy;

  @override
  State<_PolicySheet> createState() => _PolicySheetState();
}

class _PolicySheetState extends State<_PolicySheet> {
  late final TextEditingController _name;
  late String? _calendarId;
  late bool _isDefault;
  late int _warnPercent;

  // UI-AUDIT #46 — the target table, one row per priority and two clocks a
  // row. The server had the endpoint all along and the app never wrote it,
  // so every policy showed "0 targets" and promised nothing.
  late final Map<String, (TextEditingController, TextEditingController)>
  _targets;

  @override
  void initState() {
    super.initState();
    final policy = widget.policy;
    _name = TextEditingController(text: policy?.name ?? '');
    _calendarId = policy?.calendarId;
    _isDefault = policy?.isDefault ?? false;
    _warnPercent = policy?.warnPercent ?? 80;
    _targets = {
      for (final p in kSlaPriorities)
        p: (
          TextEditingController(
            text: '${policy?.targetFor(p)?.firstResponseMinutes ?? ''}',
          ),
          TextEditingController(
            text: '${policy?.targetFor(p)?.resolutionMinutes ?? ''}',
          ),
        ),
    };
  }

  @override
  void dispose() {
    _name.dispose();
    for (final pair in _targets.values) {
      pair.$1.dispose();
      pair.$2.dispose();
    }
    super.dispose();
  }

  static int? _minutesOf(TextEditingController c) {
    final v = int.tryParse(c.text.trim());
    return v == null || v <= 0 ? null : v;
  }

  bool get _targetsValid => _targets.values.every(
    (pair) => [
      pair.$1,
      pair.$2,
    ].every((c) => c.text.trim().isEmpty || _minutesOf(c) != null),
  );

  _PolicyEdit _edit() {
    final changed = <String, EeSlaTarget>{};
    for (final p in kSlaPriorities) {
      final before = widget.policy?.targetFor(p);
      final first = _minutesOf(_targets[p]!.$1);
      final resolve = _minutesOf(_targets[p]!.$2);
      if (first != before?.firstResponseMinutes ||
          resolve != before?.resolutionMinutes) {
        changed[p] = EeSlaTarget(
          priority: p,
          firstResponseMinutes: first,
          resolutionMinutes: resolve,
        );
      }
    }
    return _PolicyEdit(
      name: _name.text.trim(),
      calendarId: _calendarId,
      isDefault: _isDefault,
      warnPercent: _warnPercent,
      targets: changed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final policy = widget.policy;
    return Padding(
      padding: EdgeInsets.only(
        left: AwSpace.x4,
        right: AwSpace.x4,
        top: AwSpace.x4,
        bottom: MediaQuery.of(context).viewInsets.bottom + AwSpace.x4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              policy == null
                  ? 'ee.slaAdmin.newPolicy'.tr()
                  : 'ee.slaAdmin.editPolicy'.tr(),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AwSpace.x3),
            TextField(
              key: const Key('sla-policy-name'),
              controller: _name,
              decoration: InputDecoration(
                labelText: 'ee.slaAdmin.policyName'.tr(),
              ),
              // UI-AUDIT #23: Save reads this field, so typing must redraw the
              // sheet — without it Save stayed off until something else (the
              // slider) happened to rebuild.
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AwSpace.x3),
            DropdownButtonFormField<String?>(
              key: const Key('sla-policy-calendar'),
              initialValue: _calendarId,
              decoration: InputDecoration(
                labelText: 'ee.slaAdmin.calendar'.tr(),
              ),
              items: [
                // Null is 24/7 and is offered first, because it is a real
                // contract rather than the absence of one.
                DropdownMenuItem(
                  value: null,
                  child: Text('ee.slaAdmin.always'.tr()),
                ),
                for (final c in widget.data.calendars)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _calendarId = v),
            ),
            const SizedBox(height: AwSpace.x3),
            Row(
              children: [
                Expanded(child: Text('ee.slaAdmin.warnPercent'.tr())),
                Text('%$_warnPercent'),
              ],
            ),
            Slider(
              key: const Key('sla-policy-warn'),
              value: _warnPercent.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: (v) => setState(() => _warnPercent = v.round()),
            ),
            // 0 and 100 are both honest ways to ask for no warning at all —
            // never, and "warn me as I break it", which is not a warning.
            Text(
              _warnPercent == 0 || _warnPercent == 100
                  ? 'ee.slaAdmin.warnOff'.tr()
                  : 'ee.slaAdmin.warnOn'.tr(args: {'percent': '$_warnPercent'}),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AwSpace.x2),
            SwitchListTile(
              key: const Key('sla-policy-default'),
              contentPadding: EdgeInsets.zero,
              value: _isDefault,
              title: Text('ee.slaAdmin.makeDefault'.tr()),
              subtitle: Text('ee.slaAdmin.makeDefaultBody'.tr()),
              onChanged: (v) => setState(() => _isDefault = v),
            ),
            const SizedBox(height: AwSpace.x3),
            Text('ee.slaAdmin.targets'.tr(), style: theme.textTheme.titleSmall),
            const SizedBox(height: AwSpace.x1),
            Text(
              'ee.slaAdmin.targetsHelp'.tr(),
              style: theme.textTheme.bodySmall,
            ),
            for (final p in kSlaPriorities)
              _TargetRow(
                priority: p,
                firstResponse: _targets[p]!.$1,
                resolution: _targets[p]!.$2,
                onChanged: () => setState(() {}),
              ),
            const SizedBox(height: AwSpace.x4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (policy != null)
                  TextButton(
                    key: const Key('sla-policy-delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(const _PolicyEdit(delete: true)),
                    child: Text('ee.slaAdmin.delete'.tr()),
                  ),
                const SizedBox(width: AwSpace.x2),
                FilledButton(
                  key: const Key('sla-policy-save'),
                  onPressed: _name.text.trim().isEmpty || !_targetsValid
                      ? null
                      : () => Navigator.of(context).pop(_edit()),
                  child: Text('ee.slaAdmin.save'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One priority's two clocks, in minutes, with the span read back in words.
class _TargetRow extends StatelessWidget {
  const _TargetRow({
    required this.priority,
    required this.firstResponse,
    required this.resolution,
    required this.onChanged,
  });

  final String priority;
  final TextEditingController firstResponse;
  final TextEditingController resolution;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    Widget field(String which, TextEditingController c, String labelKey) {
      final v = int.tryParse(c.text.trim());
      final invalid = c.text.trim().isNotEmpty && (v == null || v <= 0);
      return Expanded(
        child: TextField(
          key: Key('sla-target-$priority-$which'),
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: labelKey.tr(),
            suffixText: 'ee.slaAdmin.minutesSuffix'.tr(),
            // The minutes read back as a span, so "2880" is seen to be two
            // days before it is saved.
            helperText: invalid
                ? null
                : v == null
                ? 'ee.slaAdmin.noTarget'.tr()
                : eeSpanText(v.toDouble()),
            errorText: invalid ? 'ee.slaAdmin.targetInvalid'.tr() : null,
          ),
          onChanged: (_) => onChanged(),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: AwSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ee.tickets.priority.$priority'.tr(),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          // UI-AUDIT R2-4: an outlined field's label floats ON its top border,
          // half of it above the box — with no gap the heading and "First
          // reply" were drawn on top of each other. One spacing step clears
          // the floated label with room to spare.
          const SizedBox(height: AwSpace.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              field('first', firstResponse, 'ee.slaAdmin.firstResponse'),
              const SizedBox(width: AwSpace.x3),
              field('resolve', resolution, 'ee.slaAdmin.resolution'),
            ],
          ),
        ],
      ),
    );
  }
}

// ── calendars ─────────────────────────────────────────────────────────────

class _CalendarList extends ConsumerWidget {
  const _CalendarList({required this.data});
  final EeSlaAdminData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (data.calendars.isEmpty) {
      return AwEmptyState(
        icon: Icons.calendar_month_outlined,
        title: 'ee.slaAdmin.noCalendars'.tr(),
        message: 'ee.slaAdmin.noCalendarsBody'.tr(),
        action: FilledButton(
          key: const Key('sla-calendar-new-empty'),
          onPressed: () => _editCalendar(context, ref, data, null),
          child: Text('ee.slaAdmin.newCalendar'.tr()),
        ),
      );
    }
    return Scaffold(
      // OPH-356 (UI-AUDIT #61): a create button exists on a yes only.
      floatingActionButton: !ref.watch(canProvider('sla.manage'))
          ? null
          : FloatingActionButton(
              key: const Key('sla-calendar-new'),
              tooltip: 'ee.slaAdmin.newCalendar'.tr(),
              onPressed: () => _editCalendar(context, ref, data, null),
              child: const Icon(Icons.add),
            ),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: awScrollEndPadding(context, AwSpace.x4, fab: true),
        ),
        children: [
          for (final c in data.calendars)
            ExpansionTile(
              key: Key('sla-calendar-${c.id}'),
              title: Text(c.name),
              subtitle: Text(
                [
                  c.timezone ?? 'ee.slaAdmin.teamZone'.tr(),
                  'ee.slaAdmin.shiftCount'.tr(args: {'n': '${c.hours.length}'}),
                  'ee.slaAdmin.holidayCount'.tr(
                    args: {'n': '${c.holidays.length}'},
                  ),
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
              children: [
                for (final h in c.hours)
                  ListTile(
                    dense: true,
                    key: Key('sla-hour-${c.id}-${h.weekday}-${h.startMinute}'),
                    leading: const Icon(Icons.schedule, size: 18),
                    title: Text(
                      '${weekdayLabel(h.weekday)} · '
                      '${formatShiftMinute(h.startMinute)} – ${formatShiftMinute(h.endMinute)}',
                    ),
                  ),
                if (c.hours.isEmpty)
                  ListTile(
                    dense: true,
                    // A calendar with no hours is 24/7 on the server, and
                    // saying so is the difference between "always open" and
                    // "somebody forgot to fill this in".
                    title: Text(
                      'ee.slaAdmin.noShifts'.tr(),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                for (final holiday in c.holidays)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.event_busy_outlined, size: 18),
                    title: Text(
                      [
                        holiday.date,
                        holiday.name,
                      ].whereType<String>().join(' · '),
                    ),
                  ),
                OverflowBar(
                  children: [
                    TextButton(
                      key: Key('sla-calendar-edit-${c.id}'),
                      onPressed: () => _editCalendar(context, ref, data, c),
                      child: Text('ee.slaAdmin.edit'.tr()),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

Future<void> _editCalendar(
  BuildContext context,
  WidgetRef ref,
  EeSlaAdminData data,
  EeBusinessCalendar? calendar,
) async {
  final nameCtrl = TextEditingController(text: calendar?.name ?? '');
  final tzCtrl = TextEditingController(text: calendar?.timezone ?? '');

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _DisposeWith(
      controllers: [nameCtrl, tzCtrl],
      child: Padding(
        padding: EdgeInsets.only(
          left: AwSpace.x4,
          right: AwSpace.x4,
          top: AwSpace.x4,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + AwSpace.x4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              calendar == null
                  ? 'ee.slaAdmin.newCalendar'.tr()
                  : 'ee.slaAdmin.editCalendar'.tr(),
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            const SizedBox(height: AwSpace.x3),
            TextField(
              key: const Key('sla-calendar-name'),
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'ee.slaAdmin.calendarName'.tr(),
              ),
            ),
            const SizedBox(height: AwSpace.x3),
            TextField(
              key: const Key('sla-calendar-tz'),
              controller: tzCtrl,
              decoration: InputDecoration(
                labelText: 'ee.slaAdmin.timezone'.tr(),
                // Empty follows the team, which follows UTC — two levels of
                // "not chosen" rather than a default copied at create time.
                helperText: 'ee.slaAdmin.timezoneHelp'.tr(),
              ),
            ),
            const SizedBox(height: AwSpace.x4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (calendar != null)
                  TextButton(
                    key: const Key('sla-calendar-delete'),
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: Text('ee.slaAdmin.delete'.tr()),
                  ),
                const SizedBox(width: AwSpace.x2),
                FilledButton(
                  key: const Key('sla-calendar-save'),
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: Text('ee.slaAdmin.save'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  // Read now: the sheet owns the controllers and disposes them once its
  // closing animation ends, which a fast answer would otherwise outrun.
  final name = nameCtrl.text.trim();
  final timezone = tzCtrl.text.trim();

  if (saved == true && context.mounted) {
    await _guarded(
      context,
      () => ref
          .read(eeSlaAdminProvider.notifier)
          .saveCalendar(
            id: calendar?.id,
            name: name,
            timezone: timezone.isEmpty ? null : timezone,
          ),
    );
  } else if (saved == false && calendar != null && context.mounted) {
    // UI-AUDIT #22: the impact, before the tap. A calendar a policy still
    // counts against cannot go (the server refuses, by design), so the
    // dialog names the policies instead of offering a delete that fails.
    final users = [
      for (final p in data.policies)
        if (p.calendarId == calendar.id) p.name,
    ];
    if (users.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          semanticLabel: 'ee.slaAdmin.calendarInUseTitle'.tr(),
          title: Text('ee.slaAdmin.calendarInUseTitle'.tr()),
          content: Text(
            'ee.slaAdmin.calendarInUseBody'.tr(
              args: {'policies': users.join(', ')},
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('common.ok'.tr()),
            ),
          ],
        ),
      );
    } else {
      final ok = await awConfirmDelete(
        context,
        title: 'ee.slaAdmin.deleteCalendarTitle'.tr(
          args: {'name': calendar.name},
        ),
        body: 'ee.slaAdmin.deleteCalendarBody'.tr(),
        cancelLabel: 'ee.slaAdmin.keep'.tr(),
        confirmKey: const Key('sla-calendar-delete-confirm'),
      );
      if (ok && context.mounted) {
        await _guarded(
          context,
          () =>
              ref.read(eeSlaAdminProvider.notifier).deleteCalendar(calendar.id),
        );
      }
    }
  }
}

/// Hands a sheet's text controllers to the sheet itself (OPH-360): they are
/// disposed when the sheet's route is gone, not when the awaiting function
/// moves on — a fast save used to dispose them under the closing animation.
class _DisposeWith extends StatefulWidget {
  const _DisposeWith({required this.controllers, required this.child});

  final List<TextEditingController> controllers;
  final Widget child;

  @override
  State<_DisposeWith> createState() => _DisposeWithState();
}

class _DisposeWithState extends State<_DisposeWith> {
  @override
  void dispose() {
    for (final c in widget.controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ── monitors ──────────────────────────────────────────────────────────────

class _MonitorList extends ConsumerWidget {
  const _MonitorList({required this.data});
  final EeSlaAdminData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = context.awTokens;
    if (data.checks.isEmpty) {
      return AwEmptyState(
        icon: Icons.monitor_heart_outlined,
        title: 'ee.slaAdmin.noMonitors'.tr(),
        message: 'ee.slaAdmin.noMonitorsBody'.tr(),
        action: FilledButton(
          key: const Key('sla-monitor-new-empty'),
          onPressed: () => _editMonitor(context, ref, null),
          child: Text('ee.slaAdmin.newMonitor'.tr()),
        ),
      );
    }
    return Scaffold(
      // OPH-356 (UI-AUDIT #61): a create button exists on a yes only.
      floatingActionButton: !ref.watch(canProvider('sla.manage'))
          ? null
          : FloatingActionButton(
              key: const Key('sla-monitor-new'),
              tooltip: 'ee.slaAdmin.newMonitor'.tr(),
              onPressed: () => _editMonitor(context, ref, null),
              child: const Icon(Icons.add),
            ),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: awScrollEndPadding(context, AwSpace.x4, fab: true),
        ),
        children: [
          for (final c in data.checks)
            ListTile(
              key: Key('sla-monitor-${c.id}'),
              // The colour is the MARK. `down` takes `error`, which passes at
              // text strength anyway; `up` takes success; `unknown` is neutral
              // rather than amber, because "not asked yet" is not a warning.
              leading: Icon(
                switch (c.status) {
                  'up' => Icons.check_circle_outline,
                  'down' => Icons.error_outline,
                  _ => Icons.help_outline,
                },
                color: switch (c.status) {
                  'up' => tokens.success,
                  'down' => theme.colorScheme.error,
                  _ => theme.disabledColor,
                },
              ),
              title: Text(c.name),
              subtitle: Text(
                [
                  // And the meaning is the WORD, in body colour.
                  'ee.slaAdmin.health.${c.status}'.tr(),
                  if (!c.enabled) 'ee.slaAdmin.paused'.tr(),
                  c.url,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              onTap: () => _editMonitor(context, ref, c),
            ),
        ],
      ),
    );
  }
}

Future<void> _editMonitor(
  BuildContext context,
  WidgetRef ref,
  EeHealthCheck? check,
) async {
  final nameCtrl = TextEditingController(text: check?.name ?? '');
  final urlCtrl = TextEditingController(text: check?.url ?? '');
  final bodyCtrl = TextEditingController(text: check?.expectBody ?? '');
  bool enabled = check?.enabled ?? true;

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _DisposeWith(
      controllers: [nameCtrl, urlCtrl, bodyCtrl],
      child: StatefulBuilder(
        builder: (sheetContext, setState) => Padding(
          padding: EdgeInsets.only(
            left: AwSpace.x4,
            right: AwSpace.x4,
            top: AwSpace.x4,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + AwSpace.x4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                check == null
                    ? 'ee.slaAdmin.newMonitor'.tr()
                    : 'ee.slaAdmin.editMonitor'.tr(),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: AwSpace.x3),
              TextField(
                key: const Key('sla-monitor-name'),
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'ee.slaAdmin.monitorName'.tr(),
                ),
              ),
              const SizedBox(height: AwSpace.x3),
              TextField(
                key: const Key('sla-monitor-url'),
                controller: urlCtrl,
                decoration: InputDecoration(
                  labelText: 'ee.slaAdmin.url'.tr(),
                  // The server refuses anything but public http/https, and it
                  // says so in words. Repeating the rule here means the person
                  // reads it before typing rather than after being refused.
                  helperText: 'ee.slaAdmin.urlHelp'.tr(),
                ),
              ),
              const SizedBox(height: AwSpace.x3),
              TextField(
                key: const Key('sla-monitor-body'),
                controller: bodyCtrl,
                decoration: InputDecoration(
                  labelText: 'ee.slaAdmin.expectBody'.tr(),
                  helperText: 'ee.slaAdmin.expectBodyHelp'.tr(),
                ),
              ),
              SwitchListTile(
                key: const Key('sla-monitor-enabled'),
                contentPadding: EdgeInsets.zero,
                value: enabled,
                title: Text('ee.slaAdmin.enabled'.tr()),
                onChanged: (v) => setState(() => enabled = v),
              ),
              if (check?.lastError != null)
                Padding(
                  padding: const EdgeInsets.only(top: AwSpace.x2),
                  child: Text(
                    check!.lastError!,
                    key: const Key('sla-monitor-last-error'),
                    style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                      color: Theme.of(sheetContext).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: AwSpace.x4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (check != null)
                    TextButton(
                      key: const Key('sla-monitor-delete'),
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: Text('ee.slaAdmin.delete'.tr()),
                    ),
                  const SizedBox(width: AwSpace.x2),
                  FilledButton(
                    key: const Key('sla-monitor-save'),
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: Text('ee.slaAdmin.save'.tr()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  // Read now — see `_DisposeWith`.
  final name = nameCtrl.text.trim();
  final url = urlCtrl.text.trim();
  final body = bodyCtrl.text.trim();

  if (saved == true && context.mounted) {
    await _guarded(
      context,
      () => ref
          .read(eeSlaAdminProvider.notifier)
          .saveCheck(
            id: check?.id,
            name: name,
            url: url,
            expectBody: body.isEmpty ? null : body,
            enabled: enabled,
          ),
    );
  } else if (saved == false && check != null && context.mounted) {
    final ok = await awConfirmDelete(
      context,
      title: 'ee.slaAdmin.deleteMonitorTitle'.tr(args: {'name': check.name}),
      body: 'ee.slaAdmin.deleteMonitorBody'.tr(),
      cancelLabel: 'ee.slaAdmin.keep'.tr(),
      confirmKey: const Key('sla-monitor-delete-confirm'),
    );
    if (ok && context.mounted) {
      await _guarded(
        context,
        () => ref.read(eeSlaAdminProvider.notifier).deleteCheck(check.id),
      );
    }
  }
}
