import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/search_field.dart';
import '../../../widgets/status_views.dart';
import '../catalogue_search.dart';
import '../data/services_models.dart';
import '../data/units_models.dart';
import '../services_providers.dart';
import '../team_admin_providers.dart';
import '../units_providers.dart';
import 'form_designer_screen.dart';
import 'service_categories_screen.dart';
import 'service_icons.dart';

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
///
/// EE-228 puts the catalogue ON ITS SHELVES here as well: top shelves with
/// their sub-shelves (two levels, EE-212), the services under each, and the
/// unshelved ones last — the same order the requester's picker uses, so the
/// admin arranges exactly what the requester will see. The search filters in
/// memory with the device's fold (`catalogueMatches`, shared with the
/// picker), and matches a service by its shelf's name too.
class EeTeamServicesScreen extends ConsumerStatefulWidget {
  const EeTeamServicesScreen({super.key});

  @override
  ConsumerState<EeTeamServicesScreen> createState() =>
      _EeTeamServicesScreenState();

  /// Null service = creating one. The same sheet either way: naming a service
  /// and renaming one are the same act with a different starting value.
  static Future<void> editService(
    BuildContext context,
    WidgetRef ref,
    EeService? service,
  ) => _editService(context, ref, service);
}

class _EeTeamServicesScreenState extends ConsumerState<EeTeamServicesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(eeServicesProvider);
    final shelves =
        ref.watch(eeServiceCategoriesProvider).value ??
        const <EeServiceCategory>[];

    return Scaffold(
      appBar: AppBar(
        title: Text('ee.team.services.title'.tr()),
        actions: [
          AwSearchAction(
            fieldKey: const Key('service-search'),
            hintText: 'ee.team.services.search'.tr(),
            onQuery: (q) => setState(() => _query = q),
          ),
          IconButton(
            key: const Key('service-shelves'),
            tooltip: 'ee.team.services.shelves.title'.tr(),
            icon: const Icon(Icons.account_tree_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const EeServiceCategoriesScreen(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('service-new'),
        tooltip: 'ee.team.services.create'.tr(),
        onPressed: () => _editService(context, ref, null),
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
          return _CatalogueTree(
            services: list,
            shelves: shelves,
            query: _query,
          );
        },
      ),
    );
  }
}

Future<void> _editService(
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

/// The catalogue on its shelves, or the search's answer on them.
class _CatalogueTree extends StatelessWidget {
  const _CatalogueTree({
    required this.services,
    required this.shelves,
    required this.query,
  });

  final List<EeService> services;
  final List<EeServiceCategory> shelves;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byId = {for (final shelf in shelves) shelf.id: shelf};
    final searching = query.trim().isNotEmpty;
    // A service matches by its own words AND its shelf's: "elektrik" should
    // find everything on the Elektrik shelf, which is how people think of it.
    bool matches(EeService service) {
      final shelf = byId[service.categoryId];
      return catalogueMatches(query, [
        service.name,
        service.description,
        shelf?.name,
        byId[shelf?.parentId]?.name,
      ]);
    }

    final byShelf = <String?, List<EeService>>{};
    for (final service in services.where(matches)) {
      final shelf = byId.containsKey(service.categoryId)
          ? service.categoryId
          : null;
      (byShelf[shelf] ??= []).add(service);
    }
    final tree = shelfTree(shelves);
    Widget quiet(String text, Key key, {bool indent = false}) => Padding(
      key: key,
      padding: EdgeInsetsDirectional.only(
        start: indent ? AwSpace.x6 : 0,
        bottom: AwSpace.x2,
      ),
      child: Text(text, style: theme.textTheme.bodySmall),
    );

    final children = <Widget>[
      Text('ee.team.services.intro'.tr(), style: theme.textTheme.bodySmall),
      const SizedBox(height: AwSpace.x3),
    ];
    for (final (root, subs) in tree) {
      final direct = byShelf[root.id] ?? const <EeService>[];
      final subsWithHits = [
        for (final sub in subs)
          if (!searching || (byShelf[sub.id]?.isNotEmpty ?? false)) sub,
      ];
      if (searching && direct.isEmpty && subsWithHits.isEmpty) continue;
      children.add(_ShelfHeading(shelf: root));
      if (!searching && direct.isEmpty && subs.isEmpty) {
        children.add(
          quiet(
            'ee.team.services.shelfEmpty'.tr(),
            Key('shelf-empty-${root.id}'),
          ),
        );
      }
      for (final service in direct) {
        children.add(_ServiceCard(service: service));
      }
      for (final sub in subsWithHits) {
        final hits = byShelf[sub.id] ?? const <EeService>[];
        children.add(_ShelfHeading(shelf: sub));
        if (hits.isEmpty) {
          children.add(
            quiet(
              'ee.team.services.shelfEmpty'.tr(),
              Key('shelf-empty-${sub.id}'),
              indent: true,
            ),
          );
        }
        for (final service in hits) {
          children.add(_ServiceCard(service: service, indent: true));
        }
      }
    }
    final unshelved = byShelf[null] ?? const <EeService>[];
    if (unshelved.isNotEmpty) {
      // Named only when there are shelves to tell them apart from — the
      // requester's picker says "Other" under the same condition.
      if (tree.isNotEmpty) {
        children.add(
          Padding(
            key: const Key('shelf-none'),
            padding: const EdgeInsets.only(top: AwSpace.x4, bottom: AwSpace.x1),
            child: Text(
              'ee.team.services.unshelved'.tr(),
              style: theme.textTheme.titleSmall,
            ),
          ),
        );
      }
      for (final service in unshelved) {
        children.add(_ServiceCard(service: service));
      }
    }
    if (searching && byShelf.isEmpty) {
      children.add(
        quiet(
          'ee.team.services.searchEmpty'.tr(),
          const Key('service-search-empty'),
        ),
      );
    }
    return ListView(
      padding: awListPadding(context, top: AwSpace.x4, extraBottom: 72),
      children: children,
    );
  }
}

class _ShelfHeading extends StatelessWidget {
  const _ShelfHeading({required this.shelf});

  final EeServiceCategory shelf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sub = !shelf.isRoot;
    return Padding(
      key: Key('shelf-${shelf.id}'),
      padding: EdgeInsetsDirectional.only(
        start: sub ? AwSpace.x6 : 0,
        top: sub ? AwSpace.x2 : AwSpace.x4,
        bottom: AwSpace.x1,
      ),
      child: Row(
        children: [
          Icon(
            serviceIconData(shelf.icon),
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AwSpace.x2),
          Expanded(
            child: Text(
              shelf.name,
              style: sub
                  ? theme.textTheme.labelLarge
                  : theme.textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends ConsumerWidget {
  const _ServiceCard({required this.service, this.indent = false});

  final EeService service;

  /// On a sub-shelf: set in under its heading.
  final bool indent;

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
      margin: EdgeInsetsDirectional.only(
        start: indent ? AwSpace.x6 : 0,
        bottom: AwSpace.x2,
      ),
      child: ListTile(
        leading: Icon(
          // EE-228: the icon the requester will see — archived still reads
          // as retired rather than as its old self.
          service.archived
              ? Icons.inventory_2_outlined
              : serviceIconData(service.icon),
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
                await _editService(context, ref, service);
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
///
/// EE-229 moved the form itself to its own screen: a form is PUBLISHED as a
/// version, while everything else here is saved, and one button doing both
/// would mint a form version every time somebody changed an icon. This page
/// keeps the form's summary and the door to the designer.
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
  // EE-228: the shelf, the icon and EE-185's approval rule.
  late String? _shelf = widget.service.categoryId;
  late String? _icon = widget.service.icon;
  late String _mode = widget.service.approvalMode;
  // EE-268: incident or request.
  late String _processType = widget.service.processType;
  late String? _roleKey = widget.service.approverRoleKey;
  late final Set<String> _approvers = widget.service.approverUserIds.toSet();
  bool _busy = false;
  String? _error;

  bool get _dirty =>
      !_setEquals(_units, widget.service.unitIds.toSet()) ||
      _shelf != widget.service.categoryId ||
      _icon != widget.service.icon ||
      _processType != widget.service.processType ||
      _approvalChanged;

  /// The rule as the server will hold it: a role only where the mode reads
  /// one, people only for `users`. Compared in this form so switching modes
  /// and back is not a change.
  static (String, String?, Set<String>) _rule(
    String mode,
    String? roleKey,
    Set<String> approvers,
  ) => (
    mode,
    mode == 'manager' || mode == 'role' ? roleKey : null,
    mode == 'users' ? approvers : const {},
  );

  bool get _approvalChanged {
    final before = _rule(
      widget.service.approvalMode,
      widget.service.approverRoleKey,
      widget.service.approverUserIds.toSet(),
    );
    final now = _rule(_mode, _roleKey, _approvers);
    return before.$1 != now.$1 ||
        before.$2 != now.$2 ||
        !_setEquals(before.$3, now.$3);
  }

  /// A rule nobody could answer is a lock (EE-185): the save waits for the
  /// piece the mode needs, and the section says which.
  bool get _ruleComplete => switch (_mode) {
    'manager' || 'role' => _roleKey != null,
    'users' => _approvers.isNotEmpty,
    _ => true,
  };

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = widget.service;
    // One PATCH with exactly what changed. An approval rule nobody touched is
    // NOT in it, so the server leaves it as it was (EE-185's merge); when it
    // was touched, all three parts go, because the rule is checked whole.
    final patch = <String, Object?>{
      if (_icon != service.icon) 'icon': _icon,
      if (_processType != service.processType) 'processType': _processType,
      if (_approvalChanged) ...{
        'approvalMode': _mode,
        'approverRoleKey': _mode == 'manager' || _mode == 'role'
            ? _roleKey
            : null,
        'approverUserIds': _mode == 'users'
            ? _approvers.toList()
            : const <String>[],
      },
    };
    await ref
        .read(eeServicesProvider.notifier)
        .saveSetup(
          service.id,
          units: _setEquals(_units, service.unitIds.toSet())
              ? null
              : _units.toList(),
          moveShelf: _shelf != service.categoryId,
          categoryId: _shelf,
          patch: patch,
        );
    if (!mounted) return;
    final after = ref.read(eeServicesProvider);
    if (after.hasError) {
      // The server's refusal, on the screen that asked — and the list is
      // asked again so the catalogue behind it shows what is true.
      setState(() {
        _busy = false;
        _error = localizedError(after.error);
      });
      ref.invalidate(eeServicesProvider);
      return;
    }
    Navigator.of(context).pop();
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
            ..._shelfAndIcon(context),
            const SizedBox(height: AwSpace.x6),
            ..._processTypeSection(context),
            const SizedBox(height: AwSpace.x6),
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
            ..._approval(context),
            const SizedBox(height: AwSpace.x6),
            ..._form(context),
            if (_error != null) ...[
              const SizedBox(height: AwSpace.x4),
              AwInlineError(
                message: _error!,
                textKey: const Key('service-setup-error'),
              ),
            ],
            const SizedBox(height: AwSpace.x8),
            FilledButton(
              key: const Key('service-routing-save'),
              onPressed: _busy || !_dirty || !_ruleComplete ? null : _save,
              child: Text('common.save'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  /// EE-268 (AW-E21): what kind of work a request filed here is. A request
  /// copies the answer when it is opened, so the hint says the one thing a
  /// person changing it needs to know: past work does not move.
  List<Widget> _processTypeSection(BuildContext context) {
    final theme = Theme.of(context);
    return [
      Text(
        'ee.team.services.processType.title'.tr(),
        style: theme.textTheme.titleSmall,
      ),
      Text(
        'ee.team.services.processType.hint'.tr(),
        style: theme.textTheme.bodySmall,
      ),
      RadioGroup<String>(
        groupValue: _processType,
        onChanged: (type) {
          if (!_busy && type != null) setState(() => _processType = type);
        },
        child: Column(
          children: [
            for (final type in const ['incident', 'request'])
              RadioListTile<String>(
                key: Key('service-process-type-$type'),
                contentPadding: EdgeInsets.zero,
                value: type,
                title: Text('ee.team.services.processType.$type'.tr()),
                subtitle: Text('ee.team.services.processType.${type}Hint'.tr()),
              ),
          ],
        ),
      ),
    ];
  }

  /// The form's summary and the door to its designer (EE-229).
  ///
  /// Read from the LIST, not from `widget.service`: that is the snapshot this
  /// page opened with, and a version published in the designer a moment ago
  /// is not in it.
  List<Widget> _form(BuildContext context) {
    final theme = Theme.of(context);
    final service =
        ref
            .watch(eeServicesProvider)
            .value
            ?.where((s) => s.id == widget.service.id)
            .firstOrNull ??
        widget.service;
    return [
      Text('ee.team.services.fields'.tr(), style: theme.textTheme.titleSmall),
      Text(
        'ee.team.services.fieldsHint'.tr(),
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: AwSpace.x2),
      Text(
        service.formFields.isEmpty
            ? 'ee.team.services.designer.summaryNone'.tr()
            // Version 0 with questions: a form from before EE-214, live and
            // not yet numbered — "version 0" would read as a bug.
            : service.formVersion == 0
            ? 'ee.team.services.designer.summaryUnnumbered'.tr(
                args: {'count': '${service.formFields.length}'},
              )
            : 'ee.team.services.designer.summary'.tr(
                args: {
                  'count': '${service.formFields.length}',
                  'version': '${service.formVersion}',
                },
              ),
        key: const Key('service-form-summary'),
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: AwSpace.x2),
      OutlinedButton.icon(
        key: const Key('service-form-design'),
        onPressed: _busy
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EeFormDesignerScreen(service: service),
                ),
              ),
        icon: const Icon(Icons.dynamic_form_outlined),
        label: Text('ee.team.services.designer.open'.tr()),
      ),
    ];
  }

  /// The shelf and the icon (EE-212's two catalogue fields).
  List<Widget> _shelfAndIcon(BuildContext context) {
    final theme = Theme.of(context);
    final shelves =
        ref.watch(eeServiceCategoriesProvider).value ??
        const <EeServiceCategory>[];
    final tree = shelfTree(shelves);
    final known = {for (final shelf in shelves) shelf.id};
    return [
      DropdownButtonFormField<String?>(
        key: const Key('service-shelf'),
        // A shelf that no longer exists reads as "none" rather than asserting
        // on a value the list does not hold.
        initialValue: known.contains(_shelf) ? _shelf : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: 'ee.team.services.shelf'.tr()),
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text('ee.team.services.shelfNone'.tr()),
          ),
          for (final (root, subs) in tree) ...[
            DropdownMenuItem<String?>(
              key: Key('service-shelf-${root.id}'),
              value: root.id,
              child: Text(root.name),
            ),
            for (final sub in subs)
              DropdownMenuItem<String?>(
                key: Key('service-shelf-${sub.id}'),
                value: sub.id,
                child: Text('${root.name} › ${sub.name}'),
              ),
          ],
        ],
        onChanged: _busy ? null : (id) => setState(() => _shelf = id),
      ),
      const SizedBox(height: AwSpace.x4),
      Text('ee.team.services.icon'.tr(), style: theme.textTheme.titleSmall),
      Text('ee.team.services.iconHint'.tr(), style: theme.textTheme.bodySmall),
      const SizedBox(height: AwSpace.x1),
      EeIconPicker(
        value: _icon,
        keyPrefix: 'service-icon',
        onChanged: _busy ? null : (token) => setState(() => _icon = token),
      ),
    ];
  }

  /// EE-185's rule, which until now could only be set through the API.
  List<Widget> _approval(BuildContext context) {
    final theme = Theme.of(context);
    final roles = ref.watch(eeTeamRolesProvider).value ?? const [];
    final members = [
      for (final member in ref.watch(eeTeamRosterProvider).value?.members ?? [])
        if (member.active) member,
    ];
    final needsRole = _mode == 'manager' || _mode == 'role';
    return [
      Text(
        'ee.team.services.approval.title'.tr(),
        style: theme.textTheme.titleSmall,
      ),
      Text(
        'ee.team.services.approval.hint'.tr(),
        style: theme.textTheme.bodySmall,
      ),
      RadioGroup<String>(
        groupValue: _mode,
        onChanged: (mode) {
          if (!_busy && mode != null) setState(() => _mode = mode);
        },
        child: Column(
          children: [
            for (final mode in kServiceApprovalModes)
              RadioListTile<String>(
                key: Key('service-approval-$mode'),
                contentPadding: EdgeInsets.zero,
                value: mode,
                title: Text('ee.team.services.approval.$mode'.tr()),
              ),
          ],
        ),
      ),
      if (needsRole)
        DropdownButtonFormField<String>(
          key: const Key('service-approval-role'),
          initialValue: roles.any((r) => r.key == _roleKey) ? _roleKey : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText:
                (_mode == 'manager'
                        ? 'ee.team.services.approval.fallbackLabel'
                        : 'ee.team.services.approval.roleLabel')
                    .tr(),
            helperText: _mode == 'manager'
                ? 'ee.team.services.approval.managerHint'.tr()
                : null,
            helperMaxLines: 3,
          ),
          items: [
            for (final role in roles)
              DropdownMenuItem<String>(
                key: Key('service-approval-role-${role.key}'),
                value: role.key,
                child: Text(role.name),
              ),
          ],
          onChanged: _busy ? null : (key) => setState(() => _roleKey = key),
        ),
      if (_mode == 'users')
        Card(
          child: Column(
            children: [
              for (final member in members)
                CheckboxListTile(
                  key: Key('service-approver-${member.userId}'),
                  value: _approvers.contains(member.userId),
                  title: Text(member.label),
                  onChanged: _busy
                      ? null
                      : (on) => setState(() {
                          if (on == true) {
                            _approvers.add(member.userId);
                          } else {
                            _approvers.remove(member.userId);
                          }
                        }),
                ),
            ],
          ),
        ),
      if (!_ruleComplete)
        Padding(
          padding: const EdgeInsets.only(top: AwSpace.x2),
          child: Text(
            (needsRole
                    ? 'ee.team.services.approval.incompleteRole'
                    : 'ee.team.services.approval.incompleteUsers')
                .tr(),
            key: const Key('service-approval-incomplete'),
            style: theme.textTheme.bodySmall,
          ),
        ),
    ];
  }
}
