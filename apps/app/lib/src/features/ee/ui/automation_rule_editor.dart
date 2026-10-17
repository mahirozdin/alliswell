import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/route_leading.dart';
import '../../../widgets/status_views.dart';
import '../../../widgets/swipe_actions.dart' show awConfirmDelete;
import '../data/rules_models.dart';
import '../rules_providers.dart';
import 'rules_widgets.dart';

/// The order the trigger menu lists them in — the request's life first, then
/// the promise, then the monitors. Only what the server OFFERS is shown.
const kTriggerOrder = [
  'ticket_created',
  'ticket_updated',
  'ticket_commented',
  'ticket_idle',
  'sla_breached',
  'health_down',
  'health_recovered',
];

const _kConditionOrder = ['service', 'priority', 'source', 'unit'];

/// Server codes → the field the editor shows them under.
const _kFieldOf = {
  'SLA_RULE_NAME_TAKEN': 'name',
  'SLA_RULE_NEEDS_ASSIGNEE': 'member',
  'SLA_RULE_STRATEGY': 'strategy',
  'SLA_RULE_NEEDS_PRIORITY': 'actionPriority',
  'SLA_RULE_NEEDS_WEBHOOK': 'webhook',
  'SLA_RULE_NEEDS_ADDRESS': 'email',
  'SLA_RULE_NEEDS_TAG': 'tag',
  'SLA_RULE_TAG_UNKNOWN': 'tag',
  'SLA_RULE_NEEDS_IDLE_DAYS': 'idleDays',
  'SLA_RULE_CONDITION_TRIGGER': 'if',
  'SLA_RULE_ACTION_TRIGGER': 'action',
  'SLA_RULE_ACTION': 'action',
  'SLA_RULE_TRIGGER': 'trigger',
  'SLA_RULE_TRIGGER_NOT_RAISED': 'trigger',
};

final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// EE-308 — one automation rule, as a condition → action form.
///
/// ── IT OFFERS EXACTLY WHAT THE ENGINE CAN DO ──
///
/// The trigger list, each trigger's conditions and its actions come from the
/// server (`GET /team/sla/rules/options`, from `RULE_VOCABULARY` in
/// automation.js), never from a copy here. The only operator is "is" —
/// equality, all ANDed, nothing means any — because that is the engine.
/// Changing the trigger REMOVES what the new one cannot use and says so: a
/// condition the engine can never match would otherwise be saved silently.
///
/// ── THE TEST RUNS THE DRAFT, NOT THE STORED RULE ──
///
/// "Test on a request" sends what is on the screen (and the rule's id, so its
/// pause and its ceiling count). The server builds the context the way the
/// engine does and previews the action without doing it.
class EeAutomationRuleEditor extends ConsumerStatefulWidget {
  const EeAutomationRuleEditor({super.key, this.ruleId});

  /// Null for a new rule.
  final String? ruleId;

  @override
  ConsumerState<EeAutomationRuleEditor> createState() =>
      _EeAutomationRuleEditorState();
}

class _EeAutomationRuleEditorState
    extends ConsumerState<EeAutomationRuleEditor> {
  bool _ready = false;
  EeAutomationRule? _before;

  final _name = TextEditingController();
  final _idleDays = TextEditingController();
  final _emailTo = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _dailyCap = TextEditingController();
  final _testNumber = TextEditingController();
  TextEditingController? _templateTarget;

  bool _enabled = true;
  String? _trigger;
  String? _action;
  String _strategy = 'user';
  String? _userId;
  String? _actionPriority;
  String? _webhookId;
  String? _tagId;
  String? _targetServiceId;
  String _openPriority = 'high';

  /// The conditions on screen, in the order they were added. A key with a
  /// null value was added and not yet chosen.
  final Map<String, String?> _conds = {};

  String? _removedNote;
  Map<String, String> _errors = {};
  String? _banner;
  bool _busy = false;

  EeRuleTestResult? _test;
  String? _testError;
  String? _testNumberError;
  bool _testing = false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _idleDays,
      _emailTo,
      _subject,
      _body,
      _dailyCap,
      _testNumber,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _init(EeAutomationRule? rule) {
    _ready = true;
    _before = rule;
    if (rule == null) {
      _trigger = 'ticket_created';
      _dailyCap.text = '0';
      return;
    }
    _name.text = rule.name;
    _enabled = rule.enabled;
    _trigger = rule.trigger;
    _idleDays.text = rule.idleDays?.toString() ?? '';
    for (final key in _kConditionOrder) {
      final v = rule.conditions[key];
      if (v != null) _conds[key] = v;
    }
    _action = rule.action;
    _strategy = rule.actionAssignStrategy;
    _userId = rule.actionUserId;
    _actionPriority = rule.actionPriority;
    _webhookId = rule.actionWebhookId;
    _emailTo.text = rule.actionEmailTo ?? '';
    _tagId = rule.actionTagId;
    _targetServiceId = rule.targetServiceId;
    _openPriority = rule.priority;
    _subject.text = rule.subjectTemplate;
    _body.text = rule.bodyTemplate ?? '';
    _dailyCap.text = '${rule.dailyCap}';
  }

  EeTriggerSpec? _spec(EeRuleOptions o) =>
      _trigger == null ? null : o.trigger(_trigger!);

  void _setTrigger(EeRuleOptions o, String trigger) {
    final spec = o.trigger(trigger);
    if (spec == null) return;
    setState(() {
      _trigger = trigger;
      final dropped = [
        for (final key in _conds.keys)
          if (!spec.conditions.contains(key)) key,
      ];
      for (final key in dropped) {
        _conds.remove(key);
      }
      final actionDropped = _action != null && !spec.actions.contains(_action);
      if (actionDropped) _action = null;
      _removedNote = [
        if (dropped.isNotEmpty)
          'ee.rules.conditionsRemoved'.tr(
            args: {'list': dropped.map(conditionLabel).join(', ')},
          ),
        if (actionDropped) 'ee.rules.actionRemoved'.tr(),
      ].join(' ');
      if (_removedNote!.isEmpty) _removedNote = null;
      _errors = {};
      _test = null;
    });
  }

  bool get _showsTemplates =>
      _action == 'open_ticket' ||
      _action == 'open_task' ||
      _action == 'send_email';

  /// What would be saved, built from the screen.
  EeAutomationRule _draft() {
    final name = _name.text.trim();
    final subject = _subject.text.trim();
    final body = _body.text.trim();
    final email = _emailTo.text.trim();
    return EeAutomationRule(
      id: _before?.id ?? '',
      name: name,
      trigger: _trigger ?? '',
      action: _action ?? '',
      serviceId: _conds['service'],
      condPriority: _conds['priority'],
      condSource: _conds['source'],
      condUnitId: _conds['unit'],
      enabled: _enabled,
      targetServiceId: _targetServiceId,
      priority: _openPriority,
      // The column is required; a rule that opens nothing still has one, and
      // its name is what the server would have written.
      subjectTemplate: subject.isNotEmpty
          ? subject
          : (_before?.subjectTemplate.isNotEmpty ?? false)
          ? _before!.subjectTemplate
          : (name.isEmpty ? '-' : name),
      bodyTemplate: body.isEmpty ? null : body,
      actionUserId: _userId,
      actionAssignStrategy: _strategy,
      actionPriority: _actionPriority,
      actionWebhookId: _webhookId,
      actionEmailTo: email.isEmpty ? null : email,
      actionTagId: _tagId,
      idleDays: int.tryParse(_idleDays.text.trim()),
      dailyCap: int.tryParse(_dailyCap.text.trim()) ?? 0,
      pausedAt: _before?.pausedAt,
      pauseReason: _before?.pauseReason,
    );
  }

  /// The server's required-field rules, said before anything is sent.
  Map<String, String> _validate(EeRuleOptions o) {
    final e = <String, String>{};
    final name = _name.text.trim();
    if (name.isEmpty) e['name'] = 'ee.rules.nameRequired'.tr();
    if (name.length > 160) e['name'] = 'ee.rules.nameTooLong'.tr();
    final spec = _spec(o);
    if (spec == null) {
      e['trigger'] = 'ee.rules.notRaised'.tr();
    } else {
      if (spec.needsIdleDays) {
        final d = int.tryParse(_idleDays.text.trim());
        if (d == null || d < 1 || d > 365) {
          e['idleDays'] = 'ee.rules.idleDaysInvalid'.tr();
        }
      }
      if (_conds.values.any((v) => v == null)) {
        e['if'] = 'ee.rules.chooseValue'.tr();
      }
    }
    switch (_action) {
      case null:
        e['action'] = 'ee.rules.chooseValue'.tr();
      case 'assign':
        if (_strategy == 'user' && _userId == null) {
          e['member'] = 'ee.rules.memberRequired'.tr();
        }
      case 'set_priority':
        if (_actionPriority == null) {
          e['actionPriority'] = 'ee.rules.priorityRequired'.tr();
        }
      case 'call_webhook':
        if (_webhookId == null) e['webhook'] = 'ee.rules.webhookRequired'.tr();
      case 'add_tag':
        if (_tagId == null) e['tag'] = 'ee.rules.tagRequired'.tr();
      case 'send_email':
        if (!_email.hasMatch(_emailTo.text.trim())) {
          e['email'] = 'ee.rules.emailInvalid'.tr();
        }
        if (_subject.text.trim().isEmpty) {
          e['subject'] = 'ee.rules.subjectRequired'.tr();
        }
      case 'open_ticket' || 'open_task':
        if (_subject.text.trim().isEmpty) {
          e['subject'] = 'ee.rules.subjectRequired'.tr();
        }
    }
    final cap = int.tryParse(_dailyCap.text.trim());
    if (cap == null || cap < 0 || cap > 1000) {
      e['dailyCap'] = 'ee.rules.dailyCapInvalid'.tr();
    }
    return e;
  }

  Future<void> _save(EeRuleOptions o) async {
    final errors = _validate(o);
    setState(() {
      _errors = errors;
      _banner = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(eeAutomationRulesProvider.notifier)
          .save(_before, _draft());
      if (mounted) await Navigator.of(context).maybePop();
    } on ApiException catch (e) {
      final field = _kFieldOf[e.code];
      setState(() {
        if (field != null) {
          _errors = {field: localizedError(e)};
        } else {
          _banner = localizedError(e);
        }
      });
    } catch (e) {
      setState(() => _banner = localizedError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runTest(EeRuleOptions o) async {
    final number = int.tryParse(_testNumber.text.trim().replaceAll('#', ''));
    if (number == null || number < 1) {
      setState(() => _testNumberError = 'ee.rules.testNumberInvalid'.tr());
      return;
    }
    if (_action == null) {
      setState(() => _errors = {'action': 'ee.rules.chooseValue'.tr()});
      return;
    }
    setState(() {
      _testing = true;
      _testNumberError = null;
      _testError = null;
    });
    try {
      final result = await ref
          .read(eeRulesApiProvider)
          .testAutomation(
            id: _before?.id,
            draft: _draft().toBody(),
            ticketNumber: number,
          );
      if (mounted) setState(() => _test = result);
    } on ApiException catch (e) {
      setState(() {
        _test = null;
        if (e.code == 'SLA_RULE_TEST_TICKET_NOT_FOUND') {
          _testNumberError = localizedError(e);
        } else {
          _testError = localizedError(e);
        }
      });
    } catch (e) {
      setState(() => _testError = localizedError(e));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _insertKey(String key) {
    final target = _templateTarget ?? _subject;
    final token = '{{$key}}';
    final sel = target.selection;
    final text = target.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    target.value = TextEditingValue(
      text: text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    setState(() {});
  }

  Future<void> _duplicate() async {
    final id = _before?.id;
    if (id == null) return;
    try {
      await ref.read(eeAutomationRulesProvider.notifier).duplicate(id);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('ee.rules.duplicated'.tr())));
      await Navigator.of(context).maybePop();
    } catch (e) {
      setState(() => _banner = localizedError(e));
    }
  }

  Future<void> _delete() async {
    final rule = _before;
    if (rule == null) return;
    final ok = await awConfirmDelete(
      context,
      title: 'ee.rules.deleteTitle'.tr(),
      body: 'ee.rules.deleteBody'.tr(args: {'name': rule.name}),
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(eeAutomationRulesProvider.notifier).delete(rule.id);
      if (mounted) await Navigator.of(context).maybePop();
    } catch (e) {
      setState(() => _banner = localizedError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(eeAutomationRulesProvider);
    final options = ref.watch(eeRuleOptionsProvider);
    final o = options.value;
    final list = rules.value;
    final loading =
        (options.isLoading && o == null) || (rules.isLoading && list == null);

    Widget body;
    if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (options.hasError || rules.hasError) {
      body = AwErrorState(
        message: localizedError(options.error ?? rules.error),
        onRetry: () {
          ref.invalidate(eeRuleOptionsProvider);
          ref.invalidate(eeAutomationRulesProvider);
        },
      );
    } else if (o == null || list == null) {
      body = AwEmptyState(
        icon: Icons.rule_outlined,
        title: 'ee.rules.unavailable'.tr(),
        message: 'ee.rules.unavailableBody'.tr(),
      );
    } else {
      if (!_ready) {
        EeAutomationRule? rule;
        for (final r in list) {
          if (r.id == widget.ruleId) rule = r;
        }
        if (widget.ruleId != null && rule == null) {
          body = AwEmptyState(
            icon: Icons.rule_outlined,
            title: 'error.notFound'.tr(),
            message: 'ee.rules.unavailableBody'.tr(),
          );
          return _scaffold(context, null, body);
        }
        _init(rule);
      }
      body = _form(context, o);
    }
    return _scaffold(context, o, body);
  }

  Widget _scaffold(BuildContext context, EeRuleOptions? o, Widget body) {
    final canSave = o != null && _ready && !_busy;
    return Scaffold(
      appBar: AppBar(
        leading: awRouteLeading(context),
        title: Text(
          widget.ruleId == null
              ? 'ee.rules.newAutomation'.tr()
              : 'ee.rules.editAutomation'.tr(),
        ),
        actions: [
          TextButton(
            key: const Key('rule-save-top'),
            onPressed: canSave ? () => _save(o) : null,
            child: Text('ee.rules.save'.tr()),
          ),
          if (_before != null)
            PopupMenuButton<String>(
              key: const Key('rule-editor-menu'),
              tooltip: 'ee.rules.more'.tr(),
              onSelected: (v) => v == 'duplicate' ? _duplicate() : _delete(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: const Key('rule-editor-duplicate'),
                  value: 'duplicate',
                  child: Text('ee.rules.duplicate'.tr()),
                ),
                PopupMenuItem(
                  key: const Key('rule-editor-delete'),
                  value: 'delete',
                  child: Text('ee.rules.delete'.tr()),
                ),
              ],
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _form(BuildContext context, EeRuleOptions o) {
    final theme = Theme.of(context);
    final spec = _spec(o);
    final offered = [
      for (final id in kTriggerOrder)
        if (o.trigger(id) != null) id,
    ];
    final triggerChoices = [
      for (final id in offered) EeRuleChoice(id, triggerLabel(id)),
    ];
    final services = [for (final s in o.services) EeRuleChoice(s.id, s.name)];
    final priorities = [
      for (final p in o.priorities) EeRuleChoice(p, priorityLabel(p)),
    ];
    return ListView(
      key: const Key('rule-editor-list'),
      padding: awListPadding(context),
      children: [
        if (_banner != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AwSpace.x2),
            child: AwInlineError(
              key: const Key('rule-editor-banner'),
              message: _banner!,
            ),
          ),
        // 1. Name and switch.
        EeRuleSection(
          title: 'ee.rules.name'.tr(),
          children: [
            TextField(
              key: const Key('rule-name'),
              controller: _name,
              maxLength: 160,
              decoration: InputDecoration(
                labelText: 'ee.rules.name'.tr(),
                errorText: _errors['name'],
                counterText: '',
              ),
            ),
            SwitchListTile(
              key: const Key('rule-enabled'),
              contentPadding: EdgeInsets.zero,
              title: Text('ee.rules.enabled'.tr()),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            if (_before?.paused ?? false)
              _Banner(
                key: const Key('rule-paused-banner'),
                icon: Icons.pause_circle_outline,
                iconColor: context.awTokens.warning,
                text: 'ee.rules.pausedBanner'.tr(
                  args: {'reason': _before!.pauseReason ?? ''},
                ),
              ),
          ],
        ),
        // 2. When.
        EeRuleSection(
          title: 'ee.rules.when'.tr(),
          children: [
            EeRulePickerField(
              key: const Key('rule-trigger'),
              label: 'ee.rules.trigger'.tr(),
              value: _trigger,
              choices: [
                ...triggerChoices,
                // A legacy rule on a trigger nobody raises keeps its label,
                // so the admin sees what it was before choosing another.
                if (_trigger != null && !offered.contains(_trigger))
                  EeRuleChoice(_trigger, triggerLabel(_trigger!)),
              ],
              errorText: _errors['trigger'],
              onChanged: (v) {
                if (v != null && offered.contains(v)) _setTrigger(o, v);
              },
            ),
            if (_trigger != null && spec == null)
              _Banner(
                key: const Key('rule-not-raised'),
                icon: Icons.info_outline,
                iconColor: context.awTokens.warning,
                text: 'ee.rules.notRaised'.tr(),
              ),
            if (spec?.needsIdleDays ?? false)
              TextField(
                key: const Key('rule-idle-days'),
                controller: _idleDays,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'ee.rules.idleDays'.tr(),
                  errorText: _errors['idleDays'],
                ),
              ),
          ],
        ),
        // 3. If.
        EeRuleSection(
          key: const Key('rule-if'),
          title: 'ee.rules.if'.tr(),
          help: (spec?.aboutRequest ?? true)
              ? 'ee.rules.conditionsHelp'.tr()
              : 'ee.rules.conditionsHelpSignal'.tr(),
          errorText: _errors['if'],
          children: [
            if (_removedNote != null)
              _Banner(
                key: const Key('rule-removed-note'),
                icon: Icons.info_outline,
                iconColor: theme.colorScheme.onSurfaceVariant,
                text: _removedNote!,
              ),
            if (_conds.isEmpty)
              Text(
                'ee.rules.noConditions'.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            for (final key in _conds.keys.toList())
              _ConditionRow(
                key: Key('rule-cond-$key'),
                conditionKey: key,
                value: _conds[key],
                choices: switch (key) {
                  'service' => services,
                  'priority' => priorities,
                  'source' => [
                    for (final s in o.sources) EeRuleChoice(s, sourceLabel(s)),
                  ],
                  _ => [for (final u in o.units) EeRuleChoice(u.id, u.name)],
                },
                onChanged: (v) => setState(() {
                  _conds[key] = v;
                  _errors.remove('if');
                }),
                onRemove: () => setState(() => _conds.remove(key)),
              ),
            if (spec != null)
              Builder(
                builder: (context) {
                  final free = [
                    for (final c in _kConditionOrder)
                      if (spec.conditions.contains(c) && !_conds.containsKey(c))
                        c,
                  ];
                  if (free.isEmpty) return const SizedBox.shrink();
                  return Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: PopupMenuButton<String>(
                      key: const Key('rule-add-condition'),
                      tooltip: 'ee.rules.addCondition'.tr(),
                      onSelected: (c) => setState(() => _conds[c] = null),
                      itemBuilder: (_) => [
                        for (final c in free)
                          PopupMenuItem(
                            key: Key('rule-add-condition-$c'),
                            value: c,
                            child: Text(conditionLabel(c)),
                          ),
                      ],
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, color: theme.colorScheme.primary),
                            const SizedBox(width: AwSpace.x1),
                            Text(
                              'ee.rules.addCondition'.tr(),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        // 4. Then.
        EeRuleSection(
          title: 'ee.rules.then'.tr(),
          children: [
            EeRulePickerField(
              key: const Key('rule-action'),
              label: 'ee.rules.action'.tr(),
              value: _action,
              choices: [
                for (final a in spec?.actions ?? const <String>[])
                  EeRuleChoice(a, actionLabel(a)),
              ],
              errorText: _errors['action'],
              onChanged: (v) => setState(() {
                _action = v;
                _errors.remove('action');
                _removedNote = null;
              }),
            ),
            ..._actionFields(context, o, services, priorities),
            if (_showsTemplates && (spec?.templateKeys.isNotEmpty ?? false))
              Wrap(
                key: const Key('rule-template-keys'),
                spacing: AwSpace.x2,
                runSpacing: AwSpace.x1,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'ee.rules.insertField'.tr(),
                    style: theme.textTheme.bodySmall,
                  ),
                  for (final k in spec!.templateKeys)
                    ActionChip(
                      key: Key('rule-template-$k'),
                      label: Text('{{$k}}'),
                      onPressed: () => _insertKey(k),
                    ),
                ],
              ),
          ],
        ),
        // 5. Advanced.
        EeRuleSection(
          title: 'ee.rules.advanced'.tr(),
          children: [
            TextField(
              key: const Key('rule-daily-cap'),
              controller: _dailyCap,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'ee.rules.dailyCap'.tr(),
                helperText: 'ee.rules.dailyCapHelp'.tr(),
                helperMaxLines: 4,
                errorText: _errors['dailyCap'],
              ),
            ),
          ],
        ),
        // 6. Test.
        EeRuleSection(
          key: const Key('rule-test'),
          title: 'ee.rules.test'.tr(),
          help: (spec?.aboutRequest ?? true)
              ? 'ee.rules.testHelp'.tr()
              : 'ee.rules.testSignalOnly'.tr(),
          children: [
            if (spec?.aboutRequest ?? false) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('rule-test-number'),
                      controller: _testNumber,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'ee.rules.testNumber'.tr(),
                        prefixText: '#',
                        errorText: _testNumberError,
                        errorMaxLines: 3,
                      ),
                    ),
                  ),
                  const SizedBox(width: AwSpace.x3),
                  Padding(
                    padding: const EdgeInsets.only(top: AwSpace.x1),
                    child: FilledButton.tonal(
                      key: const Key('rule-test-run'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(64, 48),
                      ),
                      onPressed: _testing ? null : () => _runTest(o),
                      child: Text('ee.rules.testRun'.tr()),
                    ),
                  ),
                ],
              ),
              if (_testError != null) AwInlineError(message: _testError!),
              if (_test != null) _TestResult(result: _test!, options: o),
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AwSpace.x3),
          child: FilledButton(
            key: const Key('rule-save'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _ready && !_busy ? () => _save(o) : null,
            child: Text('ee.rules.save'.tr()),
          ),
        ),
      ],
    );
  }

  List<Widget> _actionFields(
    BuildContext context,
    EeRuleOptions o,
    List<EeRuleChoice> services,
    List<EeRuleChoice> priorities,
  ) {
    Widget subjectAndBody() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('rule-subject'),
          controller: _subject,
          maxLength: 200,
          onTap: () => _templateTarget = _subject,
          decoration: InputDecoration(
            labelText: 'ee.rules.subject'.tr(),
            helperText: 'ee.rules.subjectHelp'.tr(),
            errorText: _errors['subject'],
            counterText: '',
          ),
        ),
        const SizedBox(height: AwSpace.x3),
        TextField(
          key: const Key('rule-body'),
          controller: _body,
          maxLength: 4000,
          minLines: 2,
          maxLines: 6,
          onTap: () => _templateTarget = _body,
          decoration: InputDecoration(
            labelText: 'ee.rules.body'.tr(),
            counterText: '',
          ),
        ),
      ],
    );
    switch (_action) {
      case 'assign':
        return [
          EeRulePickerField(
            key: const Key('rule-strategy'),
            label: 'ee.rules.strategy'.tr(),
            value: _strategy,
            errorText: _errors['strategy'],
            choices: [
              for (final s in o.assignStrategies)
                EeRuleChoice(s, strategyLabel(s)),
            ],
            onChanged: (v) => setState(() => _strategy = v ?? 'user'),
          ),
          if (_strategy == 'user')
            EeRulePickerField(
              key: const Key('rule-member'),
              label: 'ee.rules.member'.tr(),
              value: _userId,
              searchable: true,
              errorText: _errors['member'],
              choices: [for (final m in o.members) EeRuleChoice(m.id, m.name)],
              onChanged: (v) => setState(() {
                _userId = v;
                _errors.remove('member');
              }),
            ),
        ];
      case 'set_priority':
        return [
          EeRulePickerField(
            key: const Key('rule-action-priority'),
            label: 'ee.rules.priority'.tr(),
            value: _actionPriority,
            errorText: _errors['actionPriority'],
            choices: priorities,
            onChanged: (v) => setState(() => _actionPriority = v),
          ),
        ];
      case 'call_webhook':
        return [
          EeRulePickerField(
            key: const Key('rule-webhook'),
            label: 'ee.rules.webhook'.tr(),
            value: _webhookId,
            errorText: _errors['webhook'],
            choices: [
              for (final w in o.webhooks)
                EeRuleChoice(
                  w.id,
                  w.enabled == false
                      ? 'ee.rules.webhookPaused'.tr(args: {'name': w.name})
                      : w.name,
                ),
            ],
            onChanged: (v) => setState(() => _webhookId = v),
          ),
        ];
      case 'add_tag':
        return [
          EeRulePickerField(
            key: const Key('rule-tag'),
            label: 'ee.rules.tag'.tr(),
            value: _tagId,
            errorText: _errors['tag'],
            choices: [for (final t in o.tags) EeRuleChoice(t.id, t.name)],
            onChanged: (v) => setState(() => _tagId = v),
          ),
        ];
      case 'send_email':
        return [
          TextField(
            key: const Key('rule-email'),
            controller: _emailTo,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'ee.rules.emailTo'.tr(),
              errorText: _errors['email'],
            ),
          ),
          subjectAndBody(),
        ];
      case 'open_ticket' || 'open_task':
        return [
          EeRulePickerField(
            key: const Key('rule-target-service'),
            label: 'ee.rules.targetService'.tr(),
            value: _targetServiceId,
            emptyLabel: 'ee.rules.targetServiceHint'.tr(),
            choices: [
              EeRuleChoice(null, 'ee.rules.targetServiceHint'.tr()),
              ...services,
            ],
            onChanged: (v) => setState(() => _targetServiceId = v),
          ),
          EeRulePickerField(
            key: const Key('rule-open-priority'),
            label: 'ee.rules.openPriority'.tr(),
            value: _openPriority,
            choices: priorities,
            onChanged: (v) => setState(() => _openPriority = v ?? 'high'),
          ),
          subjectAndBody(),
        ];
    }
    return const [];
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AwSpace.x3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.all(Radius.circular(AwRadius.m)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: AwSpace.x2),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConditionRow extends StatelessWidget {
  const _ConditionRow({
    super.key,
    required this.conditionKey,
    required this.value,
    required this.choices,
    required this.onChanged,
    required this.onRemove,
  });

  final String conditionKey;
  final String? value;
  final List<EeRuleChoice> choices;
  final ValueChanged<String?> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: EeRulePickerField(
            key: Key('rule-cond-value-$conditionKey'),
            label: '${conditionLabel(conditionKey)} ${'ee.rules.is'.tr()}',
            value: value,
            emptyLabel: 'ee.rules.chooseValue'.tr(),
            choices: choices,
            onChanged: onChanged,
          ),
        ),
        IconButton(
          key: Key('rule-cond-remove-$conditionKey'),
          tooltip: 'ee.rules.removeCondition'.tr(),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          onPressed: onRemove,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _TestResult extends StatelessWidget {
  const _TestResult({required this.result, required this.options});

  final EeRuleTestResult result;
  final EeRuleOptions options;

  String? _value(String key, String? v) {
    if (v == null) return null;
    return switch (key) {
      'priority' => priorityLabel(v),
      'source' || 'automated_source' => sourceLabel(v),
      'service' => ruleOptionLabel(options.services, v).label,
      'unit' => ruleOptionLabel(options.units, v).label,
      'enabled' => v == 'true' ? 'ee.rules.enabled'.tr() : 'ee.rules.off'.tr(),
      'open' => v,
      _ => v,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.awTokens;
    final a = result.action;
    final detail = a.detail;
    final detailText = [
      if (detail['from'] != null && detail['to'] != null)
        '${priorityLabel(detail['from']!)} » ${priorityLabel(detail['to']!)}',
      if (detail['userId'] != null)
        ruleOptionLabel(options.members, detail['userId']).label,
      if (detail['tagId'] != null)
        ruleOptionLabel(options.tags, detail['tagId']).label,
      if (detail['webhookId'] != null)
        ruleOptionLabel(options.webhooks, detail['webhookId']).label,
      if (detail['serviceId'] != null)
        ruleOptionLabel(options.services, detail['serviceId']).label,
      if (detail['emailTo'] != null) detail['emailTo']!,
      if (detail['subject'] != null) '“${detail['subject']}”',
    ].join(' · ');
    final reason = a.reason == null
        ? null
        : (AwI18n.instance.maybeTranslate('ee.rules.reason.${a.reason}') ??
              a.reason!);
    return Column(
      key: const Key('rule-test-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              result.fires ? Icons.check_circle : Icons.cancel,
              size: 28,
              color: result.fires ? tokens.success : scheme.error,
            ),
            const SizedBox(width: AwSpace.x2),
            Expanded(
              child: Text(
                (result.fires ? 'ee.rules.wouldFire' : 'ee.rules.wouldNotFire')
                    .tr(args: {'ref': result.ticketRef}),
                key: const Key('rule-test-verdict'),
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: AwSpace.x2),
        for (final c in result.checks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              key: Key('rule-check-${c.key}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  c.pass ? Icons.check : Icons.close,
                  size: 18,
                  color: c.pass ? tokens.success : scheme.error,
                ),
                const SizedBox(width: AwSpace.x2),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'ee.rules.checkName.${c.key}'.tr(),
                          style: theme.textTheme.bodyMedium,
                        ),
                        // A state check's name says it all ("Rule is on"); only the
                        // match checks and the ceiling carry a value.
                        if ((c.group == 'match' || c.key == 'daily_cap') &&
                            (c.actual != null || c.expected != null))
                          TextSpan(
                            text:
                                ' — ${c.expected != null && !c.pass ? 'ee.rules.expectedFound'.tr(args: {'expected': _value(c.key, c.expected) ?? '-', 'actual': _value(c.key, c.actual) ?? '-'}) : 'ee.rules.found'.tr(args: {'actual': _value(c.key, c.actual) ?? '-'})}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: AwSpace.x6),
        Row(
          key: const Key('rule-test-action'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              switch (a.outcome) {
                'would_run' => Icons.play_circle_outline,
                'no_change' => Icons.remove_circle_outline,
                _ => Icons.error_outline,
              },
              size: 20,
              color: a.outcome == 'would_fail'
                  ? scheme.error
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AwSpace.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${actionLabel(a.kind)}: ${'ee.rules.outcome.${a.outcome}'.tr()}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (detailText.isNotEmpty)
                    Text(detailText, style: theme.textTheme.bodySmall),
                  if (reason != null)
                    Text(
                      reason,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
