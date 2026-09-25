import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/error_messages.dart';
import '../../../core/persisted_prefs.dart';
import '../../../core/reachability.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/fabs.dart';
import '../../../widgets/status_views.dart';
import '../../workspaces/workspaces.dart';
import '../absences_providers.dart';
import '../assignments_providers.dart';
import '../data/absences_api.dart';

/// EE-236 (AW-E18) — who is away, and who is on call because of it.
///
/// Two things on one screen because they are one question: somebody writes
/// "I am away next week", and the answer they want next is "so who has the
/// pager?". The on-call rows are the server's arithmetic (the same the
/// escalation pages from), never worked out here.
///
/// v1 by its limits, said on the screen: whole days, no approval, no reason.
/// Online only — an absence moves tonight's rota, so it reaches the server
/// when it is written or not at all.
class EeAbsencesScreen extends ConsumerWidget {
  const EeAbsencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(eeAbsencePageProvider);
    void reload() {
      ref.invalidate(eeAbsencePageProvider);
      ref.invalidate(eeMyOnCallProvider);
    }

    return Scaffold(
      appBar: AppBar(title: Text('ee.absences.title'.tr())),
      floatingActionButton: page.hasValue
          ? AwExtendedFab(
              key: const Key('absences-add'),
              onPressed: () => _add(context, page.value!),
              icon: const Icon(Icons.add),
              label: Text('ee.absences.add'.tr()),
            )
          : null,
      body: page.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => absencesNeedConnection(error)
            ? AwEmptyState(
                key: const Key('absences-offline'),
                icon: Icons.cloud_off_outlined,
                title: 'ee.absences.offlineTitle'.tr(),
                message: 'ee.absences.offlineBody'.tr(),
                action: OutlinedButton.icon(
                  onPressed: reload,
                  icon: const Icon(Icons.refresh),
                  label: Text('common.retry'.tr()),
                ),
              )
            : AwErrorState(message: localizedError(error), onRetry: reload),
        data: (data) => RefreshIndicator(
          onRefresh: () async {
            reload();
            await ref.read(eeAbsencePageProvider.future);
          },
          child: _AbsenceList(page: data),
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, EeAbsencePage page) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AbsenceSheet(page: page),
    );
  }
}

class _AbsenceList extends ConsumerWidget {
  const _AbsenceList({required this.page});
  final EeAbsencePage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final me = ref.watch(currentUserIdProvider);
    final format = ref.watch(dateFormatProvider);
    final onCall = ref.watch(eeMyOnCallProvider).value ?? const [];
    return ListView(
      padding: awListPadding(context, top: AwSpace.x4, extraBottom: 72),
      children: [
        if (onCall.isNotEmpty) ...[
          Text(
            'ee.absences.onCallTitle'.tr(),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AwSpace.x2),
          for (final unit in onCall)
            Card(
              key: Key('oncall-${unit.unitId}'),
              child: ListTile(
                leading: Icon(
                  unit.nobodyAvailable
                      ? Icons.phone_disabled_outlined
                      : Icons.phone_in_talk_outlined,
                ),
                title: Text(unit.unitName),
                subtitle: Text(_onCallLine(unit, me: me, format: format)),
              ),
            ),
          const SizedBox(height: AwSpace.x4),
        ],
        Text('ee.absences.listTitle'.tr(), style: theme.textTheme.titleSmall),
        const SizedBox(height: AwSpace.x2),
        if (page.absences.isEmpty)
          Padding(
            key: const Key('absences-empty'),
            padding: const EdgeInsets.symmetric(vertical: AwSpace.x2),
            child: Text(
              'ee.absences.empty'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          )
        else
          for (final absence in page.absences)
            Card(
              key: Key('absence-${absence.id}'),
              child: ListTile(
                leading: const Icon(Icons.event_busy_outlined),
                title: Text(
                  absence.userId == me
                      ? 'ee.absences.you'.tr()
                      : (absence.userName ?? '—'),
                ),
                subtitle: Text(_range(absence, format: format)),
                // Only what the door allows: your own, or everybody's for
                // somebody who records them for others.
                trailing: absence.userId == me || page.canManage
                    ? IconButton(
                        key: Key('absence-remove-${absence.id}'),
                        tooltip: 'ee.absences.remove'.tr(),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _remove(context, ref, absence),
                      )
                    : null,
              ),
            ),
        if (page.truncated)
          Padding(
            key: const Key('absences-truncated'),
            padding: const EdgeInsets.only(top: AwSpace.x2),
            child: Text(
              'ee.absences.truncated'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
      ],
    );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    EeAbsence absence,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ee.absences.removeTitle'.tr()),
        content: Text('ee.absences.removeBody'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('absence-remove-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('ee.absences.remove'.tr()),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await ref.read(eeAbsencesApiProvider).delete(absence.id);
    } catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(localizedError(error))));
      return;
    }
    ref.invalidate(eeAbsencePageProvider);
    ref.invalidate(eeMyOnCallProvider);
  }
}

/// "Nöbette: Burak · Ayşe izinde · bitiş 8.10.2026 00:00" — names without
/// suffixes, because a Turkish genitive depends on the name's last vowel and
/// a sentence that guessed it would be wrong for half the team.
String _onCallLine(EeOnCallNow unit, {String? me, required String format}) {
  if (unit.nobodyAvailable) return 'ee.absences.onCallNobody'.tr();
  String name(String? id, String? label) =>
      id != null && id == me ? 'ee.absences.you'.tr() : (label ?? '—');
  final until = unit.until == null
      ? '—'
      : awFormatDateTime(unit.until!, format: format);
  if (unit.coveringFor == null) {
    return 'ee.absences.onCallNow'.tr(
      args: {'name': name(unit.userId, unit.userName), 'until': until},
    );
  }
  // Covering for the person reading: its own sentence in both languages —
  // "covering for You" and "Siz izinde" were both wrong mid-sentence.
  if (unit.coveringFor == me) {
    return 'ee.absences.onCallCoveringYou'.tr(
      args: {'name': name(unit.userId, unit.userName), 'until': until},
    );
  }
  return 'ee.absences.onCallCovering'.tr(
    args: {
      'name': name(unit.userId, unit.userName),
      'for': name(unit.coveringFor, unit.coveringForName),
      'until': until,
    },
  );
}

/// A calendar day as the phone shows dates. The server's day is a UTC
/// midnight; formatting that as-is would show the day before anywhere west
/// of Greenwich, so the same year, month and day are rebuilt as a local date.
String _day(DateTime day, {required String format}) =>
    awFormatDate(DateTime(day.year, day.month, day.day), format: format);

String _range(EeAbsence absence, {required String format}) {
  final start = _day(absence.startDate, format: format);
  if (absence.startDate == absence.endDate) return start;
  return '$start – ${_day(absence.endDate, format: format)}';
}

/// Recording one: whose (only when this person may record for others), and
/// which days. Saved online or not at all — greyed out, with the reason, when
/// the app knows there is no connection.
class _AbsenceSheet extends ConsumerStatefulWidget {
  const _AbsenceSheet({required this.page});
  final EeAbsencePage page;

  @override
  ConsumerState<_AbsenceSheet> createState() => _AbsenceSheetState();
}

class _AbsenceSheetState extends ConsumerState<_AbsenceSheet> {
  String? _userId; // null = yourself
  late DateTimeRange _days = () {
    final t = widget.page.today ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    return DateTimeRange(start: today, end: today);
  }();
  bool _busy = false;
  String? _error;

  Future<void> _pickDays() async {
    final today = widget.page.today ?? DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year, today.month, today.day - 90),
      lastDate: DateTime(today.year + 1, today.month, today.day),
      initialDateRange: _days,
    );
    if (picked != null) setState(() => _days = picked);
  }

  Future<void> _save() async {
    if (_days.end.difference(_days.start).inDays + 1 > 366) {
      setState(() => _error = 'error.ABSENCE_TOO_LONG'.tr());
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(eeAbsencesApiProvider)
          .create(startDate: _days.start, endDate: _days.end, userId: _userId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = localizedError(error);
      });
      return;
    }
    ref.invalidate(eeAbsencePageProvider);
    ref.invalidate(eeMyOnCallProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final format = ref.watch(dateFormatProvider);
    final me = ref.watch(currentUserIdProvider);
    final offline = ref.watch(
      serverReachabilityProvider.select((up) => up == false),
    );
    final roster = widget.page.canManage
        ? (ref.watch(workspaceRosterProvider).value ?? const [])
        : const [];
    final days = _days.start == _days.end
        ? awFormatDate(_days.start, format: format)
        : '${awFormatDate(_days.start, format: format)} – '
              '${awFormatDate(_days.end, format: format)}';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AwSpace.x4,
        0,
        AwSpace.x4,
        AwSpace.x4 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ee.absences.add'.tr(), style: theme.textTheme.titleLarge),
          const SizedBox(height: AwSpace.x4),
          if (widget.page.canManage) ...[
            DropdownButtonFormField<String?>(
              key: const Key('absence-person'),
              initialValue: _userId,
              decoration: InputDecoration(labelText: 'ee.absences.person'.tr()),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('ee.absences.you'.tr()),
                ),
                for (final member in roster)
                  if (member.userId != me)
                    DropdownMenuItem<String?>(
                      value: member.userId,
                      child: Text(member.displayName ?? '—'),
                    ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _userId = value),
            ),
            const SizedBox(height: AwSpace.x3),
          ],
          OutlinedButton.icon(
            key: const Key('absence-days'),
            onPressed: _busy ? null : _pickDays,
            icon: const Icon(Icons.date_range_outlined),
            label: Text(days),
          ),
          const SizedBox(height: AwSpace.x2),
          // v1 by its limits, said where the absence is written.
          Text(
            'ee.absences.limits'.tr(),
            key: const Key('absences-limits'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AwSpace.x3),
            AwInlineError(
              message: _error!,
              textKey: const Key('absence-error'),
            ),
          ],
          const SizedBox(height: AwSpace.x4),
          FilledButton(
            key: const Key('absence-save'),
            onPressed: _busy || offline ? null : _save,
            child: Text('ee.absences.save'.tr()),
          ),
          if (offline) ...[
            const SizedBox(height: AwSpace.x2),
            Text(
              'ee.absences.saveOffline'.tr(),
              key: const Key('absence-save-offline'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
