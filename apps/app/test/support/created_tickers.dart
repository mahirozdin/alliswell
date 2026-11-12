import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// The class names of every [AnimationController] and [Ticker] constructed
/// while [body] runs, read from Flutter's debug memory-allocation events.
///
/// A State that builds a controller lazily (`late final … = AnimationController(
/// vsync: this)`) and only touches it in `dispose()` constructs it while its
/// element is deactivated: newer Flutter versions throw there, `dispose()`
/// aborts and leaves its timers pending. Unmounting inside this helper and
/// expecting an empty list catches the pattern on every Flutter version.
Future<List<String>> tickersCreatedDuring(Future<void> Function() body) async {
  assert(
    kFlutterMemoryAllocationsEnabled,
    'flutter test runs in debug mode, where allocation events are on',
  );
  final created = <String>[];
  void listener(ObjectEvent event) {
    if (event is! ObjectCreated) return;
    final object = event.object;
    if (object is AnimationController || object is Ticker) {
      created.add(event.className);
    }
  }

  FlutterMemoryAllocations.instance.addListener(listener);
  try {
    await body();
  } finally {
    FlutterMemoryAllocations.instance.removeListener(listener);
  }
  return created;
}
