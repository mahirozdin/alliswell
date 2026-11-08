import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../i18n/i18n.dart';
import '../../../sections.dart';
import '../../../widgets/route_leading.dart';
import '../../../widgets/status_views.dart';

/// OPH-409 (E-19) — the old "assigned to me" address.
///
/// EE-296 retired that list: in an organisation Home is the person's work,
/// everything assigned to them from every unit. The address used to redirect
/// to Home without a word, so a bookmark or an old link looked like a broken
/// page that dropped the person somewhere else. It now says where the list
/// went and takes them there in one tap.
class EeAssignmentsMovedScreen extends StatelessWidget {
  const EeAssignmentsMovedScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: awRouteLeading(context),
      title: Text('ee.assignmentsMoved.title'.tr()),
    ),
    body: AwEmptyState(
      key: const Key('ee-assignments-moved'),
      icon: Icons.home_outlined,
      title: 'ee.assignmentsMoved.heading'.tr(),
      message: 'ee.assignmentsMoved.body'.tr(),
      action: FilledButton.icon(
        key: const Key('ee-assignments-moved-home'),
        onPressed: () => context.go(AppSection.home.path),
        icon: const Icon(Icons.home_outlined),
        label: Text('ee.assignmentsMoved.action'.tr()),
      ),
    ),
  );
}
