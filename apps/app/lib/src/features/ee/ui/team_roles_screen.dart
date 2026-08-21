import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/team_admin_models.dart';
import '../team_admin_providers.dart';

/// The role list and its grant matrix (EE-053).
///
/// Three rules the layout follows, and each one is a decision the model made
/// visible rather than a style choice:
///
///   • A ROLE SHOWS WHO IS IN IT. "Can I narrow this?" is unanswerable
///     without knowing how many people it would affect, so the count is on
///     the row rather than one screen deeper.
///   • `owner` IS PRESENT AND CLOSED. Hiding the role a team cannot edit
///     would make the list look like a lie next to the members screen; a row
///     that says "always everything" answers the question instead.
///   • THE MATRIX GROUPS BY DOMAIN. Thirty flat checkboxes is a screen nobody
///     reads; `tasks`, `projects`, `notes` are how people already think about
///     what they are granting.
class EeTeamRolesScreen extends ConsumerWidget {
  const EeTeamRolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(eeTeamRolesProvider);
    return Scaffold(
      appBar: AppBar(title: Text('ee.team.roles.title'.tr())),
      floatingActionButton: FloatingActionButton(
        key: const Key('role-new'),
        tooltip: 'ee.team.roles.create'.tr(),
        onPressed: () => _openEditor(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: roles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeTeamRolesProvider),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.all(AwSpace.x4),
          children: [
            Text(
              'ee.team.roles.intro'.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AwSpace.x3),
            for (final role in list)
              Card(
                key: Key('role-${role.key}'),
                child: ListTile(
                  leading: Icon(
                    role.base
                        ? Icons.shield_outlined
                        : Icons.badge_outlined,
                  ),
                  title: Text(_roleName(role)),
                  subtitle: Text(
                    'ee.team.roles.summary'.tr(
                      args: {
                        'grants': '${role.grants.length}',
                        'members': '${role.memberCount}',
                      },
                    ),
                  ),
                  trailing: role.editable
                      ? const Icon(Icons.chevron_right)
                      : Chip(label: Text('ee.team.roles.locked'.tr())),
                  onTap: role.editable
                      ? () => _openEditor(context, ref, role)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// A base role's name is a KEY (`admin`), a custom role's name is what
  /// somebody typed. Translating the first and not the second is the whole
  /// difference between a label and a value.
  static String _roleName(EeRole role) =>
      role.base ? 'ee.team.role.${role.key}'.tr() : role.name;

  void _openEditor(BuildContext context, WidgetRef ref, EeRole? role) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _RoleEditorScreen(role: role),
        fullscreenDialog: role == null,
      ),
    );
  }
}

class _RoleEditorScreen extends ConsumerStatefulWidget {
  const _RoleEditorScreen({this.role});

  /// Null = creating. A base role arrives non-null and un-renameable.
  final EeRole? role;

  @override
  ConsumerState<_RoleEditorScreen> createState() => _RoleEditorScreenState();
}

class _RoleEditorScreenState extends ConsumerState<_RoleEditorScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.role?.base == true ? '' : widget.role?.name ?? '',
  );
  final Set<String> _grants = {};
  String _anchor = 'member';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _anchor = widget.role?.anchor ?? 'member';
    // A new role starts EMPTY rather than pre-ticked with its anchor's
    // defaults: the server fills those in when `grants` is omitted, and
    // pre-ticking them here would silently freeze today's defaults into a
    // role that should keep tracking them (PERMISSIONS.md, EE-048).
    _grants.addAll(widget.role?.grants ?? const []);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _isCreate => widget.role == null;
  bool get _renameable => _isCreate || widget.role?.base == false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final controller = ref.read(eeTeamRolesProvider.notifier);
    try {
      if (_isCreate) {
        await controller.create(
          name: _name.text.trim(),
          anchor: _anchor,
          grants: _grants.toList()..sort(),
        );
      } else {
        await controller.edit(
          widget.role!.key,
          name: _renameable ? _name.text.trim() : null,
          grants: _grants.toList()..sort(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(localizedError(error))));
    }
  }

  Future<void> _delete() async {
    final role = widget.role!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ee.team.roles.deleteTitle'.tr()),
        // The consequence, in the sentence: nobody is locked out, they fall
        // back to the base role the custom one was built on.
        content: Text(
          'ee.team.roles.deleteBody'.tr(
            args: {
              'n': '${role.memberCount}',
              'anchor': 'ee.team.role.${role.anchor}'.tr(),
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(eeTeamRolesProvider.notifier).remove(role.key);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final catalogue = ref.watch(eePermissionCatalogueProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isCreate
              ? 'ee.team.roles.create'.tr()
              : EeTeamRolesScreen._roleName(widget.role!),
        ),
        actions: [
          if (widget.role?.deletable == true)
            IconButton(
              key: const Key('role-delete'),
              tooltip: 'common.delete'.tr(),
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: catalogue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eePermissionCatalogueProvider),
        ),
        data: (defs) => _form(context, defs),
      ),
    );
  }

  Widget _form(BuildContext context, List<EePermissionDef> defs) {
    final byDomain = <String, List<EePermissionDef>>{};
    for (final def in defs) {
      byDomain.putIfAbsent(def.domain, () => []).add(def);
    }
    final domains = byDomain.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(AwSpace.x4),
      children: [
        if (_renameable)
          TextField(
            key: const Key('role-name'),
            controller: _name,
            decoration: InputDecoration(
              labelText: 'ee.team.roles.name'.tr(),
            ),
          ),
        if (_isCreate) ...[
          const SizedBox(height: AwSpace.x3),
          // The anchor is not cosmetic and the helper says why: it decides
          // rank in the team and the role the workspace sees.
          DropdownButtonFormField<String>(
            key: const Key('role-anchor'),
            initialValue: _anchor,
            decoration: InputDecoration(
              labelText: 'ee.team.roles.anchor'.tr(),
              helperText: 'ee.team.roles.anchorHelp'.tr(),
            ),
            items: [
              for (final anchor in ['member', 'admin'])
                DropdownMenuItem(
                  value: anchor,
                  child: Text('ee.team.role.$anchor'.tr()),
                ),
            ],
            onChanged: (v) => setState(() => _anchor = v ?? 'member'),
          ),
        ],
        const SizedBox(height: AwSpace.x4),
        for (final domain in domains) ...[
          Padding(
            padding: const EdgeInsets.only(
              left: AwSpace.x2,
              bottom: AwSpace.x2,
            ),
            child: Text(
              'ee.permDomain.$domain'.tr(),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Card(
            child: Column(
              children: [
                for (final def in byDomain[domain]!)
                  CheckboxListTile(
                    key: Key('grant-${def.id}'),
                    value: _grants.contains(def.id),
                    title: Text(def.label.tr()),
                    subtitle: Text(def.description),
                    onChanged: (on) => setState(() {
                      if (on == true) {
                        _grants.add(def.id);
                      } else {
                        _grants.remove(def.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AwSpace.x3),
        ],
        const SizedBox(height: AwSpace.x2),
        FilledButton(
          key: const Key('role-save'),
          onPressed: _saving ? null : _save,
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}
