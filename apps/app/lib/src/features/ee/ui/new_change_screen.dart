import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/date_format.dart';
import '../../../core/date_input.dart';
import '../../../core/error_messages.dart';
import '../../../core/persisted_prefs.dart';
import '../../../core/reachability.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../changes_providers.dart';
import '../data/changes_models.dart';
import '../services_providers.dart';
import 'change_detail_screen.dart';

/// Raising a change from the phone (EE-269 box 4, EE-279).
///
/// ── AS MUCH AS THE REST DOOR TAKES, AND NOTHING IT DOES NOT ────────────
///
/// Every field here is one `POST /changes` accepts, with the same two
/// refusals said before the button rather than after it: no impact, no way
/// back. A change raised from a request carries the request (EE-279) and is
/// filed in its desk; any other is filed in the desk on screen, so it appears
/// in the list this person just left.
///
/// ── ONLINE, AND THE BUTTON SAYS SO ─────────────────────────────────────
///
/// Changes are read-only on devices (EE-186: there is no local authoring,
/// because a plan queued offline could be scheduled into a window that has
/// since been frozen). With no signal the button is grey and the sentence
/// under it says why — the house rule for every write that needs the server.
class EeNewChangeScreen extends ConsumerStatefulWidget {
  const EeNewChangeScreen({super.key, this.source});

  /// The request this is raised from, or null.
  final EeChangeSource? source;

  @override
  ConsumerState<EeNewChangeScreen> createState() => _EeNewChangeScreenState();
}

class _EeNewChangeScreenState extends ConsumerState<EeNewChangeScreen> {
  late final TextEditingController _title;
  final _impact = TextEditingController();
  final _rollback = TextEditingController();
  final _description = TextEditingController();
  String _type = 'normal';
  String _risk = 'medium';
  DateTime? _start;
  DateTime? _end;
  final Set<String> _services = {};
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    // From a request, its subject is the first draft of the title: the
    // person is usually writing "fix what this request is about".
    _title = TextEditingController(text: widget.source?.subject ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _impact.dispose();
    _rollback.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _windowBackwards =>
      _start != null && _end != null && !_end!.isAfter(_start!);

  bool get _complete =>
      _title.text.trim().isNotEmpty &&
      _impact.text.trim().isNotEmpty &&
      _rollback.text.trim().isNotEmpty &&
      !_windowBackwards;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(eeChangeActionsProvider)
          .create(
            title: _title.text.trim(),
            type: _type,
            risk: _risk,
            impact: _impact.text.trim(),
            rollbackPlan: _rollback.text.trim(),
            description: _description.text.trim(),
            windowStart: _start,
            windowEnd: _end,
            serviceIds: _services.toList()..sort(),
            source: widget.source,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ee.changes.create.done'.tr())));
      // Straight to what was raised: the next thing somebody does with a new
      // change is read it back, or send it for a signature.
      if (GoRouter.maybeOf(context) != null) {
        context.pushReplacement('/changes/${created.id}');
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => EeChangeDetailScreen(changeId: created.id),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offline = ref.watch(
      serverReachabilityProvider.select((up) => up == false),
    );
    final format = ref.watch(dateFormatProvider);
    final services = [
      for (final s in ref.watch(eeServicesProvider).value ?? const [])
        if (!s.archived) s,
    ];
    final source = widget.source;

    return Scaffold(
      appBar: AppBar(title: Text('ee.changes.create.title'.tr())),
      body: ListView(
        padding: awListPadding(context, top: AwSpace.x4),
        children: [
          if (source != null) ...[
            Row(
              key: const Key('change-new-source'),
              children: [
                const Icon(Icons.support_agent, size: 20),
                const SizedBox(width: AwSpace.x2),
                Expanded(
                  child: Text(
                    'ee.changes.create.fromTicket'.tr(
                      args: {
                        'ticket': [
                          if (source.number != null) '#${source.number}',
                          source.subject,
                        ].join(' · '),
                      },
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AwSpace.x4),
          ],
          TextField(
            key: const Key('change-new-title'),
            controller: _title,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: 'ee.changes.create.name'.tr(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AwSpace.x2),
          Text(
            'ee.changes.create.type'.tr(),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AwSpace.x2),
          SegmentedButton<String>(
            key: const Key('change-new-type'),
            segments: [
              for (final t in const ['standard', 'normal', 'emergency'])
                ButtonSegment(value: t, label: Text('ee.changes.type.$t'.tr())),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() => _type = v.first),
          ),
          const SizedBox(height: AwSpace.x1),
          // What the choice MEANS, under it: the difference between normal
          // and standard is a signature, and the person choosing should not
          // have to know ITIL to know that.
          Text(
            'ee.changes.create.typeHint.$_type'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AwSpace.x4),
          Text(
            'ee.changes.create.risk'.tr(),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AwSpace.x2),
          SegmentedButton<String>(
            key: const Key('change-new-risk'),
            segments: [
              for (final r in const ['low', 'medium', 'high'])
                ButtonSegment(
                  value: r,
                  label: Text('ee.changes.riskShort.$r'.tr()),
                ),
            ],
            selected: {_risk},
            onSelectionChanged: (v) => setState(() => _risk = v.first),
          ),
          const SizedBox(height: AwSpace.x4),
          TextField(
            key: const Key('change-new-impact'),
            controller: _impact,
            minLines: 2,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: 'ee.changes.create.impact'.tr(),
              helperText: 'ee.changes.create.impactHelp'.tr(),
              helperMaxLines: 2,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AwSpace.x3),
          TextField(
            key: const Key('change-new-rollback'),
            controller: _rollback,
            minLines: 2,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: 'ee.changes.create.rollback'.tr(),
              helperText: 'ee.changes.create.rollbackHelp'.tr(),
              helperMaxLines: 2,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AwSpace.x4),
          _WindowField(
            fieldKey: const Key('change-new-start'),
            label: 'ee.changes.create.windowStart'.tr(),
            value: _start,
            format: format,
            onPick: () async {
              final picked = await awPickDateTime(
                context,
                ref,
                current: _start,
              );
              if (picked != null) setState(() => _start = picked);
            },
            onClear: () => setState(() => _start = null),
          ),
          _WindowField(
            fieldKey: const Key('change-new-end'),
            label: 'ee.changes.create.windowEnd'.tr(),
            value: _end,
            format: format,
            onPick: () async {
              final picked = await awPickDateTime(
                context,
                ref,
                current: _end,
                anchor: _start,
              );
              if (picked != null) setState(() => _end = picked);
            },
            onClear: () => setState(() => _end = null),
          ),
          if (_windowBackwards)
            Padding(
              padding: const EdgeInsets.only(top: AwSpace.x2),
              child: AwInlineError(
                textKey: const Key('change-new-backwards'),
                message: 'ee.changes.create.windowBackwards'.tr(),
              ),
            ),
          if (services.isNotEmpty) ...[
            const SizedBox(height: AwSpace.x4),
            Text(
              'ee.changes.create.services'.tr(),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AwSpace.x1),
            Text(
              'ee.changes.create.servicesHint'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AwSpace.x2),
            Wrap(
              spacing: AwSpace.x2,
              runSpacing: AwSpace.x1,
              children: [
                for (final service in services)
                  FilterChip(
                    key: Key('change-new-service-${service.id}'),
                    label: Text(service.name),
                    selected: _services.contains(service.id),
                    onSelected: (on) => setState(
                      () => on
                          ? _services.add(service.id)
                          : _services.remove(service.id),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AwSpace.x4),
          TextField(
            key: const Key('change-new-description'),
            controller: _description,
            minLines: 2,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: 'ee.changes.create.description'.tr(),
            ),
          ),
          const SizedBox(height: AwSpace.x4),
          if (_error != null) ...[
            AwInlineError(
              textKey: const Key('change-new-error'),
              message: localizedError(_error!),
            ),
            const SizedBox(height: AwSpace.x3),
          ],
          FilledButton(
            key: const Key('change-new-save'),
            onPressed: _complete && !_saving && !offline ? _save : null,
            child: Text('ee.changes.create.save'.tr()),
          ),
          if (offline)
            Padding(
              key: const Key('change-new-offline'),
              padding: const EdgeInsets.only(top: AwSpace.x2),
              child: Text(
                'ee.changes.create.offline'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One end of the window: the value, a way to pick it, a way to clear it.
class _WindowField extends StatelessWidget {
  const _WindowField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.format,
    required this.onPick,
    required this.onClear,
  });

  final Key fieldKey;
  final String label;
  final DateTime? value;
  final String format;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return ListTile(
      key: fieldKey,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.schedule),
      title: Text(label),
      subtitle: Text(
        v == null
            ? 'ee.changes.create.windowNone'.tr()
            : awFormatDateTime(v, format: format),
      ),
      onTap: onPick,
      trailing: v == null
          ? null
          : IconButton(
              tooltip: 'ee.changes.create.windowClear'.tr(),
              icon: const Icon(Icons.close),
              onPressed: onClear,
            ),
    );
  }
}
