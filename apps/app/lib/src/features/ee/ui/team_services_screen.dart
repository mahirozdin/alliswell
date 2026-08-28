import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/services_models.dart';
import '../data/units_models.dart';
import '../services_providers.dart';
import '../units_providers.dart';

/// The service catalogue (EE-082, madde 8).
///
/// Two facts share every row, and the second one is the reason this screen
/// looks the way it does:
///
///   • WHAT can be asked for — the service's name.
///   • WHO answers it — the units it routes to. A service routed nowhere
///     accepts no request at all (the server refuses it by an empty JOIN), and
///     nothing else on the row would betray that. So it is stated, in the
///     warning colour, on the row itself: "no unit assigned — receives
///     nothing". A catalogue whose entries silently swallow requests is worse
///     than an empty catalogue.
///
/// Archived rows read as RETIRED, not broken — muted, never struck through or
/// coloured like an error (the units screen settled this first). An archived
/// service keeps its history and stops taking new requests, which is exactly
/// what "aktif" means on the server side.
class EeTeamServicesScreen extends ConsumerWidget {
  const EeTeamServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(eeServicesProvider);

    return Scaffold(
      appBar: AppBar(title: Text('ee.team.services.title'.tr())),
      floatingActionButton: FloatingActionButton(
        key: const Key('service-new'),
        tooltip: 'ee.team.services.create'.tr(),
        onPressed: () => editService(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: services.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeServicesProvider),
        ),
        data: (list) {
          // Null is "not yours to shape" — the screen should not have been
          // reachable, but a stale link can still land here.
          if (list == null) {
            return AwEmptyState(
              icon: Icons.lock_outline,
              title: 'ee.team.services.noneTitle'.tr(),
              message: 'ee.team.services.noneBody'.tr(),
            );
          }
          if (list.isEmpty) {
            return AwEmptyState(
              icon: Icons.support_agent_outlined,
              title: 'ee.team.services.emptyTitle'.tr(),
              message: 'ee.team.services.emptyBody'.tr(),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AwSpace.x4),
            children: [
              Text(
                'ee.team.services.intro'.tr(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AwSpace.x3),
              for (final service in list) _ServiceCard(service: service),
            ],
          );
        },
      ),
    );
  }

  /// Null service = creating one. The same sheet either way: naming a service
  /// and renaming one are the same act with a different starting value.
  static Future<void> editService(
    BuildContext context,
    WidgetRef ref,
    EeService? service,
  ) async {
    final name = TextEditingController(text: service?.name ?? '');
    final description = TextEditingController(text: service?.description ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          service == null
              ? 'ee.team.services.create'.tr()
              : 'ee.team.services.rename'.tr(),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('service-name'),
              controller: name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'ee.team.services.name'.tr(),
              ),
            ),
            const SizedBox(height: AwSpace.x3),
            TextField(
              key: const Key('service-description'),
              controller: description,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'ee.team.services.description'.tr(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('service-save'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('common.save'.tr()),
          ),
        ],
      ),
    );
    if (saved != true || name.text.trim().isEmpty) return;
    final notifier = ref.read(eeServicesProvider.notifier);
    if (service == null) {
      await notifier.create(
        name: name.text.trim(),
        description: description.text.trim().isEmpty
            ? null
            : description.text.trim(),
      );
    } else {
      await notifier.rename(
        service.id,
        name: name.text.trim(),
        description: description.text.trim(),
      );
    }
  }
}

class _ServiceCard extends ConsumerWidget {
  const _ServiceCard({required this.service});

  final EeService service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final units = ref.watch(eeUnitsProvider).value ?? const <EeUnit>[];
    final names = units
        .where((u) => service.unitIds.contains(u.id))
        .map((u) => u.name)
        .toList();

    return Card(
      key: Key('service-${service.id}'),
      child: ListTile(
        leading: Icon(
          service.archived
              ? Icons.inventory_2_outlined
              : Icons.support_agent_outlined,
          color: service.archived ? theme.disabledColor : null,
        ),
        title: Text(service.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (service.description != null && service.description!.isNotEmpty)
              Text(service.description!, style: theme.textTheme.bodySmall),
            const SizedBox(height: AwSpace.x1),
            // THE ROW'S REAL JOB. A live service with no unit receives
            // nothing, and no other part of this card would say so.
            if (service.unroutable)
              Row(
                children: [
                  Icon(
                    Icons.report_problem_outlined,
                    size: 16,
                    color: context.awTokens.warning,
                  ),
                  const SizedBox(width: AwSpace.x1),
                  Expanded(
                    // The ICON carries the amber; the sentence does not.
                    // MEASURED: `warning` on the card is 3.46:1 in light —
                    // above the 3.0 a graphic needs, below the 4.5 body text
                    // needs. `contrast.py` says FAILURES: 0 either way,
                    // because the only pair it lists for this colour on this
                    // surface is the warning STAR, at the icon threshold. The
                    // alert row settled this shape first (DESIGN §7.1): colour
                    // signals, ink reads.
                    child: Text(
                      'ee.team.services.noUnits'.tr(),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              )
            else
              Text(
                [
                  if (names.isNotEmpty) names.join(', '),
                  if (service.archived) 'ee.team.services.archived'.tr(),
                  if (service.formFields.isNotEmpty)
                    'ee.team.services.fieldCount'.tr(
                      args: {'count': '${service.formFields.length}'},
                    ),
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          key: Key('service-menu-${service.id}'),
          onSelected: (value) async {
            switch (value) {
              case 'rename':
                await EeTeamServicesScreen.editService(context, ref, service);
              case 'archive':
                await ref
                    .read(eeServicesProvider.notifier)
                    .setArchived(service.id, archived: !service.archived);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'rename',
              child: Text('ee.team.services.rename'.tr()),
            ),
            PopupMenuItem(
              value: 'archive',
              child: Text(
                service.archived
                    ? 'ee.team.services.unarchive'.tr()
                    : 'ee.team.services.archive'.tr(),
              ),
            ),
          ],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EeServiceRoutingScreen(service: service),
          ),
        ),
      ),
    );
  }
}

/// Which units answer this service, and what its form asks (EE-082).
///
/// Both halves live on one screen because they are one decision from the
/// admin's side — "set this service up" — and because the second is
/// meaningless without the first: custom fields on a service nobody answers
/// are questions nobody will read.
class EeServiceRoutingScreen extends ConsumerStatefulWidget {
  const EeServiceRoutingScreen({super.key, required this.service});

  final EeService service;

  @override
  ConsumerState<EeServiceRoutingScreen> createState() =>
      _EeServiceRoutingScreenState();
}

class _EeServiceRoutingScreenState
    extends ConsumerState<EeServiceRoutingScreen> {
  late final Set<String> _units = widget.service.unitIds.toSet();
  late final List<EeServiceField> _fields = [...widget.service.formFields];
  bool _busy = false;

  bool get _dirty =>
      !_setEquals(_units, widget.service.unitIds.toSet()) ||
      !_fieldsEqual(_fields, widget.service.formFields);

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  static bool _fieldsEqual(List<EeServiceField> a, List<EeServiceField> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => i).every(
        (i) =>
            a[i].key == b[i].key &&
            a[i].label == b[i].label &&
            a[i].type == b[i].type &&
            a[i].required == b[i].required &&
            a[i].options.join(' ') == b[i].options.join(' '),
      );

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final notifier = ref.read(eeServicesProvider.notifier);
      // Two calls because they are two endpoints, and in this order because
      // routing is the one that decides whether the service works at all.
      if (!_setEquals(_units, widget.service.unitIds.toSet())) {
        await notifier.setUnits(widget.service.id, _units.toList());
      }
      if (!_fieldsEqual(_fields, widget.service.formFields)) {
        await notifier.setFields(widget.service.id, _fields);
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(eeUnitsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.service.name)),
      body: units.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(message: localizedError(error)),
        data: (list) => ListView(
          padding: const EdgeInsets.all(AwSpace.x4),
          children: [
            Text(
              'ee.team.services.units'.tr(),
              style: theme.textTheme.titleSmall,
            ),
            Text(
              'ee.team.services.unitsHint'.tr(),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AwSpace.x2),
            Card(
              child: Column(
                children: [
                  for (final unit in (list ?? const <EeUnit>[]).where(
                    (u) => !u.archived,
                  ))
                    CheckboxListTile(
                      key: Key('service-unit-${unit.id}'),
                      value: _units.contains(unit.id),
                      title: Text(unit.name),
                      onChanged: _busy
                          ? null
                          : (on) => setState(() {
                              if (on == true) {
                                _units.add(unit.id);
                              } else {
                                _units.remove(unit.id);
                              }
                            }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AwSpace.x6),
            Text(
              'ee.team.services.fields'.tr(),
              style: theme.textTheme.titleSmall,
            ),
            Text(
              'ee.team.services.fieldsHint'.tr(),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AwSpace.x2),
            if (_fields.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AwSpace.x2),
                child: Text(
                  'ee.team.services.fieldsNone'.tr(),
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (final field in _fields)
                      ListTile(
                        key: Key('service-field-${field.key}'),
                        title: Text(field.label),
                        subtitle: Text(
                          [
                            'ee.team.services.fieldType.${field.type}'.tr(),
                            if (field.required)
                              'ee.team.services.fieldRequired'.tr(),
                          ].join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                        trailing: IconButton(
                          key: Key('service-field-remove-${field.key}'),
                          tooltip: 'ee.team.services.fieldRemove'.tr(),
                          icon: const Icon(Icons.close),
                          onPressed: _busy
                              ? null
                              : () => setState(() => _fields.remove(field)),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: AwSpace.x2),
            OutlinedButton.icon(
              key: const Key('service-field-add'),
              onPressed: _busy ? null : _addField,
              icon: const Icon(Icons.add),
              label: Text('ee.team.services.fieldAdd'.tr()),
            ),
            const SizedBox(height: AwSpace.x8),
            FilledButton(
              key: const Key('service-routing-save'),
              onPressed: _busy || !_dirty ? null : _save,
              child: Text('common.save'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addField() async {
    final field = await showDialog<EeServiceField>(
      context: context,
      builder: (ctx) => const _FieldDialog(),
    );
    if (field == null) return;
    // A duplicate key means one answer overwrites another when the form is
    // submitted — the server refuses it, and refusing here costs a round trip
    // less and explains itself at the moment of the mistake.
    if (_fields.any((f) => f.key == field.key)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ee.team.services.fieldDuplicate'.tr())),
      );
      return;
    }
    setState(() => _fields.add(field));
  }
}

class _FieldDialog extends StatefulWidget {
  const _FieldDialog();

  @override
  State<_FieldDialog> createState() => _FieldDialogState();
}

class _FieldDialogState extends State<_FieldDialog> {
  final _key = TextEditingController();
  final _label = TextEditingController();
  final _options = TextEditingController();
  String _type = 'text';
  bool _required = false;

  @override
  void dispose() {
    _key.dispose();
    _label.dispose();
    _options.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('ee.team.services.fieldAdd'.tr()),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('field-label'),
            controller: _label,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'ee.team.services.fieldLabel'.tr(),
            ),
          ),
          TextField(
            key: const Key('field-key'),
            controller: _key,
            decoration: InputDecoration(
              labelText: 'ee.team.services.fieldKey'.tr(),
              helperText: 'ee.team.services.fieldKeyHint'.tr(),
            ),
          ),
          const SizedBox(height: AwSpace.x3),
          DropdownButtonFormField<String>(
            key: const Key('field-type'),
            initialValue: _type,
            decoration: InputDecoration(
              // `fieldType` is a MAP of the five type names, so the picker's
              // own label needs a separate key — a dotted lookup cannot make
              // one name mean both a leaf and a branch.
              labelText: 'ee.team.services.fieldTypeLabel'.tr(),
            ),
            items: [
              for (final type in EeServiceField.types)
                DropdownMenuItem(
                  value: type,
                  child: Text('ee.team.services.fieldType.$type'.tr()),
                ),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'text'),
          ),
          if (_type == 'select')
            TextField(
              key: const Key('field-options'),
              controller: _options,
              decoration: InputDecoration(
                labelText: 'ee.team.services.fieldOptions'.tr(),
                helperText: 'ee.team.services.fieldOptionsHint'.tr(),
              ),
            ),
          SwitchListTile(
            key: const Key('field-required'),
            value: _required,
            title: Text('ee.team.services.fieldRequired'.tr()),
            onChanged: (v) => setState(() => _required = v),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text('common.cancel'.tr()),
      ),
      FilledButton(
        key: const Key('field-save'),
        onPressed: _submit,
        child: Text('common.add'.tr()),
      ),
    ],
  );

  void _submit() {
    final label = _label.text.trim();
    // The key is derived from the label when the admin does not supply one:
    // it is a machine name they should not have to think about, but they may
    // if they are matching an existing export.
    final key = (_key.text.trim().isEmpty ? _slug(label) : _key.text.trim());
    final options = _options.text
        .split(',')
        .map((o) => o.trim())
        .where((o) => o.isNotEmpty)
        .toList();
    if (label.isEmpty || key.isEmpty) return;
    if (_type == 'select' && options.isEmpty) return;
    Navigator.of(context).pop(
      EeServiceField(
        key: key,
        label: label,
        type: _type,
        required: _required,
        options: options,
      ),
    );
  }

  /// Turkish letters fold to ASCII first: `ç→c`, `ı→i`, … A key is `a-z0-9_`
  /// on the server, so a label like "Hat numarası" must not become "hat_numaras".
  static String _slug(String label) {
    const map = {
      'ç': 'c',
      'ğ': 'g',
      'ı': 'i',
      'i̇': 'i',
      'ö': 'o',
      'ş': 's',
      'ü': 'u',
    };
    var out = label.toLowerCase();
    map.forEach((from, to) => out = out.replaceAll(from, to));
    out = out.replaceAll(RegExp('[^a-z0-9]+'), '_');
    out = out.replaceAll(RegExp('^_+|_+\$'), '');
    if (out.isEmpty) return '';
    if (RegExp('^[0-9]').hasMatch(out)) out = 'f_$out';
    return out.length > 32 ? out.substring(0, 32) : out;
  }
}
