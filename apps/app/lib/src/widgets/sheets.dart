import 'package:flutter/material.dart';

/// One place for the root-navigator bottom-sheet contract (OPH-221). Pushed
/// into a shell branch, a sheet otherwise renders UNDER the shell's glass bar
/// and FAB (the OPH-212 lesson) — so every AI sheet goes through here. New AI
/// surfaces use this; the older 17 call sites are already correct and are left
/// as they are (churn without behavior change).
Future<T?> showAwSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool showDragHandle = false,
  double maxWidth = 560,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: isScrollControlled,
    useSafeArea: true,
    showDragHandle: showDragHandle,
    constraints: BoxConstraints(maxWidth: maxWidth),
    builder: builder,
  );
}
