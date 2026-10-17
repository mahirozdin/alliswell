import 'package:flutter/material.dart';

import '../../../core/date_format.dart';
import '../../../core/fold.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../data/rules_models.dart';

/// EE-308 — the pieces both rule editors and the rules list share.
///
/// ── A REMOVED REFERENCE IS SAID, NEVER SHOWN AS AN ID ──
///
/// A rule may name a service that was archived, a person who left or a tag
/// that was deleted. The picker then reads "Unavailable (removed)" in the
/// error colour — a raw ULID would read as a bug, and an empty field would
/// read as "any", which is the opposite of what the rule does.

/// One choosable value.
@immutable
class EeRuleChoice {
  const EeRuleChoice(this.value, this.label, {this.note});

  final String? value;
  final String label;

  /// A second line, e.g. "(paused)" on a webhook.
  final String? note;
}

/// The label of [id] in [list], or the "removed" sentence when it is gone.
({String label, bool missing}) ruleOptionLabel(
  List<EeNamedOption> list,
  String? id,
) {
  if (id == null) return (label: '', missing: false);
  final name = EeRuleOptions.nameIn(list, id);
  return name == null
      ? (label: 'ee.rules.removed'.tr(), missing: true)
      : (label: name, missing: false);
}

String triggerLabel(String trigger) => 'ee.rules.triggerName.$trigger'.tr();
String actionLabel(String action) => 'ee.rules.actionName.$action'.tr();
String strategyLabel(String s) => 'ee.rules.strategyName.$s'.tr();
String conditionLabel(String c) => 'ee.rules.conditionName.$c'.tr();
String sourceLabel(String s) => 'ee.rules.sourceName.$s'.tr();
String priorityLabel(String p) => 'ee.tickets.priority.$p'.tr();

/// What the action does, in a few words: "Assign: Ayşe", "Set priority: Urgent".
String automationActionSummary(EeAutomationRule rule, EeRuleOptions? o) {
  final head = actionLabel(rule.action);
  String? detail;
  switch (rule.action) {
    case 'assign':
      detail = rule.actionAssignStrategy == 'user'
          ? (o == null
                ? null
                : ruleOptionLabel(o.members, rule.actionUserId).label)
          : strategyLabel(rule.actionAssignStrategy);
    case 'set_priority':
      detail = rule.actionPriority == null
          ? null
          : priorityLabel(rule.actionPriority!);
    case 'add_tag':
      detail = o == null
          ? null
          : ruleOptionLabel(o.tags, rule.actionTagId).label;
    case 'call_webhook':
      detail = o == null
          ? null
          : ruleOptionLabel(o.webhooks, rule.actionWebhookId).label;
    case 'send_email':
      detail = rule.actionEmailTo;
    case 'open_ticket' || 'open_task':
      detail = rule.targetServiceId == null || o == null
          ? null
          : ruleOptionLabel(o.services, rule.targetServiceId).label;
  }
  return detail == null || detail.isEmpty ? head : '$head: $detail';
}

/// "Request created · Assign: Ayşe · Conditions: 2".
String automationSentence(EeAutomationRule rule, EeRuleOptions? o) {
  final conditions = rule.conditions.values.where((v) => v != null).length;
  return [
    triggerLabel(rule.trigger),
    automationActionSummary(rule, o),
    if (conditions > 0)
      'ee.rules.conditionCount'.tr(args: {'n': '$conditions'}),
  ].join(' · ');
}

/// "kablo, priz, arıza… » Elektrik arızası, Bakım".
String routingSentence(EeClassificationRule rule, EeRuleOptions? o) {
  final when = <String>[
    if (rule.condSource != null) sourceLabel(rule.condSource!),
    if (rule.condServiceId != null && o != null)
      ruleOptionLabel(o.services, rule.condServiceId).label,
    if (rule.condKeywords.isNotEmpty)
      rule.condKeywords.length > 3
          ? '${rule.condKeywords.take(3).join(', ')}…'
          : rule.condKeywords.join(', '),
    if (rule.condFrom != null) rule.condFrom!,
  ];
  final then = <String>[
    if (rule.actionServiceId != null && o != null)
      ruleOptionLabel(o.services, rule.actionServiceId).label,
    if (rule.actionUnitId != null && o != null)
      ruleOptionLabel(o.units, rule.actionUnitId).label,
    if (rule.actionPriority != null) priorityLabel(rule.actionPriority!),
    if (rule.actionTagId != null && o != null)
      '#${ruleOptionLabel(o.tags, rule.actionTagId).label}',
  ];
  final left = when.isEmpty ? 'ee.rules.any'.tr() : when.join(' · ');
  return then.isEmpty ? left : '$left » ${then.join(', ')}';
}

/// The state of a rule in words, each with an icon — never colour alone.
class EeRuleStatusLine extends StatelessWidget {
  const EeRuleStatusLine({
    super.key,
    required this.enabled,
    this.pausedReason,
    this.paused = false,
    this.lastFiredAt,
    this.failure,
    this.showActivity = true,
    this.now,
  });

  final bool enabled;
  final bool paused;
  final String? pausedReason;
  final DateTime? lastFiredAt;

  /// The latest failure, only when newer than the latest success.
  final String? failure;
  final bool showActivity;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.awTokens;
    final small = theme.textTheme.bodySmall;
    final muted = small?.copyWith(color: scheme.onSurfaceVariant);
    Widget item(IconData icon, Color color, String text, {TextStyle? style}) =>
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: AwSpace.x1),
            Flexible(child: Text(text, style: style ?? muted)),
          ],
        );
    final at = now ?? DateTime.now();
    return Wrap(
      spacing: AwSpace.x3,
      runSpacing: AwSpace.x1,
      children: [
        if (!enabled)
          item(
            Icons.power_settings_new,
            scheme.onSurfaceVariant,
            'ee.rules.off'.tr(),
          ),
        if (paused)
          // The warning colour is a MARK (3.46:1 on light, DESIGN §7): the
          // icon carries it, the words stay in body ink.
          item(
            Icons.pause_circle_outline,
            tokens.warning,
            (pausedReason ?? '').isEmpty
                ? 'ee.rules.paused'.tr()
                : 'ee.rules.pausedReason'.tr(args: {'reason': pausedReason!}),
            style: small?.copyWith(color: scheme.onSurface),
          ),
        if (showActivity)
          if (failure != null)
            item(
              Icons.error_outline,
              scheme.error,
              'ee.rules.lastFailed'.tr(args: {'reason': failure!}),
              style: small?.copyWith(color: scheme.error),
            )
          else if (lastFiredAt != null)
            item(
              Icons.history,
              scheme.onSurfaceVariant,
              'ee.rules.lastRan'.tr(
                args: {'ago': awRelativePast(lastFiredAt!, at)},
              ),
            )
          else
            item(
              Icons.history_toggle_off,
              scheme.onSurfaceVariant,
              'ee.rules.neverRan'.tr(),
            ),
      ],
    );
  }
}

/// A labelled field that opens a list — the editors' one picker.
///
/// A value the list no longer holds is drawn as "Unavailable (removed)" in
/// the error colour, and the field stays choosable so the admin can fix it.
class EeRulePickerField extends StatelessWidget {
  const EeRulePickerField({
    super.key,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.errorText,
    this.helperText,
    this.enabled = true,
    this.emptyLabel,
    this.searchable = false,
  });

  final String label;
  final String? value;
  final List<EeRuleChoice> choices;
  final ValueChanged<String?> onChanged;
  final String? errorText;
  final String? helperText;
  final bool enabled;

  /// What an unset value reads as ("Any", "Where the signal came from").
  final String? emptyLabel;

  /// A long list (people) opens a search dialog instead of a plain list.
  final bool searchable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    EeRuleChoice? current;
    for (final c in choices) {
      if (c.value == value) current = c;
    }
    final missing = value != null && current == null;
    final text = missing
        ? 'ee.rules.removed'.tr()
        : current?.label ?? emptyLabel ?? '';
    return InkWell(
      onTap: !enabled
          ? null
          : () async {
              final picked = await showDialog<_Picked>(
                context: context,
                builder: (_) => _ChoiceDialog(
                  title: label,
                  choices: choices,
                  current: value,
                  searchable: searchable,
                ),
              );
              if (picked != null) onChanged(picked.value);
            },
      borderRadius: const BorderRadius.all(Radius.circular(AwRadius.s)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: InputDecorator(
          isEmpty: text.isEmpty,
          decoration: InputDecoration(
            labelText: label,
            errorText: errorText,
            helperText: helperText,
            helperMaxLines: 3,
            errorMaxLines: 3,
            enabled: enabled,
            suffixIcon: const Icon(Icons.arrow_drop_down),
          ),
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: missing
                  ? scheme.error
                  : enabled
                  ? null
                  : scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

class _Picked {
  const _Picked(this.value);
  final String? value;
}

class _ChoiceDialog extends StatefulWidget {
  const _ChoiceDialog({
    required this.title,
    required this.choices,
    required this.current,
    required this.searchable,
  });

  final String title;
  final List<EeRuleChoice> choices;
  final String? current;
  final bool searchable;

  @override
  State<_ChoiceDialog> createState() => _ChoiceDialogState();
}

class _ChoiceDialogState extends State<_ChoiceDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final folded = foldSearchText(_query);
    final shown = folded.isEmpty
        ? widget.choices
        : widget.choices
              .where((c) => foldSearchText(c.label).contains(folded))
              .toList();
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(0, AwSpace.x3, 0, 0),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AwSpace.x4),
                child: TextField(
                  key: const Key('rule-picker-search'),
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'ee.rules.memberSearch'.tr(),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            Flexible(
              child: shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AwSpace.x4),
                      child: Text('ee.rules.noMatches'.tr()),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final c in shown)
                          ListTile(
                            key: Key('rule-choice-${c.value ?? 'none'}'),
                            minTileHeight: 48,
                            title: Text(c.label),
                            subtitle: c.note == null ? null : Text(c.note!),
                            trailing: c.value == widget.current
                                ? const Icon(Icons.check)
                                : null,
                            selected: c.value == widget.current,
                            onTap: () =>
                                Navigator.of(context).pop(_Picked(c.value)),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
      ],
    );
  }
}

/// A titled card section of an editor.
class EeRuleSection extends StatelessWidget {
  const EeRuleSection({
    super.key,
    required this.title,
    required this.children,
    this.help,
    this.errorText,
  });

  final String title;
  final String? help;
  final String? errorText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: kRuleCardPadding,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AwSpace.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              if (help != null) ...[
                const SizedBox(height: AwSpace.x1),
                Text(
                  help!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AwSpace.x3),
              for (final (i, child) in children.indexed) ...[
                if (i > 0) const SizedBox(height: AwSpace.x3),
                child,
              ],
              if (errorText != null) ...[
                const SizedBox(height: AwSpace.x3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: AwSpace.x2),
                    Expanded(
                      child: Text(
                        errorText!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

const EdgeInsets kRuleCardPadding = EdgeInsets.symmetric(vertical: 3);
