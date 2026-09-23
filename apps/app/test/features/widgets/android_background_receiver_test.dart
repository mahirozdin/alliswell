import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// OPH-341 — the broadcast every Android background turn is made of has to
/// have somewhere to land.
///
/// `HomeWidgetBackgroundIntent.getBroadcast` addresses
/// `HomeWidgetBackgroundReceiver` BY CLASS, and home_widget 0.9.3's own
/// manifest declares nothing. With no `<receiver>` in ours, the widget circle
/// (OPH-188), the six-hourly refresh (OPH-321) and the midnight redraw
/// (OPH-334) were broadcasts to nobody — shipped, green in every Dart suite,
/// and dead on every Android phone. No test could see it: each Dart half was
/// tested, the wire between them was not. This one reads the wire.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final senders = [
    for (final file in Directory(
      'android/app/src/main/kotlin/com/alliswell/alliswell',
    ).listSync().whereType<File>())
      if (file.path.endsWith('.kt') &&
          file.readAsStringSync().contains('HomeWidgetBackgroundIntent'))
        file.uri.pathSegments.last,
  ]..sort();

  test('the three background turns are still broadcasts', () {
    // If one stops sending, this list changes on purpose — and whether the
    // receiver is still needed is the question to ask in the same change.
    expect(senders, [
      'AlarmRefreshWorker.kt',
      'TasksWidgetProvider.kt',
      'WidgetMidnightWorker.kt',
    ]);
  });

  test('someone sends, so the manifest declares someone to receive', () {
    final receiver = RegExp(
      r'<receiver\s+android:name="es\.antonborri\.home_widget\.'
      r'HomeWidgetBackgroundReceiver"[\s\S]*?</receiver>',
    ).firstMatch(manifest);
    expect(
      receiver,
      isNotNull,
      reason: '${senders.join(', ')} broadcast to it by class',
    );
    final block = receiver!.group(0)!;
    expect(block, contains('es.antonborri.home_widget.action.BACKGROUND'));
    expect(
      block,
      contains('android:exported="false"'),
      reason:
          'every sender is this app (a PendingIntent runs as its creator); '
          'an exported receiver would let any app complete a task by URL — '
          'the write-by-URL ADR-0016 forbids',
    );
  });
}
