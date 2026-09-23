import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/date_format.dart';
import '../../../core/error_messages.dart';
import '../../../core/fold.dart';
import '../../../core/persisted_prefs.dart';
import '../../../core/reachability.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/new_ticket_api.dart';
import '../my_tickets_providers.dart';
import '../new_ticket_providers.dart';
import '../providers.dart';
import '../ticket_drafts_providers.dart';

/// EE-225 — filing a request from the app.
///
/// ── ONE FORM, TWO WAYS OUT ────────────────────────────────────────────
///
/// With a connection the form goes through the door every other surface
/// uses (`POST /tickets`): the service, the unit when several answer it, the
/// service's form in force (EE-214) and, for whoever may, somebody else's
/// name (EE-170). Without one, E19's single exception applies — the SAME form
/// writes a draft (EE-216's engine, no second store) into the person's own
/// space, and says so, including what a draft cannot carry.
///
/// ── NOTHING THE DOOR WOULD REFUSE ────────────────────────────────────
///
/// The list of services is the server's catalogue, which offers exactly what
/// the door accepts (live and routed). The form's conditions and required
/// marks are the server's too; the device only evaluates them as somebody
/// types (`visibleFormFields`), because a form that waited for a round trip
/// to reveal the next question would not be a form.
class EeNewTicketScreen extends ConsumerStatefulWidget {
  const EeNewTicketScreen({super.key});

  @override
  ConsumerState<EeNewTicketScreen> createState() => _EeNewTicketScreenState();
}

class _EeNewTicketScreenState extends ConsumerState<EeNewTicketScreen> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _requesterName = TextEditingController();
  final _requesterEmail = TextEditingController();
  final _answers = <String, Object?>{};
  final _textAnswers = <String, TextEditingController>{};
  EeCatalogService? _service;
  String? _unitId;
  bool _onBehalf = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final controller in [_subject, _body, _requesterName]) {
      controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _subject,
      _body,
      _requesterName,
      _requesterEmail,
      ..._textAnswers.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {});

  void _pickService(EeCatalogService service) {
    setState(() {
      _service = service;
      // One unit needs no choice; several need the person's.
      _unitId = service.units.length == 1 ? service.units.single.id : null;
      // Answers belong to the form they were given against.
      _answers.clear();
      for (final controller in _textAnswers.values) {
        controller.dispose();
      }
      _textAnswers.clear();
      _error = null;
    });
  }

  TextEditingController _textFor(EeFormField field) =>
      _textAnswers.putIfAbsent(field.key, () {
        final controller = TextEditingController();
        controller.addListener(() {
          final text = controller.text.trim();
          setState(() {
            if (text.isEmpty) {
              _answers.remove(field.key);
            } else if (field.type == 'number') {
              _answers[field.key] = num.tryParse(text) ?? text;
            } else {
              _answers[field.key] = text;
            }
          });
        });
        return controller;
      });

  /// What is still missing for an online send, in the words on the screen.
  List<String> _missing(bool online) {
    final missing = <String>[];
    if (_subject.text.trim().isEmpty) {
      missing.add('ee.tickets.new.subject'.tr());
    }
    if (!online) return missing;
    final service = _service;
    if (service == null) {
      missing.add('ee.tickets.new.service'.tr());
      return missing;
    }
    if (service.units.length > 1 && _unitId == null) {
      missing.add('ee.tickets.new.unit'.tr());
    }
    for (final field in missingRequiredFields(service.fields, _answers)) {
      missing.add(field.label);
    }
    for (final field in visibleFormFields(service.fields, _answers)) {
      if (field.type == 'number' &&
          _answers[field.key] != null &&
          _answers[field.key] is! num) {
        missing.add(field.label);
      }
    }
    if (_onBehalf && _requesterName.text.trim().isEmpty) {
      missing.add('ee.tickets.new.requesterName'.tr());
    }
    return missing;
  }

  Future<void> _send() async {
    final online = ref.read(serverReachabilityProvider) != false;
    final missing = _missing(online);
    if (missing.isNotEmpty) {
      setState(
        () => _error = 'ee.tickets.new.missing'.tr(
          args: {'fields': missing.join(', ')},
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    try {
      final String done;
      if (online) {
        done = await _file();
      } else {
        final saved = await _draft();
        if (saved == null) {
          setState(() {
            _busy = false;
            _error = 'ee.tickets.new.noDraftHome'.tr();
          });
          return;
        }
        done = saved;
      }
      messenger?.showSnackBar(SnackBar(content: Text(done)));
      navigator.pop();
    } on ApiException catch (failure) {
      // No answer at all: the form turns into its offline self and says so;
      // what was typed stays exactly where it is.
      if (failure.code == 'NETWORK_ERROR') {
        ref.read(serverReachabilityProvider.notifier).unreachable();
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _error = localizedError(failure);
        });
      }
    }
  }

  Future<String> _file() async {
    final service = _service!;
    final visible = {
      for (final field in visibleFormFields(service.fields, _answers))
        field.key,
    };
    final filed = await ref
        .read(eeNewTicketApiProvider)
        .create(
          serviceId: service.id,
          subject: _subject.text.trim(),
          body: _body.text.trim().isEmpty ? null : _body.text.trim(),
          unitId: service.units.length > 1 ? _unitId : null,
          fields: {
            for (final entry in _answers.entries)
              if (visible.contains(entry.key)) entry.key: entry.value,
          },
          requesterName: _onBehalf ? _requesterName.text.trim() : null,
          requesterEmail: _onBehalf && _requesterEmail.text.trim().isNotEmpty
              ? _requesterEmail.text.trim()
              : null,
        );
    // The requester's list is a REST read; the desk's queue is the replica.
    // Both are told now rather than at their next scheduled look.
    ref.invalidate(eeMyTicketsProvider);
    unawaited(ref.read(syncEngineProvider)?.syncNow());
    return filed.number == null
        ? 'ee.tickets.new.sent'.tr()
        : 'ee.tickets.new.sentNumbered'.tr(args: {'number': '${filed.number}'});
  }

  /// The offline way out: EE-216's store, in the person's own space. Null
  /// when this device knows of no such space to keep it in.
  Future<String?> _draft() async {
    final home = ref.read(draftWorkspaceIdProvider);
    if (home == null) return null;
    await ref
        .read(ticketDraftStoreProvider)
        .write(
          workspaceId: home,
          subject: _subject.text.trim(),
          body: _body.text.trim().isEmpty ? null : _body.text.trim(),
          serviceId: _service?.id,
        );
    return 'ee.tickets.new.drafted'.tr();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = ref.watch(serverReachabilityProvider) != false;
    final catalog = ref.watch(eeCatalogProvider);
    final mayActForOthers = ref.watch(canProvider('tickets.create_on_behalf'));
    final service = _service;

    return Scaffold(
      appBar: AppBar(title: Text('ee.tickets.new.title'.tr())),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(eeCatalogProvider.future),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AwSpace.x4,
            AwSpace.x4,
            AwSpace.x4,
            AwSpace.x6 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: [
            if (!online) ...[
              _Note(
                key: const Key('new-ticket-offline'),
                icon: Icons.cloud_off_outlined,
                text: 'ee.tickets.new.offline'.tr(),
              ),
              const SizedBox(height: AwSpace.x2),
              _Note(
                key: const Key('new-ticket-draft-note'),
                icon: Icons.inventory_2_outlined,
                text: 'ee.tickets.new.draftCarries'.tr(),
              ),
              const SizedBox(height: AwSpace.x4),
            ],
            // ── The service ───────────────────────────────────────────────
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                key: const Key('new-ticket-service'),
                leading: const Icon(Icons.category_outlined),
                title: Text(service?.name ?? 'ee.tickets.new.pickService'.tr()),
                subtitle: Text(
                  service?.description ?? 'ee.tickets.new.service'.tr(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                enabled: !_busy,
                onTap: () => _openCatalog(catalog),
              ),
            ),
            if (catalog.hasError || (catalog.hasValue && catalog.value == null))
              Padding(
                key: const Key('new-ticket-catalog-unavailable'),
                padding: const EdgeInsets.only(top: AwSpace.x2),
                child: Text(
                  'ee.tickets.new.catalogUnavailable'.tr(),
                  style: _quiet(theme),
                ),
              ),
            if (service != null && service.needsApproval) ...[
              const SizedBox(height: AwSpace.x2),
              _Note(
                key: const Key('new-ticket-approval'),
                icon: Icons.approval_outlined,
                text: 'ee.tickets.new.needsApproval'.tr(),
              ),
            ],
            if (service != null && service.units.length > 1) ...[
              const SizedBox(height: AwSpace.x4),
              Text(
                'ee.tickets.new.unit'.tr(),
                style: theme.textTheme.titleSmall,
              ),
              if (!online)
                Padding(
                  padding: const EdgeInsets.only(top: AwSpace.x1),
                  child: Text(
                    'ee.tickets.new.draftMultiUnit'.tr(),
                    key: const Key('new-ticket-draft-multi-unit'),
                    style: _quiet(theme),
                  ),
                )
              else
                RadioGroup<String>(
                  groupValue: _unitId,
                  onChanged: (value) {
                    if (!_busy) setState(() => _unitId = value);
                  },
                  child: Column(
                    children: [
                      for (final unit in service.units)
                        RadioListTile<String>(
                          key: Key('new-ticket-unit-${unit.id}'),
                          contentPadding: EdgeInsets.zero,
                          value: unit.id,
                          title: Text(unit.name),
                        ),
                    ],
                  ),
                ),
            ],
            // ── What happened ─────────────────────────────────────────────
            const SizedBox(height: AwSpace.x4),
            TextField(
              key: const Key('new-ticket-subject'),
              controller: _subject,
              enabled: !_busy,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'ee.tickets.new.subject'.tr(),
                hintText: 'ee.tickets.new.subjectHint'.tr(),
              ),
            ),
            const SizedBox(height: AwSpace.x2),
            TextField(
              key: const Key('new-ticket-body'),
              controller: _body,
              enabled: !_busy,
              minLines: 3,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'ee.tickets.new.body'.tr(),
                hintText: 'ee.tickets.new.bodyHint'.tr(),
              ),
            ),
            // ── The service's own questions — only with a connection ──────
            if (service != null && online)
              for (final field in visibleFormFields(service.fields, _answers))
                Padding(
                  padding: const EdgeInsets.only(top: AwSpace.x3),
                  child: _field(context, field),
                ),
            // ── For somebody else (EE-170) ────────────────────────────────
            if (mayActForOthers && online) ...[
              const SizedBox(height: AwSpace.x3),
              SwitchListTile(
                key: const Key('new-ticket-on-behalf'),
                contentPadding: EdgeInsets.zero,
                value: _onBehalf,
                title: Text('ee.tickets.new.onBehalf'.tr()),
                subtitle: Text('ee.tickets.new.onBehalfHelp'.tr()),
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _onBehalf = value),
              ),
              if (_onBehalf) ...[
                TextField(
                  key: const Key('new-ticket-requester-name'),
                  controller: _requesterName,
                  enabled: !_busy,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'ee.tickets.new.requesterName'.tr(),
                  ),
                ),
                TextField(
                  key: const Key('new-ticket-requester-email'),
                  controller: _requesterEmail,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'ee.tickets.new.requesterEmail'.tr(),
                  ),
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: AwSpace.x3),
              AwInlineError(
                message: _error!,
                textKey: const Key('new-ticket-error'),
              ),
            ],
            const SizedBox(height: AwSpace.x4),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                key: const Key('new-ticket-submit'),
                onPressed: _busy ? null : _send,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(online ? Icons.send_outlined : Icons.save_outlined),
                label: Text(
                  (online ? 'ee.tickets.new.send' : 'ee.tickets.new.saveDraft')
                      .tr(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(BuildContext context, EeFormField field) {
    final theme = Theme.of(context);
    final label = field.required
        ? 'ee.tickets.new.requiredLabel'.tr(args: {'label': field.label})
        : field.label;
    final key = Key('new-ticket-field-${field.key}');
    final help = field.help;
    switch (field.type) {
      case 'checkbox':
        return CheckboxListTile(
          key: key,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _answers[field.key] == true,
          title: Text(label),
          subtitle: help == null ? null : Text(help),
          onChanged: _busy
              ? null
              : (value) => setState(() => _answers[field.key] = value ?? false),
        );
      case 'select':
        return DropdownButtonFormField<String>(
          key: key,
          initialValue: _answers[field.key] as String?,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, helperText: help),
          hint: Text('ee.tickets.new.selectHint'.tr()),
          items: [
            for (final option in field.options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  if (value == null) {
                    _answers.remove(field.key);
                  } else {
                    _answers[field.key] = value;
                  }
                }),
        );
      case 'date':
        final picked = _answers[field.key] as String?;
        final format = ref.watch(dateFormatProvider);
        return InputDecorator(
          key: key,
          decoration: InputDecoration(labelText: label, helperText: help),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: Key('new-ticket-field-${field.key}-pick'),
              onPressed: _busy ? null : () => _pickDate(field),
              icon: const Icon(Icons.event_outlined),
              label: Text(
                picked == null
                    ? 'ee.tickets.new.pickDate'.tr()
                    : awFormatDate(DateTime.parse(picked), format: format),
              ),
            ),
          ),
        );
      default:
        final number = field.type == 'number';
        final controller = _textFor(field);
        final raw = controller.text.trim();
        return TextField(
          key: key,
          controller: controller,
          enabled: !_busy,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(
            labelText: label,
            helperText: help,
            errorText: number && raw.isNotEmpty && num.tryParse(raw) == null
                ? 'ee.tickets.new.invalidNumber'.tr()
                : null,
          ),
          style: theme.textTheme.bodyLarge,
        );
    }
  }

  Future<void> _pickDate(EeFormField field) async {
    final now = DateTime.now();
    final current = _answers[field.key] as String?;
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null ? now : DateTime.parse(current),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() {
      // The day, as the server's date answers are written: yyyy-mm-dd.
      _answers[field.key] =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _openCatalog(AsyncValue<EeCatalog?> catalog) async {
    final picked = await showEeCatalogPicker(context);
    if (picked != null && mounted) _pickService(picked);
  }
}

/// The catalogue as a picker — the new-request form's, and the one a held
/// draft uses to finally name its service (EE-225). One sheet, so the two
/// can never offer different lists.
Future<EeCatalogService?> showEeCatalogPicker(BuildContext context) =>
    showModalBottomSheet<EeCatalogService>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _CatalogSheet(),
    );

TextStyle? _quiet(ThemeData theme) => theme.textTheme.bodySmall?.copyWith(
  color: theme.colorScheme.onSurfaceVariant,
);

class _Note extends StatelessWidget {
  const _Note({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AwSpace.x2),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

/// The catalogue, grouped by its shelves and searchable on the device.
///
/// The search folds on the device (`foldSearchText`), EE-212's decision for
/// the app: the catalogue arrives whole over REST, so `yazici` finds
/// `Yazıcı` without asking the server for a third definition of "matches".
class _CatalogSheet extends ConsumerStatefulWidget {
  const _CatalogSheet();

  @override
  ConsumerState<_CatalogSheet> createState() => _CatalogSheetState();
}

class _CatalogSheetState extends ConsumerState<_CatalogSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = ref.watch(eeCatalogProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AwSpace.x4,
            0,
            AwSpace.x4,
            AwSpace.x4,
          ),
          child: catalog.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AwSpace.x6),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => AwInlineError(message: localizedError(error)),
            data: (data) {
              if (data == null || data.services.isEmpty) {
                return AwEmptyState(
                  key: const Key('new-ticket-catalog-empty'),
                  icon: Icons.category_outlined,
                  title: 'ee.tickets.new.pickService'.tr(),
                  message:
                      (data == null
                              ? 'ee.tickets.new.catalogUnavailable'
                              : 'ee.tickets.new.noServices')
                          .tr(),
                );
              }
              final needle = foldSearchText(_query);
              final hits = [
                for (final service in data.services)
                  if (needle.isEmpty ||
                      foldSearchText(
                        '${service.name} ${service.description ?? ''}',
                      ).contains(needle))
                    service,
              ];
              final names = {for (final c in data.categories) c.id: c.name};
              final byShelf = <String?, List<EeCatalogService>>{};
              for (final service in hits) {
                final shelf = names.containsKey(service.categoryId)
                    ? service.categoryId
                    : null;
                (byShelf[shelf] ??= []).add(service);
              }
              final shelves = [
                for (final c in data.categories)
                  if (byShelf.containsKey(c.id)) c.id,
                if (byShelf.containsKey(null)) null,
              ];
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ee.tickets.new.pickService'.tr(),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AwSpace.x2),
                  TextField(
                    key: const Key('new-ticket-service-search'),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'ee.tickets.new.serviceSearch'.tr(),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: AwSpace.x2),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final shelf in shelves) ...[
                          if (shelves.length > 1 || shelf != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AwSpace.x3,
                                bottom: AwSpace.x1,
                              ),
                              child: Text(
                                shelf == null
                                    ? 'ee.tickets.new.otherCategory'.tr()
                                    : names[shelf]!,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          for (final service in byShelf[shelf]!)
                            ListTile(
                              key: Key('catalog-service-${service.id}'),
                              contentPadding: EdgeInsets.zero,
                              title: Text(service.name),
                              subtitle: service.description == null
                                  ? null
                                  : Text(
                                      service.description!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              trailing: service.needsApproval
                                  ? Icon(
                                      Icons.approval_outlined,
                                      semanticLabel:
                                          'ee.tickets.new.needsApproval'.tr(),
                                    )
                                  : null,
                              onTap: () => Navigator.of(context).pop(service),
                            ),
                        ],
                        if (hits.isEmpty)
                          Padding(
                            key: const Key('new-ticket-service-none'),
                            padding: const EdgeInsets.all(AwSpace.x4),
                            child: Text(
                              'ee.tickets.new.searchEmpty'.tr(),
                              style: _quiet(theme),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
