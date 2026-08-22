import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/i18n.dart';
import 'history_tab.dart';

/// Item 10's task half, on screen (EE-069).
///
/// *"Task ve ITSM ticket'larındaki TÜM işlemler loglanır (üstüne aldı, bıraktı,
/// atadı, alt işi tamamladı…) ve History sekmesinde saatleriyle izlenir."*
///
/// The mandate says TAB, and this is a screen — a departure worth writing down
/// rather than hiding. The task detail is one scroll of cards with no tab bar
/// anywhere in it; adding one for an entitlement-gated feature would reshape a
/// CORE screen for an EE reason, which is exactly what ADR-0001 §5 asks the
/// overlay not to do. What item 10 actually promises — the task's whole story,
/// with times, reachable from the task — is kept, and the widget rendering it
/// is EE-026's, unchanged, so a ticket's history in E09 will read identically.
class EeTaskHistoryScreen extends ConsumerWidget {
  const EeTaskHistoryScreen({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text('ee.history.taskTitle'.tr())),
    body: EeHistoryTab(entityType: 'task', entityId: taskId),
  );
}
