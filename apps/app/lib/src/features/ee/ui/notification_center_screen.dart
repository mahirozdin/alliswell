import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../widgets/status_views.dart';
import '../notifications_providers.dart';

/// The notification centre (EE-077) — what happened to you, offline.
///
/// Every row comes from the replica (EE-073's synced inbox), so this screen is
/// complete on a phone with no signal, which is the reason notifications were
/// delivered through sync rather than fetched from an endpoint.
///
/// READ AND UNREAD SIT TOGETHER, newest first. Hiding what you have read would
/// turn the centre into a to-do list, and this app already has one of those;
/// what this screen is for is answering "what did I miss", which includes the
/// thing you glanced at yesterday.
class EeNotificationCenterScreen extends ConsumerWidget {
  const EeNotificationCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationCenterProvider);
    final unread = ref.watch(unreadNotificationCountProvider).value ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('ee.notif.centerTitle'.tr()),
        actions: [
          // No dead controls (DESIGN §22): with nothing unread the action is
          // absent rather than present-and-inert.
          if (unread > 0)
            TextButton(
              key: const Key('notif-mark-all-read'),
              onPressed: () async {
                final count = await ref
                    .read(notificationStoreProvider)
                    .markAllRead();
                if (!context.mounted || count == 0) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'ee.notif.markedAllRead'.tr(args: {'count': '$count'}),
                    ),
                  ),
                );
              },
              child: Text('ee.notif.markAllRead'.tr()),
            ),
        ],
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(message: localizedError(error)),
        data: (rows) {
          if (rows.isEmpty) {
            return AwEmptyState(
              key: const Key('notif-empty'),
              icon: Icons.notifications_none_outlined,
              title: 'ee.notif.emptyTitle'.tr(),
              message: 'ee.notif.emptyBody'.tr(),
            );
          }
          return ListView.separated(
            padding: awListPadding(context),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) =>
                _NotificationTile(item: rows[index]),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.item});

  final NotificationItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // The server sends KEYS and their parameters; the device renders them in
    // the language it is set to now (EE-073). A missing key falls back to the
    // key itself rather than to a blank row — visible, and traceable.
    final args = {
      for (final entry in item.params.entries) entry.key: '${entry.value}',
    };
    final title = item.titleKey.tr(args: args);
    final body = item.bodyKey?.tr(args: args);
    final destination = item.destination;

    return ListTile(
      key: Key('notif-${item.id}'),
      leading: _UnreadDot(unread: item.isUnread),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: item.isUnread ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: body == null || body.isEmpty
          ? null
          : Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: item.createdAt == null
          ? null
          : Text(_shortWhen(item.createdAt!), style: theme.textTheme.bodySmall),
      onTap: () async {
        // Reading it is the act of opening it — marking read separately would
        // be a second tap for something the first tap already meant.
        await ref.read(notificationStoreProvider).markRead(item.id);
        if (!context.mounted || destination == null) return;
        context.push(destination);
      },
    );
  }

  /// Deliberately coarse. A notification centre needs "when, roughly"; a
  /// precise timestamp belongs to the history tab, which has one.
  ///
  /// TRANSLATED, and that was not the first version. "5m / 3h / 1d" looked
  /// like punctuation rather than words, so it shipped hardcoded — and then a
  /// Turkish screenshot showed "3h" and "1d" sitting under Turkish sentences.
  /// An abbreviation is still language.
  static String _shortWhen(DateTime at) {
    final delta = DateTime.now().toUtc().difference(at.toUtc());
    if (delta.inMinutes < 1) return 'ee.notif.time.now'.tr();
    if (delta.inHours < 1) {
      return 'ee.notif.time.minutes'.tr(args: {'n': '${delta.inMinutes}'});
    }
    if (delta.inDays < 1) {
      return 'ee.notif.time.hours'.tr(args: {'n': '${delta.inHours}'});
    }
    return 'ee.notif.time.days'.tr(args: {'n': '${delta.inDays}'});
  }
}

/// The unread marker.
///
/// A dot rather than a colour on the text: DESIGN's contrast rule (§11) applies
/// to anything carrying meaning, and "slightly darker text" is exactly the kind
/// of signal that survives a designer's eye and fails a contrast measurement.
/// The dot uses the theme's primary colour on the theme's surface, which the
/// gate already checks for every other use of that pair.
class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.unread});

  final bool unread;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 12,
      height: 40,
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: unread ? scheme.primary : Colors.transparent,
          ),
        ),
      ),
    );
  }
}
