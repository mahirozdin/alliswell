import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api_exception.dart';
import '../../../../core/error_messages.dart';
import '../../../../i18n/i18n.dart';
import '../../../../theme/tokens.dart';
import '../../../../widgets/status_views.dart';
import '../admin_providers.dart';
import '../data/admin_models.dart';

/// The package editor (EE-033).
///
/// The form is BUILT FROM THE SERVER'S DICTIONARY rather than a hard-coded
/// list of fields: EE-029's promise is that a new limit type costs a registry
/// entry and a doc line, and a client with the keys baked in would quietly
/// turn that into "…and an app release". Each field also says whether the
/// limit is actually enforced today, because offering a ceiling nothing
/// applies would be selling a promise the code does not keep.
class AdminPackagesScreen extends ConsumerWidget {
  const AdminPackagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packages = ref.watch(adminPackagesProvider);
    final keys = ref.watch(adminLimitKeysProvider);

    if (packages.isLoading || keys.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = packages.error ?? keys.error;
    if (error != null) {
      return AwErrorState(
        message: localizedError(error),
        onRetry: () {
          ref.invalidate(adminPackagesProvider);
          ref.invalidate(adminLimitKeysProvider);
        },
      );
    }

    final rows = packages.value ?? const <AdminPackage>[];
    final dictionary = keys.value ?? const <LimitKeyInfo>[];
    return ListView(
      padding: const EdgeInsets.all(AwSpace.x4),
      children: [
        for (final row in rows)
          Card(
            margin: const EdgeInsets.only(bottom: AwSpace.x3),
            child: ExpansionTile(
              title: Row(
                children: [
                  Expanded(child: Text(row.name)),
                  if (row.isDefault)
                    Padding(
                      padding: const EdgeInsets.only(left: AwSpace.x2),
                      child: Chip(
                        label: Text('ee.admin.packages.default'.tr()),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
              subtitle: Text(
                'ee.admin.packages.limitCount'.tr(
                  args: {'n': '${row.limits.length}'},
                ),
              ),
              children: [_PackageForm(package: row, dictionary: dictionary)],
            ),
          ),
      ],
    );
  }
}

class _PackageForm extends ConsumerStatefulWidget {
  const _PackageForm({required this.package, required this.dictionary});

  final AdminPackage package;
  final List<LimitKeyInfo> dictionary;

  @override
  ConsumerState<_PackageForm> createState() => _PackageFormState();
}

class _PackageFormState extends ConsumerState<_PackageForm> {
  late final Map<String, TextEditingController> _fields = {
    for (final info in widget.dictionary)
      info.key: TextEditingController(
        text: widget.package.limits.containsKey(info.key)
            ? (widget.package.limits[info.key]?.toString() ?? '')
            : '',
      ),
  };
  bool _busy = false;

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Empty means "this package does not speak about that limit" and is left
  /// OUT; the word "unlimited" means an explicit `null`. EE-029 keeps the two
  /// apart in storage, so the form has to keep them apart too.
  Map<String, int?> _collect() {
    final limits = <String, int?>{};
    for (final entry in _fields.entries) {
      final raw = entry.value.text.trim();
      if (raw.isEmpty) continue;
      if (raw == '-' || raw.toLowerCase() == 'unlimited') {
        limits[entry.key] = null;
        continue;
      }
      final value = int.tryParse(raw);
      if (value != null) limits[entry.key] = value;
    }
    return limits;
  }

  Future<void> _save() async {
    if (_busy) return;
    final token = ref.read(adminSessionProvider).value?.accessToken;
    if (token == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(adminApiProvider)
          .savePackage(
            token,
            id: widget.package.id,
            name: widget.package.name,
            limits: _collect(),
          );
      ref.invalidate(adminPackagesProvider);
      ref.invalidate(adminUsageProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('ee.admin.packages.saved'.tr())),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(localizedError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AwSpace.x4, 0, AwSpace.x4, AwSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ee.admin.packages.help'.tr(), style: theme.textTheme.bodySmall),
          const SizedBox(height: AwSpace.x3),
          for (final info in widget.dictionary)
            Padding(
              padding: const EdgeInsets.only(bottom: AwSpace.x3),
              child: TextField(
                controller: _fields[info.key],
                keyboardType: TextInputType.text,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                ],
                decoration: InputDecoration(
                  labelText: 'ee.admin.limit.${info.key}'.tr(),
                  suffixText: info.unit,
                  helperText: info.enforced
                      ? null
                      // Said out loud rather than implied: this number is
                      // stored and shown, and nothing enforces it yet.
                      : 'ee.admin.packages.notEnforced'.tr(),
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: Text('common.save'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}
