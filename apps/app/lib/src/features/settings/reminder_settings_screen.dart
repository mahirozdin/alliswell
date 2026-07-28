import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_format.dart';
import '../../core/persisted_prefs.dart';
import '../../i18n/i18n.dart';
import '../../notifications/providers.dart';
import '../../notifications/reminder_profile.dart';
import 'sound_picker_sheet.dart';
import '../../theme/tokens.dart';
import '../../widgets/status_views.dart';

/// **Hatırlatıcı Sistemi Ayarları** (round 9 #7, OPH-179 — DESIGN §18).
///
/// One destination for how insistent an urgent alarm is: ready-made chains
/// first (N2), the step editor as the escape hatch (N3), the limits stated
/// rather than silently applied (N5), and drag-to-reorder only where order is
/// actually the user's to choose — the snooze buttons (N4).
class ReminderSettingsScreen extends ConsumerWidget {
  const ReminderSettingsScreen({super.key});

  /// The sample alarm the timeline previews: round 9's own 22:42.
  static DateTime _sampleBase(DateTime now) =>
      DateTime(now.year, now.month, now.day, 22, 42);

  Future<void> _save(WidgetRef ref, ReminderProfile profile) => ref
      .read(reminderProfileRawProvider.notifier)
      .set(
        profile
            .copyWith(slots: ReminderProfile.normalizeSlots(profile.slots))
            .encode(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(reminderProfileProvider);
    final dateFormat = ref.watch(dateFormatProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = _sampleBase(DateTime.now());
    final presetId = profile.presetId;

    return Scaffold(
      appBar: AppBar(title: Text('reminderSettings.title'.tr())),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: awListPadding(context, top: AwSpace.x2),
            children: [
              // N2 — ready-made first: most people should never touch a stepper.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AwSpace.x4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'reminderSettings.presets'.tr(),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: AwSpace.x3),
                      SegmentedButton<String>(
                        key: const Key('reminder-presets'),
                        showSelectedIcon: false,
                        segments: [
                          for (final preset in kReminderProfilePresets)
                            ButtonSegment(
                              value: preset.id,
                              label: Text(
                                'reminderSettings.preset.${preset.id}'.tr(),
                              ),
                            ),
                          // A hand-built chain is a real state, not a blank.
                          ButtonSegment(
                            value: 'custom',
                            label: Text('reminderSettings.preset.custom'.tr()),
                          ),
                        ],
                        selected: {presetId ?? 'custom'},
                        onSelectionChanged: (selection) {
                          final id = selection.first;
                          if (id == 'custom') return; // nothing to apply
                          final preset = kReminderProfilePresets.firstWhere(
                            (p) => p.id == id,
                          );
                          _save(ref, profile.copyWith(slots: preset.slots));
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AwSpace.x3),

              // N3 — the chain, and when each alert actually rings.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AwSpace.x4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'reminderSettings.chain'.tr(),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: AwSpace.x2),
                      // The live timeline: the answer to "5 dk sonra ne olacak?"
                      // BEFORE it is experienced.
                      Text(
                        'reminderSettings.timeline'.tr(
                          args: {
                            'time': awFormatTime(base, format: dateFormat),
                          },
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        key: const Key('reminder-timeline'),
                        [
                          for (final minutes in profile.slots)
                            awFormatTime(
                              base.add(Duration(minutes: minutes)),
                              format: dateFormat,
                            ),
                        ].join(' → '),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Divider(height: AwSpace.x6),
                      for (final (index, minutes) in profile.slots.indexed)
                        _StepRow(
                          index: index,
                          minutes: minutes,
                          minMinutes: ReminderProfile.minSlotAfter(
                            index == 0 ? null : profile.slots[index - 1],
                          ),
                          maxMinutes: index + 1 < profile.slots.length
                              ? profile.slots[index + 1] -
                                    kMinReminderGapMinutes
                              : null,
                          canRemove: profile.slots.length > 1,
                          onChanged: (value) {
                            final slots = [...profile.slots];
                            slots[index] = value;
                            _save(ref, profile.copyWith(slots: slots));
                          },
                          onRemove: () {
                            final slots = [...profile.slots]..removeAt(index);
                            _save(ref, profile.copyWith(slots: slots));
                          },
                        ),
                      const SizedBox(height: AwSpace.x2),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const Key('reminder-add-step'),
                          onPressed: profile.slots.length >= kMaxReminderSlots
                              ? null
                              : () {
                                  final slots = [
                                    ...profile.slots,
                                    profile.slots.last +
                                        kMinReminderGapMinutes * 5,
                                  ];
                                  _save(ref, profile.copyWith(slots: slots));
                                },
                          icon: const Icon(Icons.add, size: 18),
                          label: Text('reminderSettings.addStep'.tr()),
                        ),
                      ),
                      // N5 — limits are STATED, never silently applied.
                      const SizedBox(height: AwSpace.x2),
                      Text(
                        'reminderSettings.minGap'.tr(
                          args: {'minutes': '$kMinReminderGapMinutes'},
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        'reminderSettings.maxSteps'.tr(
                          args: {'count': '$kMaxReminderSlots'},
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AwSpace.x2),
                      Text(
                        key: const Key('reminder-capacity'),
                        'reminderSettings.capacity'.tr(
                          args: {'count': '${profile.alarmsFullyCovered}'},
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (profile.slots.length > 10) ...[
                        const SizedBox(height: AwSpace.x2),
                        AwInlineError(
                          key: const Key('reminder-capacity-warning'),
                          message: 'reminderSettings.capacityWarning'.tr(),
                        ),
                      ],
                      const Divider(height: AwSpace.x6),
                      SwitchListTile(
                        key: const Key('reminder-repeat-after-snooze'),
                        contentPadding: EdgeInsets.zero,
                        title: Text('reminderSettings.repeatAfterSnooze'.tr()),
                        subtitle: Text(
                          'reminderSettings.repeatAfterSnoozeSub'.tr(),
                        ),
                        value: profile.repeatAfterSnooze,
                        onChanged: (value) => _save(
                          ref,
                          profile.copyWith(repeatAfterSnooze: value),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          key: const Key('reminder-reset'),
                          onPressed: () => _save(ref, ReminderProfile.factory),
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: Text('reminderSettings.reset'.tr()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AwSpace.x3),

              // N6 — sounds are chosen by HEARING them.
              Card(
                child: Column(
                  children: [
                    ListTile(
                      key: const Key('sound-row-alarm'),
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: Text('sound.alarmTitle'.tr()),
                      subtitle: Text(
                        soundChoiceLabel(ref.watch(alarmSoundChoiceProvider)),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showSoundPicker(context, SoundLane.alarm),
                    ),
                    ListTile(
                      key: const Key('sound-row-reminder'),
                      leading: const Icon(Icons.notifications_outlined),
                      title: Text('sound.reminderTitle'.tr()),
                      subtitle: Text(
                        soundChoiceLabel(
                          ref.watch(reminderSoundChoiceProvider),
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showSoundPicker(context, SoundLane.reminder),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AwSpace.x3),

              // N4 — the ONE list where dragging means something.
              const _SnoozeOrderCard(),
            ],
          ),
        ),
      ),
    );
  }
}

/// One alert of the chain: which one it is, how far after the alarm it fires,
/// and a stepper clamped so the 1-minute rule holds WHILE editing (N5).
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.minutes,
    required this.minMinutes,
    required this.maxMinutes,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final int minutes;
  final int minMinutes;
  final int? maxMinutes;
  final bool canRemove;
  final void Function(int minutes) onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canDecrease = minutes > minMinutes;
    final canIncrease = maxMinutes == null || minutes < maxMinutes!;
    return ListTile(
      key: Key('reminder-step-$index'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        'reminderSettings.step'.tr(args: {'index': '${index + 1}'}),
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        minutes == 0
            ? 'reminderSettings.immediately'.tr()
            : 'reminderSettings.atInstant'.tr(args: {'minutes': '$minutes'}),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('reminder-step-$index-minus'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: canDecrease ? () => onChanged(minutes - 1) : null,
          ),
          IconButton(
            key: Key('reminder-step-$index-plus'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline),
            onPressed: canIncrease ? () => onChanged(minutes + 1) : null,
          ),
          IconButton(
            key: Key('reminder-step-$index-remove'),
            visualDensity: VisualDensity.compact,
            tooltip: 'reminderSettings.removeStep'.tr(),
            icon: const Icon(Icons.close),
            onPressed: canRemove ? onRemove : null,
          ),
        ],
      ),
    );
  }
}

/// The snooze buttons in the user's own order (N4). A sorted numeric chain
/// re-sorts itself, so dragging it would be a gesture the system undoes — this
/// list is the one where the order IS the data.
class _SnoozeOrderCard extends ConsumerWidget {
  const _SnoozeOrderCard();

  static const _labels = {
    '5_min': 'notif.action.snooze5m',
    '30_min': 'notif.action.snooze30m',
    '1_hour': 'notif.action.snooze1h',
    'tomorrow_morning': 'notif.action.snoozeTomorrow',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(snoozePresetOrderProvider);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'reminderSettings.snoozeOrder'.tr(),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'reminderSettings.snoozeOrderSub'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AwSpace.x2),
            ReorderableListView(
              key: const Key('snooze-order-list'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: true,
              // onReorderItem hands us an index already adjusted for the
              // removal, so no off-by-one dance here.
              onReorderItem: (from, to) {
                final next = [...order];
                next.insert(to, next.removeAt(from));
                ref
                    .read(snoozePresetOrderRawProvider.notifier)
                    .set(next.join(','));
              },
              children: [
                for (final id in order)
                  ListTile(
                    key: Key('snooze-order-$id'),
                    dense: true,
                    leading: const Icon(Icons.drag_handle),
                    title: Text((_labels[id] ?? id).tr()),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
