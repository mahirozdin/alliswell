import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/sla_admin_models.dart';
import '../sla_admin_providers.dart';

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
      floatingActionButton: FloatingActionButton(
        key: const Key('sla-policy-new'),
        tooltip: 'ee.slaAdmin.newPolicy'.tr(),
        onPressed: () => _editPolicy(context, ref, data, null),
        child: const Icon(Icons.add),
      ),
      body: ListView(
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

Future<void> _editPolicy(
  BuildContext context,
  WidgetRef ref,
  EeSlaAdminData data,
  EeSlaPolicy? policy,
) async {
  final nameCtrl = TextEditingController(text: policy?.name ?? '');
  String? calendarId = policy?.calendarId;
  bool isDefault = policy?.isDefault ?? false;
  int warnPercent = policy?.warnPercent ?? 80;

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
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
              policy == null
                  ? 'ee.slaAdmin.newPolicy'.tr()
                  : 'ee.slaAdmin.editPolicy'.tr(),
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
            const SizedBox(height: AwSpace.x3),
            TextField(
              key: const Key('sla-policy-name'),
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'ee.slaAdmin.policyName'.tr(),
              ),
            ),
            const SizedBox(height: AwSpace.x3),
            DropdownButtonFormField<String?>(
              key: const Key('sla-policy-calendar'),
              initialValue: calendarId,
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
                for (final c in data.calendars)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => calendarId = v),
            ),
            const SizedBox(height: AwSpace.x3),
            Row(
              children: [
                Expanded(child: Text('ee.slaAdmin.warnPercent'.tr())),
                Text('%$warnPercent'),
              ],
            ),
            Slider(
              key: const Key('sla-policy-warn'),
              value: warnPercent.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: (v) => setState(() => warnPercent = v.round()),
            ),
            // 0 and 100 are both honest ways to ask for no warning at all —
            // never, and "warn me as I break it", which is not a warning.
            Text(
              warnPercent == 0 || warnPercent == 100
                  ? 'ee.slaAdmin.warnOff'.tr()
                  : 'ee.slaAdmin.warnOn'.tr(args: {'percent': '$warnPercent'}),
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: AwSpace.x2),
            SwitchListTile(
              key: const Key('sla-policy-default'),
              contentPadding: EdgeInsets.zero,
              value: isDefault,
              title: Text('ee.slaAdmin.makeDefault'.tr()),
              subtitle: Text('ee.slaAdmin.makeDefaultBody'.tr()),
              onChanged: (v) => setState(() => isDefault = v),
            ),
            const SizedBox(height: AwSpace.x4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (policy != null)
                  TextButton(
                    key: const Key('sla-policy-delete'),
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: Text('ee.slaAdmin.delete'.tr()),
                  ),
                const SizedBox(width: AwSpace.x2),
                FilledButton(
                  key: const Key('sla-policy-save'),
                  onPressed: nameCtrl.text.trim().isEmpty
                      ? null
                      : () => Navigator.of(sheetContext).pop(true),
                  child: Text('ee.slaAdmin.save'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (saved == true) {
    await ref
        .read(eeSlaAdminProvider.notifier)
        .savePolicy(
          id: policy?.id,
          name: nameCtrl.text.trim(),
          calendarId: calendarId,
          isDefault: isDefault,
          warnPercent: warnPercent,
        );
  } else if (saved == false && policy != null) {
    await ref.read(eeSlaAdminProvider.notifier).deletePolicy(policy.id);
  }
  nameCtrl.dispose();
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
          onPressed: () => _editCalendar(context, ref, null),
          child: Text('ee.slaAdmin.newCalendar'.tr()),
        ),
      );
    }
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        key: const Key('sla-calendar-new'),
        tooltip: 'ee.slaAdmin.newCalendar'.tr(),
        onPressed: () => _editCalendar(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: ListView(
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
                      onPressed: () => _editCalendar(context, ref, c),
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
  EeBusinessCalendar? calendar,
) async {
  final nameCtrl = TextEditingController(text: calendar?.name ?? '');
  final tzCtrl = TextEditingController(text: calendar?.timezone ?? '');

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
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
  );

  if (saved == true) {
    await ref
        .read(eeSlaAdminProvider.notifier)
        .saveCalendar(
          id: calendar?.id,
          name: nameCtrl.text.trim(),
          timezone: tzCtrl.text.trim().isEmpty ? null : tzCtrl.text.trim(),
        );
  } else if (saved == false && calendar != null) {
    await ref.read(eeSlaAdminProvider.notifier).deleteCalendar(calendar.id);
  }
  nameCtrl.dispose();
  tzCtrl.dispose();
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
      floatingActionButton: FloatingActionButton(
        key: const Key('sla-monitor-new'),
        tooltip: 'ee.slaAdmin.newMonitor'.tr(),
        onPressed: () => _editMonitor(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: ListView(
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
    builder: (sheetContext) => StatefulBuilder(
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
  );

  if (saved == true) {
    await ref
        .read(eeSlaAdminProvider.notifier)
        .saveCheck(
          id: check?.id,
          name: nameCtrl.text.trim(),
          url: urlCtrl.text.trim(),
          expectBody: bodyCtrl.text.trim().isEmpty
              ? null
              : bodyCtrl.text.trim(),
          enabled: enabled,
        );
  } else if (saved == false && check != null) {
    await ref.read(eeSlaAdminProvider.notifier).deleteCheck(check.id);
  }
  nameCtrl.dispose();
  urlCtrl.dispose();
  bodyCtrl.dispose();
}
