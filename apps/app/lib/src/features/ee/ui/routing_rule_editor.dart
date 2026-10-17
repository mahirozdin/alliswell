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
import '../providers.dart' show canProvider;
import '../rules_providers.dart';
import 'rules_widgets.dart';

const _kFieldOf = {
  'CLASSIFICATION_RULE_NAME_TAKEN': 'name',
  'CLASSIFICATION_RULE_HAS_NO_ACTION': 'then',
  'CLASSIFICATION_UNKNOWN_TAG': 'tag',
  'CLASSIFICATION_TOO_MANY_KEYWORDS': 'keywords',
  'CLASSIFICATION_KEYWORD_TOO_LONG': 'keywords',
  'CLASSIFICATION_UNKNOWN_PRIORITY': 'priority',
};

/// EE-308 — one routing (classification, EE-202) rule.
///
/// ── PRIORITY IS A CLAIM, AND ONLY A CHANGED ONE IS SENT ──
///
/// Naming a priority on a routing rule needs `tickets.override_priority`
/// (the server's guard reads ANY body carrying `actionPriority`). So the
/// priority picker is locked, with the reason, for an admin without it — and
/// a PATCH carries only the keys that moved, so such an admin can still
/// rename a rule that somebody else gave a priority.
///
/// ── THE DRY RUN KNOWS THE ORDER ──
///
/// "Try on recent requests" places the draft at its own position: a request
/// a rule above would take is reported as SHADOWED, by that rule's name,
/// rather than counted as a match the engine will never make.
class EeRoutingRuleEditor extends ConsumerStatefulWidget {
  const EeRoutingRuleEditor({super.key, this.ruleId});

  final String? ruleId;

  @override
  ConsumerState<EeRoutingRuleEditor> createState() =>
      _EeRoutingRuleEditorState();
}

class _EeRoutingRuleEditorState extends ConsumerState<EeRoutingRuleEditor> {
  bool _ready = false;
  EeClassificationRule? _before;

  final _name = TextEditingController();
  final _keyword = TextEditingController();
  final _from = TextEditingController();

  bool _enabled = true;
  String? _source;
  String? _condService;
  List<String> _keywords = [];
  String? _service;
  String? _unit;
  String? _priority;
  String? _tag;

  Map<String, String> _errors = {};
  String? _banner;
  bool _busy = false;

  EeClassificationDryRun? _dry;
  String? _dryError;
  bool _trying = false;

  @override
  void dispose() {
    _name.dispose();
    _keyword.dispose();
    _from.dispose();
    super.dispose();
  }

  void _init(EeClassificationRule? rule) {
    _ready = true;
    _before = rule;
    if (rule == null) return;
    _name.text = rule.name;
    _enabled = rule.enabled;
    _source = rule.condSource;
    _condService = rule.condServiceId;
    _keywords = [...rule.condKeywords];
    _from.text = rule.condFrom ?? '';
    _service = rule.actionServiceId;
    _unit = rule.actionUnitId;
    _priority = rule.actionPriority;
    _tag = rule.actionTagId;
  }

  EeClassificationRule _draft() {
    final from = _from.text.trim();
    return EeClassificationRule(
      id: _before?.id ?? '',
      name: _name.text.trim(),
      position: _before?.position ?? 0,
      enabled: _enabled,
      condSource: _source,
      condServiceId: _condService,
      condKeywords: _keywords,
      condFrom: from.isEmpty ? null : from,
      actionServiceId: _service,
      actionUnitId: _unit,
      actionPriority: _priority,
      actionTagId: _tag,
    );
  }

  void _addKeyword(EeRuleOptions o) {
    final word = _keyword.text.trim();
    if (word.isEmpty) return;
    setState(() {
      if (word.length > o.maxKeywordLength) {
        _errors = {
          ..._errors,
          'keywords': 'ee.rules.keywordTooLong'.tr(
            args: {'n': '${o.maxKeywordLength}'},
          ),
        };
        return;
      }
      if (_keywords.length >= o.maxKeywords) {
        _errors = {
          ..._errors,
          'keywords': 'ee.rules.keywordTooMany'.tr(
            args: {'n': '${o.maxKeywords}'},
          ),
        };
        return;
      }
      if (!_keywords.contains(word)) _keywords = [..._keywords, word];
      _keyword.clear();
      _errors = {..._errors}..remove('keywords');
    });
  }

  Map<String, String> _validate() {
    final e = <String, String>{};
    if (_name.text.trim().isEmpty) e['name'] = 'ee.rules.nameRequired'.tr();
    if (!_draft().acts) e['then'] = 'ee.rules.needsAction'.tr();
    return e;
  }

  Future<void> _save() async {
    final errors = _validate();
    setState(() {
      _errors = errors;
      _banner = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(eeRoutingRulesProvider.notifier).save(_before, _draft());
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

  Future<void> _try() async {
    final draft = _draft();
    setState(() {
      _trying = true;
      _dryError = null;
    });
    try {
      final body = draft.toBody();
      // The dry run wants a name like the write doors do; an unnamed draft is
      // still worth trying.
      if ((body['name'] as String).isEmpty) body['name'] = '-';
      body['position'] = _before?.position ?? _lastPosition() + 1;
      final result = await ref
          .read(eeRulesApiProvider)
          .dryRunRouting(id: _before?.id, draft: body);
      if (mounted) setState(() => _dry = result);
    } catch (e) {
      setState(() => _dryError = localizedError(e));
    } finally {
      if (mounted) setState(() => _trying = false);
    }
  }

  int _lastPosition() {
    final list = ref.read(eeRoutingRulesProvider).value ?? const [];
    return list.fold<int>(-1, (top, r) => r.position > top ? r.position : top);
  }

  Future<void> _duplicate() async {
    final id = _before?.id;
    if (id == null) return;
    try {
      await ref.read(eeRoutingRulesProvider.notifier).duplicate(id);
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
      await ref.read(eeRoutingRulesProvider.notifier).delete(rule.id);
      if (mounted) await Navigator.of(context).maybePop();
    } catch (e) {
      setState(() => _banner = localizedError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(eeRoutingRulesProvider);
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
          ref.invalidate(eeRoutingRulesProvider);
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
        EeClassificationRule? rule;
        for (final r in list) {
          if (r.id == widget.ruleId) rule = r;
        }
        _init(rule);
      }
      body = _form(context, o);
    }
    return Scaffold(
      appBar: AppBar(
        leading: awRouteLeading(context),
        title: Text(
          widget.ruleId == null
              ? 'ee.rules.newRouting'.tr()
              : 'ee.rules.editRouting'.tr(),
        ),
        actions: [
          TextButton(
            key: const Key('routing-save-top'),
            onPressed: o != null && _ready && !_busy ? _save : null,
            child: Text('ee.rules.save'.tr()),
          ),
          if (_before != null)
            PopupMenuButton<String>(
              key: const Key('routing-editor-menu'),
              tooltip: 'ee.rules.more'.tr(),
              onSelected: (v) => v == 'duplicate' ? _duplicate() : _delete(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'duplicate',
                  child: Text('ee.rules.duplicate'.tr()),
                ),
                PopupMenuItem(
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
    final mayPrioritize = ref.watch(canProvider('tickets.override_priority'));
    final services = [for (final s in o.services) EeRuleChoice(s.id, s.name)];
    final none = EeRuleChoice(null, 'ee.rules.none'.tr());
    final any = EeRuleChoice(null, 'ee.rules.any'.tr());
    return ListView(
      key: const Key('routing-editor-list'),
      padding: awListPadding(context),
      children: [
        if (_banner != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AwSpace.x2),
            child: AwInlineError(message: _banner!),
          ),
        EeRuleSection(
          title: 'ee.rules.name'.tr(),
          children: [
            TextField(
              key: const Key('routing-name'),
              controller: _name,
              maxLength: 160,
              decoration: InputDecoration(
                labelText: 'ee.rules.name'.tr(),
                errorText: _errors['name'],
                counterText: '',
              ),
            ),
            SwitchListTile(
              key: const Key('routing-enabled'),
              contentPadding: EdgeInsets.zero,
              title: Text('ee.rules.enabled'.tr()),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
          ],
        ),
        EeRuleSection(
          title: 'ee.rules.if'.tr(),
          help: 'ee.rules.conditionsHelp'.tr(),
          children: [
            EeRulePickerField(
              key: const Key('routing-source'),
              label: 'ee.rules.conditionName.source'.tr(),
              value: _source,
              emptyLabel: any.label,
              choices: [
                any,
                for (final s in o.classificationSources)
                  EeRuleChoice(s, sourceLabel(s)),
              ],
              onChanged: (v) => setState(() => _source = v),
            ),
            EeRulePickerField(
              key: const Key('routing-cond-service'),
              label: 'ee.rules.service'.tr(),
              value: _condService,
              emptyLabel: any.label,
              choices: [any, ...services],
              onChanged: (v) => setState(() => _condService = v),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('routing-keyword'),
                        controller: _keyword,
                        onSubmitted: (_) => _addKeyword(o),
                        decoration: InputDecoration(
                          labelText: 'ee.rules.keywords'.tr(),
                          helperText: 'ee.rules.keywordsHelp'.tr(),
                          helperMaxLines: 3,
                          errorText: _errors['keywords'],
                          errorMaxLines: 2,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('routing-keyword-add'),
                      tooltip: 'ee.rules.keywordAdd'.tr(),
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: () => _addKeyword(o),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                if (_keywords.isNotEmpty) ...[
                  const SizedBox(height: AwSpace.x2),
                  Wrap(
                    spacing: AwSpace.x2,
                    runSpacing: AwSpace.x1,
                    children: [
                      for (final k in _keywords)
                        InputChip(
                          key: Key('routing-keyword-chip-$k'),
                          label: Text(k),
                          onDeleted: () => setState(
                            () => _keywords = [..._keywords]..remove(k),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
            TextField(
              key: const Key('routing-from'),
              controller: _from,
              maxLength: 320,
              decoration: InputDecoration(
                labelText: 'ee.rules.from'.tr(),
                helperText: 'ee.rules.fromHelp'.tr(),
                helperMaxLines: 2,
                counterText: '',
              ),
            ),
          ],
        ),
        EeRuleSection(
          key: const Key('routing-then'),
          title: 'ee.rules.then'.tr(),
          errorText: _errors['then'],
          children: [
            EeRulePickerField(
              key: const Key('routing-service'),
              label: 'ee.rules.service'.tr(),
              value: _service,
              emptyLabel: none.label,
              choices: [none, ...services],
              onChanged: (v) => setState(() => _service = v),
            ),
            EeRulePickerField(
              key: const Key('routing-unit'),
              label: 'ee.rules.unit'.tr(),
              value: _unit,
              emptyLabel: none.label,
              choices: [
                none,
                for (final u in o.units) EeRuleChoice(u.id, u.name),
              ],
              onChanged: (v) => setState(() => _unit = v),
            ),
            EeRulePickerField(
              key: const Key('routing-priority'),
              label: 'ee.rules.priority'.tr(),
              value: _priority,
              enabled: mayPrioritize,
              emptyLabel: none.label,
              errorText: _errors['priority'],
              helperText: mayPrioritize ? null : 'ee.rules.priorityLocked'.tr(),
              choices: [
                none,
                for (final p in o.priorities) EeRuleChoice(p, priorityLabel(p)),
              ],
              onChanged: (v) => setState(() => _priority = v),
            ),
            EeRulePickerField(
              key: const Key('routing-tag'),
              label: 'ee.rules.tag'.tr(),
              value: _tag,
              emptyLabel: none.label,
              errorText: _errors['tag'],
              choices: [
                none,
                for (final t in o.tags) EeRuleChoice(t.id, t.name),
              ],
              onChanged: (v) => setState(() => _tag = v),
            ),
          ],
        ),
        EeRuleSection(
          key: const Key('routing-try'),
          title: 'ee.rules.tryRecent'.tr(),
          help: 'ee.rules.tryRecentHelp'.tr(),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonal(
                key: const Key('routing-try-run'),
                style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
                onPressed: _trying ? null : _try,
                child: Text('ee.rules.tryRun'.tr()),
              ),
            ),
            if (_dryError != null) AwInlineError(message: _dryError!),
            if (_dry != null) _DryRunResult(result: _dry!),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AwSpace.x3),
          child: FilledButton(
            key: const Key('routing-save'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _ready && !_busy ? _save : null,
            child: Text('ee.rules.save'.tr()),
          ),
        ),
        Text(
          'ee.rules.explainRouting'.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DryRunResult extends StatelessWidget {
  const _DryRunResult({required this.result});

  final EeClassificationDryRun result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    String ref(EeDryRunHit h) => h.number == null ? '' : '#${h.number} ';
    return Column(
      key: const Key('routing-dry-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ee.rules.drySummary'.tr(
            args: {
              'sampled': '${result.sampled}',
              'matched': '${result.matched.length}',
              'unmatched': '${result.unmatched}',
            },
          ),
          key: const Key('routing-dry-summary'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AwSpace.x2),
        Text('ee.rules.dryMatched'.tr(), style: theme.textTheme.titleSmall),
        if (result.matched.isEmpty) Text('ee.rules.dryNone'.tr(), style: muted),
        for (final h in result.matched.take(20))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                const Icon(Icons.check, size: 16),
                const SizedBox(width: AwSpace.x2),
                Expanded(
                  child: Text(
                    '${ref(h)}${h.subject}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (result.shadowed.isNotEmpty) ...[
          const SizedBox(height: AwSpace.x2),
          Text('ee.rules.dryShadowed'.tr(), style: theme.textTheme.titleSmall),
          for (final h in result.shadowed.take(20))
            Padding(
              key: Key('routing-dry-shadowed-${h.ticketId}'),
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.subdirectory_arrow_right, size: 16),
                  const SizedBox(width: AwSpace.x2),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${ref(h)}${h.subject} '),
                          TextSpan(
                            text: 'ee.rules.shadowedBy'.tr(
                              args: {'rule': h.byRuleName ?? ''},
                            ),
                            style: muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
