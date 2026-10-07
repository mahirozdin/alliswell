import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/error_messages.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/route_leading.dart';
import '../../../widgets/status_views.dart';
import '../../../widgets/swipe_actions.dart' show awConfirmDelete;
import '../customers_providers.dart';
import '../data/customers_api.dart';
import '../providers.dart' show canProvider;

/// The companies a team serves, and the people at them (OPH-360, UI-AUDIT
/// #18).
///
/// Before this screen a company contact, once added, could not be listed,
/// switched off or told apart from a colleague: `customers.manage` existed and
/// nothing in the app used it, so a person who left the customer kept their
/// way into the company portal. Two screens, one job — the companies, then a
/// company's people — the way units and their rosters are drawn.
///
/// ── AN OLDER SERVER SAYS SO ───────────────────────────────────────────────
///
/// Listing contacts, renaming, archiving and switching off arrived with
/// EE-300. On a server before it those routes do not exist, and the codeless
/// 404 is drawn as "this server cannot do this yet" rather than as an empty
/// company or a generic failure.
class EeCustomersScreen extends ConsumerWidget {
  const EeCustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(eeCustomersProvider);
    final may = ref.watch(canProvider('customers.manage'));

    return Scaffold(
      appBar: AppBar(
        leading: awRouteLeading(context),
        title: Text('ee.customers.title'.tr()),
      ),
      floatingActionButton: data.value == null || !may
          ? null
          : FloatingActionButton(
              key: const Key('customer-new'),
              tooltip: 'ee.customers.create'.tr(),
              onPressed: () => _create(context, ref),
              child: const Icon(Icons.add_business_outlined),
            ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeCustomersProvider),
        ),
        data: (customers) {
          if (customers == null) {
            return AwEmptyState(
              icon: Icons.business_outlined,
              title: 'ee.customers.unavailable'.tr(),
              message: 'ee.customers.unavailableBody'.tr(),
            );
          }
          if (customers.isEmpty) {
            return AwEmptyState(
              key: const Key('customers-empty'),
              icon: Icons.business_outlined,
              title: 'ee.customers.emptyTitle'.tr(),
              message: 'ee.customers.emptyBody'.tr(),
            );
          }
          // Live companies first, archived ones after them — still listed,
          // because restoring one is done from here.
          final sorted = [
            ...customers.where((c) => !c.archived),
            ...customers.where((c) => c.archived),
          ];
          return ListView(
            padding: awListPadding(context, fab: true),
            children: [
              for (final customer in sorted)
                _CustomerTile(customer: customer, may: may),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await _askName(
      context,
      title: 'ee.customers.create'.tr(),
      fieldKey: const Key('customer-name'),
    );
    if (name == null || !context.mounted) return;
    await _guard(
      context,
      () => ref.read(eeCustomersProvider.notifier).create(name),
    );
  }
}

class _CustomerTile extends ConsumerWidget {
  const _CustomerTile({required this.customer, required this.may});

  final EeCustomer customer;
  final bool may;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: kAwListRowPadding,
      child: Card(
        key: Key('customer-${customer.id}'),
        child: ListTile(
          leading: Icon(
            customer.archived
                ? Icons.inventory_2_outlined
                : Icons.business_outlined,
            // Archived reads as retired, not broken: muted, never red.
            color: customer.archived ? theme.disabledColor : null,
          ),
          title: Text(customer.name),
          subtitle: customer.archived
              ? Text(
                  'ee.customers.archived'.tr(),
                  style: theme.textTheme.bodySmall,
                )
              : null,
          trailing: may
              ? PopupMenuButton<String>(
                  key: Key('customer-menu-${customer.id}'),
                  tooltip: 'ee.customers.actions'.tr(),
                  onSelected: (value) => _act(context, ref, value),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'rename',
                      child: Text('ee.customers.rename'.tr()),
                    ),
                    PopupMenuItem(
                      value: 'archive',
                      child: Text(
                        customer.archived
                            ? 'ee.customers.unarchive'.tr()
                            : 'ee.customers.archive'.tr(),
                      ),
                    ),
                  ],
                )
              : const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EeCustomerContactsScreen(customer: customer),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref, String value) async {
    final controller = ref.read(eeCustomersProvider.notifier);
    switch (value) {
      case 'rename':
        final name = await _askName(
          context,
          title: 'ee.customers.rename'.tr(),
          initial: customer.name,
          fieldKey: const Key('customer-rename'),
        );
        if (name == null || name == customer.name || !context.mounted) return;
        await _guard(context, () => controller.rename(customer.id, name));
      case 'archive':
        // Archiving shuts a company's people out; it asks, and says what
        // stays (its open requests). Restoring is harmless and does not ask.
        final ok =
            customer.archived ||
            await awConfirmDelete(
              context,
              title: 'ee.customers.archiveTitle'.tr(
                args: {'name': customer.name},
              ),
              body: 'ee.customers.archiveBody'.tr(),
              confirmLabel: 'ee.customers.archive'.tr(),
              cancelLabel: 'ee.customers.keep'.tr(),
              confirmKey: const Key('customer-archive-confirm'),
            );
        if (!ok || !context.mounted) return;
        await _guard(
          context,
          () =>
              controller.setArchived(customer.id, archived: !customer.archived),
        );
    }
  }
}

/// One company's people: who may sign in to its portal, and the switch that
/// takes that away.
class EeCustomerContactsScreen extends ConsumerWidget {
  const EeCustomerContactsScreen({required this.customer, super.key});

  final EeCustomer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(eeCustomerContactsProvider(customer.id));
    final may = ref.watch(canProvider('customers.manage'));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: awRouteLeading(context),
        title: Text(customer.name),
      ),
      // An archived company takes no new people: restore it first.
      floatingActionButton: !may || customer.archived || page.hasError
          ? null
          : FloatingActionButton(
              key: const Key('contact-new'),
              tooltip: 'ee.customers.addContact'.tr(),
              onPressed: () => _add(context, ref),
              child: const Icon(Icons.person_add_alt),
            ),
      body: page.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => isUnsupported(error)
            ? AwEmptyState(
                key: const Key('contacts-unsupported'),
                icon: Icons.cloud_off_outlined,
                title: 'ee.customers.unsupportedTitle'.tr(),
                message: 'ee.customers.unsupportedBody'.tr(),
              )
            : AwErrorState(
                message: localizedError(error),
                onRetry: () =>
                    ref.invalidate(eeCustomerContactsProvider(customer.id)),
              ),
        data: (data) => ListView(
          padding: awListPadding(context, fab: true),
          children: [
            if (customer.archived)
              Padding(
                padding: kAwListRowPadding,
                child: Card(
                  key: const Key('customer-archived-note'),
                  child: Padding(
                    padding: const EdgeInsets.all(AwSpace.x4),
                    child: Text(
                      'ee.customers.archivedNote'.tr(),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ),
            if (data.contacts.isEmpty)
              AwEmptyState(
                key: const Key('contacts-empty'),
                icon: Icons.group_outlined,
                title: 'ee.customers.noContactsTitle'.tr(),
                message: 'ee.customers.noContactsBody'.tr(),
                physics: const NeverScrollableScrollPhysics(),
              ),
            for (final contact in data.contacts)
              _ContactTile(customer: customer, contact: contact, may: may),
            if (data.nextCursor != null)
              Padding(
                padding: const EdgeInsets.all(AwSpace.x3),
                child: Center(
                  child: TextButton(
                    key: const Key('contacts-more'),
                    onPressed: () => _guard(
                      context,
                      () => ref
                          .read(
                            eeCustomerContactsProvider(customer.id).notifier,
                          )
                          .loadMore(),
                    ),
                    child: Text('ee.customers.more'.tr()),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<_ContactDraft>(
      context: context,
      builder: (_) => const _AddContactDialog(),
    );
    if (draft == null || !context.mounted) return;
    final controller = ref.read(
      eeCustomerContactsProvider(customer.id).notifier,
    );
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final id = await controller.add(
        email: draft.email,
        displayName: draft.name,
      );
      if (draft.invite && context.mounted) {
        await _sendInvite(context, ref, id);
      }
    } on EeContactDeactivated catch (refusal) {
      // The address is a switched-off contact: the useful answer is the
      // switch, not "already exists".
      messenger?.showSnackBar(
        SnackBar(
          content: Text('ee.customers.addDeactivated'.tr()),
          action: SnackBarAction(
            label: 'ee.customers.reactivate'.tr(),
            onPressed: () =>
                controller.setDeactivated(refusal.customerUserId, off: false),
          ),
        ),
      );
    } catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(_say(error))));
    }
  }
}

class _ContactTile extends ConsumerWidget {
  const _ContactTile({
    required this.customer,
    required this.contact,
    required this.may,
  });

  final EeCustomer customer;
  final EeCustomerContact contact;
  final bool may;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final format = ref.watch(dateFormatProvider);
    return Padding(
      padding: kAwListRowPadding,
      child: Card(
        key: Key('contact-${contact.id}'),
        child: ListTile(
          leading: Icon(
            contact.deactivated
                ? Icons.person_off_outlined
                : Icons.person_outline,
            color: contact.deactivated ? theme.disabledColor : null,
          ),
          title: Text(contact.label),
          subtitle: Text(
            [
              if (contact.label != contact.email) contact.email,
              // The state is a WORD, not only a muted icon.
              contact.deactivated
                  ? 'ee.customers.stateOff'.tr()
                  : 'ee.customers.stateOn'.tr(),
              if (!contact.deactivated && contact.invitePending)
                'ee.customers.invitePending'.tr(),
              if (contact.lastSeenAt != null)
                'ee.customers.lastSeen'.tr(
                  args: {
                    'date': awFormatDate(contact.lastSeenAt!, format: format),
                  },
                ),
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          trailing: may
              ? PopupMenuButton<String>(
                  key: Key('contact-menu-${contact.id}'),
                  tooltip: 'ee.customers.actions'.tr(),
                  onSelected: (value) => _act(context, ref, value),
                  itemBuilder: (_) => [
                    if (!contact.deactivated && !customer.archived)
                      PopupMenuItem(
                        value: 'invite',
                        child: Text('ee.customers.invite'.tr()),
                      ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(
                        contact.deactivated
                            ? 'ee.customers.reactivate'.tr()
                            : 'ee.customers.deactivate'.tr(),
                      ),
                    ),
                  ],
                )
              : null,
        ),
      ),
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref, String value) async {
    final controller = ref.read(
      eeCustomerContactsProvider(customer.id).notifier,
    );
    switch (value) {
      case 'invite':
        await _sendInvite(context, ref, contact.id);
      case 'toggle':
        if (!contact.deactivated) {
          final ok = await awConfirmDelete(
            context,
            title: 'ee.customers.deactivateTitle'.tr(
              args: {'name': contact.label},
            ),
            body: 'ee.customers.deactivateBody'.tr(),
            confirmLabel: 'ee.customers.deactivate'.tr(),
            cancelLabel: 'ee.customers.keep'.tr(),
            confirmKey: const Key('contact-deactivate-confirm'),
          );
          if (!ok || !context.mounted) return;
        }
        await _guard(
          context,
          () =>
              controller.setDeactivated(contact.id, off: !contact.deactivated),
        );
    }
  }
}

/// Mints an invitation and shows its link the one time it exists.
Future<void> _sendInvite(
  BuildContext context,
  WidgetRef ref,
  String contactId,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final EeCustomerInvite invite;
  try {
    invite = await ref.read(eeCustomersApiProvider).invite(contactId);
  } catch (error) {
    messenger?.showSnackBar(SnackBar(content: Text(_say(error))));
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      key: const Key('contact-invite-once'),
      semanticLabel: 'ee.customers.inviteTitle'.tr(),
      title: Text('ee.customers.inviteTitle'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ee.customers.inviteBody'.tr(),
            style: Theme.of(dialogContext).textTheme.bodySmall,
          ),
          const SizedBox(height: AwSpace.x3),
          Semantics(
            label: 'ee.customers.inviteLink'.tr(),
            child: SelectableText(
              invite.url,
              key: const Key('contact-invite-url'),
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('contact-invite-copy'),
          onPressed: () async {
            final dialogMessenger = ScaffoldMessenger.maybeOf(dialogContext);
            try {
              await Clipboard.setData(ClipboardData(text: invite.url));
              dialogMessenger?.showSnackBar(
                SnackBar(content: Text('ee.customers.copied'.tr())),
              );
            } catch (_) {
              dialogMessenger?.showSnackBar(
                SnackBar(content: Text('ee.customers.copyFailed'.tr())),
              );
            }
          },
          child: Text('common.copy'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text('common.done'.tr()),
        ),
      ],
    ),
  );
}

class _ContactDraft {
  const _ContactDraft({
    required this.email,
    required this.name,
    required this.invite,
  });
  final String email;
  final String? name;
  final bool invite;
}

class _AddContactDialog extends StatefulWidget {
  const _AddContactDialog();

  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  var _invite = true;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _email.text.trim().contains('@');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      semanticLabel: 'ee.customers.addContact'.tr(),
      title: Text('ee.customers.addContact'.tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('contact-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: InputDecoration(labelText: 'ee.customers.email'.tr()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AwSpace.x3),
            TextField(
              key: const Key('contact-name'),
              controller: _name,
              decoration: InputDecoration(
                labelText: 'ee.customers.contactName'.tr(),
              ),
            ),
            SwitchListTile(
              key: const Key('contact-invite-now'),
              contentPadding: EdgeInsets.zero,
              value: _invite,
              title: Text('ee.customers.inviteNow'.tr()),
              onChanged: (v) => setState(() => _invite = v),
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
          key: const Key('contact-add-confirm'),
          onPressed: !_valid
              ? null
              : () => Navigator.of(context).pop(
                  _ContactDraft(
                    email: _email.text.trim(),
                    name: _name.text.trim().isEmpty ? null : _name.text.trim(),
                    invite: _invite,
                  ),
                ),
          child: Text('common.add'.tr()),
        ),
      ],
    );
  }
}

/// A company name, asked in a dialog that owns its field.
Future<String?> _askName(
  BuildContext context, {
  required String title,
  required Key fieldKey,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) =>
      _NameDialog(title: title, fieldKey: fieldKey, initial: initial),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.fieldKey,
    required this.initial,
  });

  final String title;
  final Key fieldKey;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _name.text.trim();
    return AlertDialog(
      semanticLabel: widget.title,
      title: Text(widget.title),
      content: TextField(
        key: widget.fieldKey,
        controller: _name,
        autofocus: true,
        maxLength: 200,
        decoration: InputDecoration(labelText: 'ee.customers.name'.tr()),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const Key('customer-name-save'),
          onPressed: value.isEmpty
              ? null
              : () => Navigator.of(context).pop(value),
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}

/// A refusal in words. A codeless 404 on these doors means the server is
/// older than them — said as such, not as "not found".
String _say(Object error) => isUnsupported(error)
    ? 'ee.customers.unsupportedAction'.tr()
    : localizedError(error);

Future<void> _guard(
  BuildContext context,
  Future<void> Function() action,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action();
  } catch (error) {
    messenger?.showSnackBar(SnackBar(content: Text(_say(error))));
  }
}
