import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/sheets.dart';
import '../assets_providers.dart';
import '../data/assets_models.dart';

/// Editing one machine (EE-194).
///
/// ── WHAT IS EDITABLE HERE, AND WHAT IS NOT ─────────────────────────────
///
/// The fields a person standing at the machine actually corrects: what it is
/// called, where it is, and what state it is in. Not the tag — that is the
/// import's matching key and what the printed QR label is stuck to, so
/// changing it is a different act with consequences on a wall somewhere. The
/// server allows it; this sheet does not offer it, and that asymmetry is
/// deliberate rather than an omission.
///
/// Not the purchase cost either. A finance number typed on a phone beside a
/// lathe is a finance number typed by the wrong person.
///
/// ── AND `retired` IS NOT ONE OF THE CHIPS ─────────────────────────────
///
/// Scrapping a machine is terminal — the server refuses every later edit and
/// the tag can never be reused — so it does not belong beside "in
/// maintenance" as one chip among four, where it is one mis-tap away. It
/// stays on the REST surface behind `assets.manage` until somebody designs
/// the confirmation it deserves; that is a decision, and it is written down
/// rather than left as a gap.
const _editableStatuses = ['in_stock', 'in_use', 'maintenance', 'faulty'];

Future<void> editAssetSheet(
  BuildContext context,
  WidgetRef ref,
  EeAsset asset,
) {
  return showAwSheet<void>(context, builder: (_) => _EditSheet(asset: asset));
}

class _EditSheet extends ConsumerStatefulWidget {
  const _EditSheet({required this.asset});
  final EeAsset asset;

  @override
  ConsumerState<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends ConsumerState<_EditSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.asset.name,
  );
  late final TextEditingController _location = TextEditingController(
    text: widget.asset.location ?? '',
  );
  late String _status = widget.asset.status;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(eeAssetsApiProvider);
      final patch = <String, dynamic>{};
      if (_name.text.trim() != widget.asset.name) {
        patch['name'] = _name.text.trim();
      }
      final location = _location.text.trim();
      if (location != (widget.asset.location ?? '')) {
        patch['location'] = location.isEmpty ? null : location;
      }
      if (patch.isNotEmpty) await api.update(widget.asset.id, patch);
      // Its own door, like the server's: moving a machine through its life and
      // correcting what it says are different acts, and the history has to be
      // able to tell them apart.
      if (_status != widget.asset.status) {
        await api.setStatus(widget.asset.id, _status);
      }
      ref.invalidate(eeAssetProvider(widget.asset.id));
      // EE-238: the card reads the device's copy, which the server's write
      // reaches through a pull — asked for now rather than at the next tick,
      // so the card does not show the old name for a minute after "saved".
      unawaited(ref.read(syncEngineProvider)?.syncNow());
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = localizedError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AwSpace.x4,
        right: AwSpace.x4,
        top: AwSpace.x4,
        bottom: MediaQuery.of(context).viewInsets.bottom + AwSpace.x4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.asset.tag,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AwSpace.x4),
          TextField(
            key: const Key('asset-edit-name'),
            controller: _name,
            decoration: InputDecoration(labelText: 'ee.assets.field.name'.tr()),
          ),
          const SizedBox(height: AwSpace.x3),
          TextField(
            key: const Key('asset-edit-location'),
            controller: _location,
            decoration: InputDecoration(
              labelText: 'ee.assets.field.location'.tr(),
            ),
          ),
          const SizedBox(height: AwSpace.x4),
          Wrap(
            spacing: AwSpace.x2,
            children: [
              for (final status in _editableStatuses)
                ChoiceChip(
                  key: Key('asset-edit-status-$status'),
                  label: Text('ee.assets.status.$status'.tr()),
                  selected: _status == status,
                  onSelected: (_) => setState(() => _status = status),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AwSpace.x3),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AwSpace.x4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: Text('common.cancel'.tr()),
              ),
              const SizedBox(width: AwSpace.x2),
              FilledButton(
                key: const Key('asset-edit-save'),
                onPressed: _busy ? null : _save,
                child: Text('common.save'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
