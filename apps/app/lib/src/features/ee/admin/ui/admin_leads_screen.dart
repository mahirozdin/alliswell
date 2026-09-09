import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error_messages.dart';
import '../../../../i18n/i18n.dart';
import '../../../../theme/tokens.dart';
import '../../../../widgets/status_views.dart';
import '../admin_providers.dart';
import '../data/admin_models.dart';

/// The sales inbox (EE-160).
///
/// Plain like the rest of the console (`admin_shell.dart`): this is an operator
/// tool and it should look like the thing it is. The one place it says more
/// than a list would is the erasure — see `_ErasedNotice`.
class AdminLeadsScreen extends ConsumerWidget {
  const AdminLeadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(adminLeadsProvider);
    final controller = ref.read(adminLeadsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusFilter(
          selected: controller.status,
          onSelected: controller.filter,
        ),
        Expanded(
          child: switch (leads) {
            AsyncLoading() => const Center(child: CircularProgressIndicator()),
            AsyncError(:final error) => AwErrorState(
              message: localizedError(error),
              onRetry: controller.reload,
            ),
            AsyncValue(:final value?) when value.items.isEmpty => AwEmptyState(
              icon: Icons.inbox_outlined,
              title: 'ee.admin.leads.empty'.tr(),
              message: 'ee.admin.leads.emptyHelp'.tr(),
            ),
            AsyncValue(:final value?) => ListView.builder(
              padding: const EdgeInsets.all(AwSpace.x4),
              // One extra row for the "load more" control, and only when the
              // server said there IS more. `nextCursor == null` is the end.
              itemCount:
                  value.items.length + (value.nextCursor == null ? 0 : 1),
              itemBuilder: (context, i) {
                if (i == value.items.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: AwSpace.x2),
                    child: OutlinedButton(
                      key: const Key('admin-leads-more'),
                      onPressed: controller.loadMore,
                      child: Text('ee.admin.leads.loadMore'.tr()),
                    ),
                  );
                }
                return _LeadRow(lead: value.items[i]);
              },
            ),
          },
        ),
      ],
    );
  }
}

class _StatusFilter extends StatelessWidget {
  const _StatusFilter({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AwSpace.x4,
        vertical: AwSpace.x2,
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AwSpace.x2),
            child: ChoiceChip(
              label: Text('ee.admin.leads.filterAll'.tr()),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final status in kAdminLeadStatuses)
            Padding(
              padding: const EdgeInsets.only(right: AwSpace.x2),
              child: ChoiceChip(
                label: Text('ee.admin.leads.status.$status'.tr()),
                selected: selected == status,
                onSelected: (_) => onSelected(status),
              ),
            ),
        ],
      ),
    );
  }
}

/// The server stores an ISO instant; the console shows the date part. A
/// wrong-looking clock is worse than a coarse one, and the operator's question
/// here is "when did this arrive", not "at what second".
///
/// Top-level rather than a method on the detail state, and that is not tidying:
/// while it lived inside the state the erasure notice could not reach it, so the
/// one line on that screen that is NOT a field — the sentence explaining the
/// blanks — printed a raw `2026-09-09T08:00:00.000Z` next to four formatted
/// dates. No test saw it; opening the golden did.
String? _date(String? iso) {
  if (iso == null) return null;
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  final local = parsed.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

class _LeadRow extends StatelessWidget {
  const _LeadRow({required this.lead});

  final AdminLead lead;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AwSpace.x2),
      child: ListTile(
        key: Key('admin-lead-${lead.id}'),
        // An erased row keeps its place in the list. Removing it would make
        // the funnel's own numbers move when somebody exercises a right, and
        // that is precisely what EE-156 shaped the table to prevent.
        title: Text(
          lead.erased
              ? 'ee.admin.leads.erasedRow'.tr()
              : (lead.companyName ?? 'ee.admin.leads.notStated'.tr()),
          style: lead.erased
              ? text.bodyLarge?.copyWith(fontStyle: FontStyle.italic)
              : null,
        ),
        subtitle: Text(
          lead.erased
              ? 'ee.admin.leads.status.${lead.status}'.tr()
              : [
                  'ee.admin.leads.status.${lead.status}'.tr(),
                  if (lead.seatCount != null)
                    'ee.admin.leads.seatsShort'.tr(
                      args: {'count': '${lead.seatCount}'},
                    ),
                  if (lead.packageInterest != null) lead.packageInterest!,
                ].join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go('/admin/leads/${lead.id}'),
      ),
    );
  }
}

/// One enquiry, and everything an operator needs to answer it.
class AdminLeadDetailScreen extends ConsumerStatefulWidget {
  const AdminLeadDetailScreen({super.key, required this.leadId});

  final String leadId;

  @override
  ConsumerState<AdminLeadDetailScreen> createState() =>
      _AdminLeadDetailScreenState();
}

class _AdminLeadDetailScreenState extends ConsumerState<AdminLeadDetailScreen> {
  final _notes = TextEditingController();
  String? _status;
  bool _busy = false;
  String? _error;
  bool _loaded = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lead = ref.watch(adminLeadProvider(widget.leadId));

    return switch (lead) {
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncError(:final error) => AwErrorState(
        message: localizedError(error),
        onRetry: () => ref.invalidate(adminLeadProvider(widget.leadId)),
      ),
      AsyncValue(:final value?) => _body(context, value),
    };
  }

  Widget _body(BuildContext context, AdminLead lead) {
    // Seed the editable fields once, so a rebuild while somebody is typing
    // does not throw their words away.
    if (!_loaded) {
      _loaded = true;
      _status = lead.status;
      _notes.text = lead.notes ?? '';
    }
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(AwSpace.x4),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'ee.admin.leads.back'.tr(),
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/admin/leads'),
            ),
            Expanded(
              child: Text(
                lead.erased
                    ? 'ee.admin.leads.erasedRow'.tr()
                    : (lead.companyName ?? 'ee.admin.leads.notStated'.tr()),
                style: text.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: AwSpace.x3),

        if (lead.erased) _ErasedNotice(at: lead.erasedAt),

        // ── What they asked for. Present whether or not the row was erased:
        // these are facts about an enquiry rather than about a person, and
        // they are exactly what survives an erasure on purpose.
        _Section(
          title: 'ee.admin.leads.enquiry'.tr(),
          rows: [
            (
              'ee.admin.leads.received'.tr(),
              _date(lead.createdAt) ?? 'ee.admin.leads.notStated'.tr(),
            ),
            (
              'ee.admin.leads.seats'.tr(),
              lead.seatCount?.toString() ?? 'ee.admin.leads.notStated'.tr(),
            ),
            (
              'ee.admin.leads.units'.tr(),
              lead.unitCount?.toString() ?? 'ee.admin.leads.notStated'.tr(),
            ),
            (
              'ee.admin.leads.package'.tr(),
              lead.packageInterest ?? 'ee.admin.leads.notStated'.tr(),
            ),
            (
              'ee.admin.leads.language'.tr(),
              'ee.admin.leads.locale.${lead.locale}'.tr(),
            ),
          ],
        ),

        // ── Who asked. Empty on an erased row, and the notice above is what
        // explains why — without it these blanks read as a broken record.
        if (!lead.erased)
          _Section(
            title: 'ee.admin.leads.contact'.tr(),
            rows: [
              (
                'ee.admin.leads.name'.tr(),
                lead.fullName ?? 'ee.admin.leads.notStated'.tr(),
              ),
              (
                'ee.admin.leads.email'.tr(),
                lead.workEmail ?? 'ee.admin.leads.notStated'.tr(),
              ),
              (
                'ee.admin.leads.phone'.tr(),
                lead.phone ?? 'ee.admin.leads.notStated'.tr(),
              ),
            ],
          ),

        if (!lead.erased && (lead.message ?? '').isNotEmpty) ...[
          const SizedBox(height: AwSpace.x3),
          Text('ee.admin.leads.message'.tr(), style: text.labelLarge),
          const SizedBox(height: AwSpace.x1),
          Text(lead.message!),
        ],

        // ── The consent, which is the reason the row may be held at all.
        _Section(
          title: 'ee.admin.leads.consent'.tr(),
          rows: [
            (
              'ee.admin.leads.consentVersion'.tr(),
              lead.consentVersion ?? 'ee.admin.leads.notStated'.tr(),
            ),
            (
              'ee.admin.leads.consentAt'.tr(),
              _date(lead.consentAt) ?? 'ee.admin.leads.notStated'.tr(),
            ),
          ],
        ),

        // ── The forensic three, on the shorter clock. Shown because the
        // question they answer — was this real or a script — is asked once,
        // here, while triaging.
        if (!lead.erased &&
            (lead.sourceIp != null ||
                lead.referrer != null ||
                lead.userAgent != null))
          _Section(
            title: 'ee.admin.leads.origin'.tr(),
            rows: [
              (
                'ee.admin.leads.sourceIp'.tr(),
                lead.sourceIp ?? 'ee.admin.leads.notStated'.tr(),
              ),
              (
                'ee.admin.leads.referrer'.tr(),
                lead.referrer ?? 'ee.admin.leads.notStated'.tr(),
              ),
              (
                'ee.admin.leads.userAgent'.tr(),
                lead.userAgent ?? 'ee.admin.leads.notStated'.tr(),
              ),
            ],
          ),

        const SizedBox(height: AwSpace.x4),
        Text('ee.admin.leads.status.label'.tr(), style: text.labelLarge),
        const SizedBox(height: AwSpace.x1),
        DropdownButtonFormField<String>(
          key: const Key('admin-lead-status'),
          initialValue: _status,
          items: [
            for (final status in kAdminLeadStatuses)
              DropdownMenuItem(
                value: status,
                child: Text('ee.admin.leads.status.$status'.tr()),
              ),
          ],
          onChanged: _busy ? null : (v) => setState(() => _status = v),
        ),

        const SizedBox(height: AwSpace.x3),
        TextField(
          key: const Key('admin-lead-notes'),
          controller: _notes,
          enabled: !_busy,
          maxLines: 4,
          maxLength: 4000,
          decoration: InputDecoration(
            labelText: 'ee.admin.leads.notes'.tr(),
            helperText: 'ee.admin.leads.notesHelp'.tr(),
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: AwSpace.x2),
          AwInlineError(message: _error!),
        ],

        const SizedBox(height: AwSpace.x3),
        Row(
          children: [
            FilledButton(
              key: const Key('admin-lead-save'),
              onPressed: _busy ? null : () => _save(lead),
              child: Text(
                _busy
                    ? 'ee.admin.leads.saving'.tr()
                    : 'ee.admin.leads.save'.tr(),
              ),
            ),
            const Spacer(),
            if (!lead.erased)
              TextButton.icon(
                key: const Key('admin-lead-erase'),
                onPressed: _busy ? null : () => _erase(lead),
                icon: const Icon(Icons.delete_outline),
                label: Text('ee.admin.leads.erase.action'.tr()),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _save(AdminLead lead) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = ref.read(adminSessionProvider).value?.accessToken;
      if (token == null) throw StateError('no admin session');
      final notes = _notes.text.trim();
      await ref
          .read(adminApiProvider)
          .patchLead(
            token,
            lead.id,
            status: _status,
            notes: notes.isEmpty ? null : notes,
            clearNotes: notes.isEmpty && (lead.notes ?? '').isNotEmpty,
          );
      ref.invalidate(adminLeadProvider(lead.id));
      ref.read(adminLeadsProvider.notifier).reload();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ee.admin.leads.saved'.tr())));
      }
    } catch (e) {
      if (mounted) setState(() => _error = localizedError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _erase(AdminLead lead) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('ee.admin.leads.erase.title'.tr()),
        // NAMES what happens, both halves of it. "Are you sure?" would leave
        // the operator to guess whether this removes the enquiry from the
        // funnel's numbers — it does not, and that is the whole design.
        content: Text('ee.admin.leads.erase.body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('ee.admin.leads.erase.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('admin-lead-erase-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('ee.admin.leads.erase.confirm'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = ref.read(adminSessionProvider).value?.accessToken;
      if (token == null) throw StateError('no admin session');
      await ref.read(adminApiProvider).eraseLead(token, lead.id);
      ref.invalidate(adminLeadProvider(lead.id));
      ref.read(adminLeadsProvider.notifier).reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ee.admin.leads.erase.done'.tr())),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = localizedError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Why this row is mostly empty.
///
/// The reason this widget exists rather than letting the blanks speak: a lead
/// whose personal columns were emptied looks identical to a lead that arrived
/// broken, and a legal obligation we DISCHARGED would read as a defect. It
/// also says what survived, because the next question an operator asks is
/// whether the funnel's numbers just moved.
class _ErasedNotice extends StatelessWidget {
  const _ErasedNotice({this.at});

  final String? at;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('admin-lead-erased'),
      color: scheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: AwSpace.x3),
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, color: scheme.onSurfaceVariant),
            const SizedBox(width: AwSpace.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ee.admin.leads.erasedNotice'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (at != null) ...[
                    const SizedBox(height: AwSpace.x1),
                    Text(
                      'ee.admin.leads.erasedAt'.tr(
                        args: {'date': _date(at) ?? at!},
                      ),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AwSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.labelLarge),
          const SizedBox(height: AwSpace.x1),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: AwSpace.x1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 160,
                    child: Text(label, style: text.bodySmall),
                  ),
                  Expanded(child: Text(value, style: text.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
