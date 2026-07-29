import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';
import '../../../core/recurrence.dart';
import '../../../core/recurrence_text.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';

/// The recurrence dialog (OPH-207, DESIGN §25 R1-R9).
///
/// Presets first, "Gelişmiş" one disclosure deeper, and the "Sonraki 5" preview
/// always in view — it is the only place the user can see that a rule survived
/// a short month, so it never scrolls out of reach (R4).
///
/// Returns the rule, or null when the user cancels — which is what turns the
/// Repeat switch back off (R1).
Future<AwRepeatRule?> showRepeatDialog(
  BuildContext context, {
  required DateTime anchor,
  AwRepeatRule? initial,
}) => showDialog<AwRepeatRule>(
  context: context,
  // The dialog goes to the ROOT navigator: pushed into a shell branch it would
  // render under the shell's own bar and FAB (OPH-212's lesson).
  useRootNavigator: true,
  builder: (_) => _RepeatDialog(anchor: anchor, initial: initial),
);

enum _MonthMode { monthDay, nthWeekday, afterDay }

class _RepeatDialog extends ConsumerStatefulWidget {
  const _RepeatDialog({required this.anchor, this.initial});

  final DateTime anchor;
  final AwRepeatRule? initial;

  @override
  ConsumerState<_RepeatDialog> createState() => _RepeatDialogState();
}

class _RepeatDialogState extends ConsumerState<_RepeatDialog> {
  late AwRepeatFreq _freq;
  late int _interval;
  late Set<String> _weekdays;
  late _MonthMode _monthMode;
  late int _monthDay;
  late bool _lastDay;
  late int _ordinal;
  late String _ordinalWeekday;
  late int _afterDay;
  late String _afterWeekday;
  late String _endType;
  DateTime? _until;
  late int _count;
  bool _advanced = false;

  // R5: the dialog owns its controllers for its whole lifetime. Disposing them
  // when `showDialog` returns rebuilds the fields mid-animation and throws —
  // round 11 shipped that bug three times.
  final _intervalController = TextEditingController();
  final _countController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final rule = widget.initial;
    final anchorWeekday = kAwWeekdays[widget.anchor.weekday - 1];
    _freq = rule?.freq ?? AwRepeatFreq.monthly;
    _interval = rule?.interval ?? 1;
    _weekdays = rule?.byWeekday.map((w) => w.day).toSet() ?? {anchorWeekday};
    _monthDay = widget.anchor.day;
    _lastDay = false;
    _ordinal = 1;
    _ordinalWeekday = anchorWeekday;
    _afterDay = widget.anchor.day > 1 ? widget.anchor.day - 1 : 1;
    _afterWeekday = anchorWeekday;
    _monthMode = _MonthMode.monthDay;

    if (rule != null) {
      final after = awAfterDayOf(rule);
      if (after != null) {
        _monthMode = _MonthMode.afterDay;
        _afterDay = after.day;
        _afterWeekday = after.weekday;
      } else if (rule.byMonthDay.isNotEmpty) {
        _monthMode = _MonthMode.monthDay;
        _lastDay = rule.byMonthDay.first == -1;
        if (!_lastDay) _monthDay = rule.byMonthDay.first;
      } else if (rule.byWeekday.isNotEmpty &&
          rule.byWeekday.first.ordinal != null &&
          _freq != AwRepeatFreq.weekly) {
        _monthMode = _MonthMode.nthWeekday;
        _ordinal = rule.byWeekday.first.ordinal!;
        _ordinalWeekday = rule.byWeekday.first.day;
      }
      _advanced = _monthMode != _MonthMode.monthDay || _interval > 1;
    }

    _endType = rule?.end.type ?? 'never';
    _until = DateTime.tryParse(rule?.end.until ?? '');
    _count = rule?.end.count ?? 10;
    _intervalController.text = '$_interval';
    _countController.text = '$_count';
  }

  @override
  void dispose() {
    _intervalController.dispose();
    _countController.dispose();
    super.dispose();
  }

  AwRepeatEnd get _end => switch (_endType) {
    'until' when _until != null => AwRepeatEnd.until(awDayKey(_until!)),
    'count' => AwRepeatEnd.count(_count),
    _ => const AwRepeatEnd.never(),
  };

  AwRepeatRule get _rule {
    switch (_freq) {
      case AwRepeatFreq.daily:
        return AwRepeatRule(
          freq: AwRepeatFreq.daily,
          interval: _interval,
          end: _end,
        );
      case AwRepeatFreq.weekly:
        return AwRepeatRule(
          freq: AwRepeatFreq.weekly,
          interval: _interval,
          byWeekday: [
            for (final day in kAwWeekdays)
              if (_weekdays.contains(day)) AwWeekdayPick(day),
          ],
          end: _end,
        );
      case AwRepeatFreq.monthly:
      case AwRepeatFreq.yearly:
        switch (_monthMode) {
          case _MonthMode.monthDay:
            return AwRepeatRule(
              freq: _freq,
              interval: _interval,
              byMonthDay: [_lastDay ? -1 : _monthDay],
              end: _end,
            );
          case _MonthMode.nthWeekday:
            return AwRepeatRule(
              freq: _freq,
              interval: _interval,
              byWeekday: [AwWeekdayPick(_ordinalWeekday, ordinal: _ordinal)],
              end: _end,
            );
          case _MonthMode.afterDay:
            return awAfterDayRule(
              day: _afterDay,
              weekday: _afterWeekday,
              end: _end,
              interval: _interval,
            );
        }
    }
  }

  List<String> get _preview {
    try {
      return awExpandOccurrences(
        _rule,
        anchor: awDayKey(widget.anchor),
        max: 5,
      );
    } on ArgumentError {
      return const [];
    }
  }

  void _applyPreset(String preset) => setState(() {
    _advanced = false;
    _interval = 1;
    _intervalController.text = '1';
    switch (preset) {
      case 'daily':
        _freq = AwRepeatFreq.daily;
      case 'weekly':
        _freq = AwRepeatFreq.weekly;
        _weekdays = {kAwWeekdays[widget.anchor.weekday - 1]};
      case 'weekdays':
        _freq = AwRepeatFreq.weekly;
        _weekdays = {'MO', 'TU', 'WE', 'TH', 'FR'};
      case 'monthly':
        _freq = AwRepeatFreq.monthly;
        _monthMode = _MonthMode.monthDay;
        _lastDay = false;
        _monthDay = widget.anchor.day;
      case 'yearly':
        _freq = AwRepeatFreq.yearly;
        _monthMode = _MonthMode.monthDay;
        _lastDay = false;
        _monthDay = widget.anchor.day;
    }
  });

  String get _activePreset {
    if (_interval != 1) return '';
    return switch (_freq) {
      AwRepeatFreq.daily => 'daily',
      AwRepeatFreq.weekly =>
        _weekdays.length == 5 &&
                _weekdays.containsAll(const {'MO', 'TU', 'WE', 'TH', 'FR'})
            ? 'weekdays'
            : 'weekly',
      AwRepeatFreq.monthly =>
        _monthMode == _MonthMode.monthDay && !_lastDay ? 'monthly' : '',
      AwRepeatFreq.yearly =>
        _monthMode == _MonthMode.monthDay && !_lastDay ? 'yearly' : '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = ref.watch(dateFormatProvider);
    final locale = AwI18n.instance.locale.languageCode;
    final valid = awValidateRepeatRule(_rule) == null && _preview.isNotEmpty;

    return AlertDialog(
      key: const Key('repeat-dialog'),
      title: Text('repeat.dialogTitle'.tr()),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('repeat.presets'.tr()),
            Wrap(
              spacing: AwSpace.x2,
              children: [
                for (final preset in const [
                  'daily',
                  'weekly',
                  'weekdays',
                  'monthly',
                  'yearly',
                ])
                  ChoiceChip(
                    key: Key('repeat-preset-$preset'),
                    label: Text('repeat.preset.$preset'.tr()),
                    selected: _activePreset == preset,
                    onSelected: (_) => _applyPreset(preset),
                  ),
              ],
            ),
            const SizedBox(height: AwSpace.x2),
            // R4: the preview sits ABOVE the advanced disclosure, so the answer
            // is on screen no matter how deep the rule goes.
            _previewCard(dateFormat, locale),
            const SizedBox(height: AwSpace.x2),
            _sentence(dateFormat, locale),
            ExpansionTile(
              key: const Key('repeat-advanced'),
              title: Text('repeat.advanced'.tr()),
              initiallyExpanded: _advanced,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: AwSpace.x2),
              onExpansionChanged: (open) => setState(() => _advanced = open),
              children: [_intervalField(), ..._freqFields(), _endFields()],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('repeat-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const Key('repeat-save'),
          onPressed: valid ? () => Navigator.of(context).pop(_rule) : null,
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AwSpace.x2),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );

  Widget _sentence(String dateFormat, String locale) => Text(
    awRepeatSentence(_rule, dateFormat: dateFormat, locale: locale),
    key: const Key('repeat-sentence'),
    style: Theme.of(context).textTheme.bodyMedium,
  );

  Widget _previewCard(String dateFormat, String locale) {
    final days = _preview;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'repeat.next5'.tr(),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: AwSpace.x1),
            for (final day in days)
              Text(
                awFormatDate(
                  DateTime.parse(day),
                  format: dateFormat,
                  locale: locale,
                ),
                key: Key('repeat-preview-$day'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            if (days.isEmpty)
              Text(
                'state.empty'.tr(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Widget _intervalField() => Padding(
    padding: const EdgeInsets.only(bottom: AwSpace.x3),
    child: TextField(
      key: const Key('repeat-interval'),
      controller: _intervalController,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: 'repeat.intervalLabel'.tr()),
      onChanged: (value) {
        final parsed = int.tryParse(value);
        if (parsed != null && parsed >= 1 && parsed <= 366) {
          setState(() => _interval = parsed);
        }
      },
    ),
  );

  List<Widget> _freqFields() {
    switch (_freq) {
      case AwRepeatFreq.daily:
        return const [];
      case AwRepeatFreq.weekly:
        return [
          Wrap(
            spacing: AwSpace.x2,
            children: [
              for (final day in kAwWeekdays)
                FilterChip(
                  key: Key('repeat-weekday-$day'),
                  label: Text('repeat.weekday.${day.toLowerCase()}'.tr()),
                  selected: _weekdays.contains(day),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _weekdays.add(day);
                    } else if (_weekdays.length > 1) {
                      _weekdays.remove(day);
                    }
                  }),
                ),
            ],
          ),
        ];
      case AwRepeatFreq.monthly:
      case AwRepeatFreq.yearly:
        return [
          SegmentedButton<_MonthMode>(
            key: const Key('repeat-month-mode'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: _MonthMode.monthDay,
                label: Text('repeat.mode.monthDay'.tr()),
              ),
              ButtonSegment(
                value: _MonthMode.nthWeekday,
                label: Text('repeat.mode.nthWeekday'.tr()),
              ),
              ButtonSegment(
                value: _MonthMode.afterDay,
                label: Text('repeat.mode.afterDay'.tr()),
              ),
            ],
            selected: {_monthMode},
            onSelectionChanged: (s) => setState(() => _monthMode = s.first),
          ),
          const SizedBox(height: AwSpace.x3),
          ..._monthModeFields(),
        ];
    }
  }

  List<Widget> _monthModeFields() {
    switch (_monthMode) {
      case _MonthMode.monthDay:
        return [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const Key('repeat-month-day'),
                  initialValue: _lastDay ? -1 : _monthDay,
                  decoration: InputDecoration(
                    labelText: 'repeat.monthDayLabel'.tr(),
                  ),
                  items: [
                    for (var day = 1; day <= 31; day += 1)
                      DropdownMenuItem(value: day, child: Text('$day')),
                    DropdownMenuItem(
                      value: -1,
                      child: Text('repeat.on.lastDay'.tr()),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _lastDay = value == -1;
                    if (!_lastDay) _monthDay = value ?? _monthDay;
                  }),
                ),
              ),
            ],
          ),
          if (!_lastDay && _monthDay > 28)
            Padding(
              padding: const EdgeInsets.only(top: AwSpace.x2),
              child: Text(
                'repeat.clampHint'.tr(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ];
      case _MonthMode.nthWeekday:
        return [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const Key('repeat-ordinal'),
                  initialValue: _ordinal,
                  decoration: InputDecoration(
                    labelText: 'repeat.ordinalLabel'.tr(),
                  ),
                  items: [
                    for (var n = 1; n <= 5; n += 1)
                      DropdownMenuItem(
                        value: n,
                        child: Text('repeat.ordinal.$n'.tr()),
                      ),
                    DropdownMenuItem(
                      value: -1,
                      child: Text('repeat.on.lastDay'.tr()),
                    ),
                  ],
                  onChanged: (v) => setState(() => _ordinal = v ?? _ordinal),
                ),
              ),
              const SizedBox(width: AwSpace.x3),
              Expanded(
                child: _weekdayDropdown(
                  'repeat-ordinal-weekday',
                  _ordinalWeekday,
                  (v) => _ordinalWeekday = v,
                ),
              ),
            ],
          ),
        ];
      case _MonthMode.afterDay:
        return [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: const Key('repeat-after-day'),
                  initialValue: _afterDay,
                  decoration: InputDecoration(
                    labelText: 'repeat.monthDayLabel'.tr(),
                  ),
                  items: [
                    for (var day = 1; day <= 28; day += 1)
                      DropdownMenuItem(value: day, child: Text('$day')),
                  ],
                  onChanged: (v) => setState(() => _afterDay = v ?? _afterDay),
                ),
              ),
              const SizedBox(width: AwSpace.x3),
              Expanded(
                child: _weekdayDropdown(
                  'repeat-after-weekday',
                  _afterWeekday,
                  (v) => _afterWeekday = v,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: AwSpace.x2),
            child: Text(
              'repeat.afterDayHint'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ];
    }
  }

  Widget _weekdayDropdown(
    String key,
    String value,
    void Function(String) onPicked,
  ) => DropdownButtonFormField<String>(
    key: Key(key),
    initialValue: value,
    decoration: InputDecoration(labelText: 'repeat.weekdayLabel'.tr()),
    items: [
      for (final day in kAwWeekdays)
        DropdownMenuItem(
          value: day,
          child: Text('repeat.weekday.${day.toLowerCase()}'.tr()),
        ),
    ],
    onChanged: (picked) => setState(() => onPicked(picked ?? value)),
  );

  Widget _endFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: AwSpace.x3),
      _label('repeat.endLabel'.tr()),
      SegmentedButton<String>(
        key: const Key('repeat-end-mode'),
        showSelectedIcon: false,
        segments: [
          ButtonSegment(value: 'never', label: Text('repeat.end.never'.tr())),
          ButtonSegment(value: 'until', label: Text('repeat.end.until'.tr())),
          ButtonSegment(value: 'count', label: Text('repeat.end.count'.tr())),
        ],
        selected: {_endType},
        onSelectionChanged: (s) => setState(() => _endType = s.first),
      ),
      if (_endType == 'until')
        Padding(
          padding: const EdgeInsets.only(top: AwSpace.x3),
          child: OutlinedButton(
            key: const Key('repeat-until'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _until ?? widget.anchor,
                firstDate: widget.anchor,
                lastDate: DateTime(widget.anchor.year + 10),
              );
              if (picked != null) setState(() => _until = picked);
            },
            child: Text(
              _until == null
                  ? 'repeat.endUntilLabel'.tr()
                  : awFormatDate(
                      _until!,
                      format: ref.read(dateFormatProvider),
                      locale: AwI18n.instance.locale.languageCode,
                    ),
            ),
          ),
        ),
      if (_endType == 'count')
        Padding(
          padding: const EdgeInsets.only(top: AwSpace.x3),
          child: TextField(
            key: const Key('repeat-count'),
            controller: _countController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'repeat.endCountLabel'.tr()),
            onChanged: (value) {
              final parsed = int.tryParse(value);
              if (parsed != null && parsed >= 1 && parsed <= 1000) {
                setState(() => _count = parsed);
              }
            },
          ),
        ),
    ],
  );
}
