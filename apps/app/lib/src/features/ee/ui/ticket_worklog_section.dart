import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import '../../../i18n/i18n.dart';
import '../data/worklog_models.dart';
import '../worklog_providers.dart';

/// The hours on a request (EE-208).
///
/// ── ENTERED BY HAND, AND THERE IS NO TIMER ──────────────────────────────
///
/// The task's own reason, kept in the UI where it shows: a technician in the
/// field does not start a stopwatch, and a start/stop button would produce a
/// second source of truth for the same minutes — wrong every time somebody
/// forgets to stop it, and wrong in the direction that inflates a bill. So
/// the entry is a number and a day, and the day defaults to today because
/// "I just finished" is the ordinary case.
///
/// ── THE COST FIELD IS ABSENT WHEN THERE IS NO RATE, NOT EMPTY ───────────
///
/// The acceptance line asks for it and the reason is that zero is a CLAIM. A
/// desk whose people sit on base roles has no rates at all, so nothing here
/// prints money — but `unpricedMinutes` is still shown, because an empty cost
/// beside two hours of real work reads as "that was free" unless something
/// says otherwise.
///
/// ── AND TWO CURRENCIES ARE TWO LINES ────────────────────────────────────
///
/// The totals come from the SERVER, already grouped. This widget never adds
/// anything: it is the one place a client could quietly produce a
/// cross-currency figure, and the way to make that impossible is to never
/// hand it the arithmetic.
class EeTicketWorklogSection extends ConsumerWidget {
  const EeTicketWorklogSection({required this.ticketId, super.key});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final panel = ref.watch(eeWorklogProvider(ticketId));

    return panel.when(
      // Quiet on both: the request above is readable without this, and a red
      // box here would make a slow network look like a broken record.
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) {
        if (data == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AwSpace.x6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'ee.worklogs.title'.tr(),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  key: const Key('worklog-add'),
                  onPressed: () => _openSheet(context, ref),
                  icon: const Icon(Icons.more_time),
                  label: Text('ee.worklogs.add'.tr()),
                ),
              ],
            ),
            if (data.worklogs.isEmpty)
              Text(
                'ee.worklogs.empty'.tr(),
                key: const Key('worklog-empty'),
                style: theme.textTheme.bodySmall,
              )
            else ...[
              for (final row in data.worklogs)
                _Row(ticketId: ticketId, row: row),
              const SizedBox(height: AwSpace.x2),
              _Totals(totals: data.totals),
            ],
          ],
        );
      },
    );
  }

  Future<void> _openSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddSheet(ticketId: ticketId),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.ticketId, required this.row});

  final String ticketId;
  final EeWorklog row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      key: Key('worklog-${row.id}'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.schedule),
      title: Text(
        'ee.worklogs.entry'.tr(
          args: {'hours': _hours(row.minutes), 'date': row.workedOn},
        ),
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: row.note == null || row.note!.isEmpty
          ? null
          : Text(row.note!, style: theme.textTheme.bodySmall),
      // HIDDEN, not empty. A dash or a "—" here would still be a statement
      // about the cost of an hour.
      trailing: row.hasCost
          ? Text(
              'ee.worklogs.money'.tr(
                args: {
                  'amount': (row.costMinor! / 100).toStringAsFixed(2),
                  'currency': row.currency!,
                },
              ),
              key: Key('worklog-cost-${row.id}'),
              style: theme.textTheme.labelLarge,
            )
          : null,
      onLongPress: () => _confirmRemove(context, ref),
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('ee.worklogs.removeTitle'.tr()),
        // Says what happens rather than asking "are you sure": a correction is
        // a withdrawal and a new entry, and somebody about to fix a typo
        // should know they are about to retype it.
        content: Text('ee.worklogs.removeBody'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('worklog-remove-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('ee.worklogs.remove'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(eeWorklogActionsProvider(ticketId)).remove(row.id);
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.totals});

  final EeWorklogTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ee.worklogs.totalHours'.tr(args: {'hours': _hours(totals.minutes)}),
          key: const Key('worklog-total-hours'),
          style: theme.textTheme.bodyMedium,
        ),
        // One line per currency. The list IS the refusal to add them.
        for (final money in totals.byCurrency)
          Text(
            'ee.worklogs.money'.tr(
              args: {
                'amount': (money.costMinor / 100).toStringAsFixed(2),
                'currency': money.currency,
              },
            ),
            key: Key('worklog-total-${money.currency}'),
            style: theme.textTheme.labelLarge,
          ),
        if (totals.unpricedMinutes > 0)
          Text(
            'ee.worklogs.unpriced'.tr(
              args: {'hours': _hours(totals.unpricedMinutes)},
            ),
            key: const Key('worklog-unpriced'),
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet({required this.ticketId});

  final String ticketId;

  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  final _minutes = TextEditingController();
  final _note = TextEditingController();
  DateTime _day = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _minutes.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _dayText =>
      '${_day.year.toString().padLeft(4, '0')}-'
      '${_day.month.toString().padLeft(2, '0')}-'
      '${_day.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AwSpace.x4,
        right: AwSpace.x4,
        top: AwSpace.x4,
        bottom: MediaQuery.of(context).viewInsets.bottom + AwSpace.x4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ee.worklogs.add'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AwSpace.x3),
          TextField(
            key: const Key('worklog-minutes'),
            controller: _minutes,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'ee.worklogs.minutes'.tr(),
              helperText: 'ee.worklogs.minutesHelp'.tr(),
              errorText: _error,
            ),
          ),
          const SizedBox(height: AwSpace.x3),
          // The DAY the work happened, not the day it is typed. Friday's hours
          // written on Monday belong to Friday, and a month's report that
          // filed them under Monday would move work between months.
          ListTile(
            key: const Key('worklog-day'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text('ee.worklogs.day'.tr(args: {'date': _dayText})),
            trailing: TextButton(
              onPressed: _pickDay,
              child: Text('ee.worklogs.changeDay'.tr()),
            ),
          ),
          TextField(
            key: const Key('worklog-note'),
            controller: _note,
            decoration: InputDecoration(labelText: 'ee.worklogs.note'.tr()),
          ),
          const SizedBox(height: AwSpace.x4),
          FilledButton(
            key: const Key('worklog-save'),
            onPressed: _saving ? null : _save,
            child: Text('common.save'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: now.subtract(const Duration(days: 365)),
      // Not past today. A day that has not happened is a typo, and it would
      // land in a month that has not been reported — the one error nobody
      // notices until the report is already out.
      lastDate: now,
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _save() async {
    final minutes = int.tryParse(_minutes.text.trim());
    if (minutes == null || minutes <= 0) {
      setState(() => _error = 'ee.worklogs.minutesInvalid'.tr());
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(eeWorklogActionsProvider(widget.ticketId))
          .add(minutes: minutes, workedOn: _dayText, note: _note.text.trim());
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$err';
        });
      }
    }
  }
}

/// Minutes as hours, to one decimal — the unit people say out loud.
///
/// Stored as minutes and shown as hours on purpose: nobody types 0.1 h, and
/// 0.1 h is six minutes rounded differently by every desk that tries.
String _hours(int minutes) => (minutes / 60).toStringAsFixed(1);
