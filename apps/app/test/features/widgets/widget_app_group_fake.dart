import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The widget's App Group behind `home_widget`'s method channel, as the
/// plugin's iOS side (0.9.3) treats it: a value is stored as it comes, and a
/// null arrives as `NSNull`, which `NSUserDefaults` refuses by aborting the
/// app (#50, PR2-01) — here a [PlatformException], recorded in [calls].
class FakeHomeWidgetChannel {
  static const channel = MethodChannel('home_widget');

  /// The App Group's values, by key.
  final Map<String, Object> values = {};

  /// Every call the app made, in order.
  final List<MethodCall> calls = [];

  /// The keys written, then `update` for every reload asked for, in order.
  final List<String> log = [];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, _handle);
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }

  /// Removed — the app writes the empty string for that (WIDGETS §3.2) — or
  /// never written.
  bool isAbsent(String key) => !values.containsKey(key) || values[key] == '';

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    final args = call.arguments is Map ? call.arguments as Map : const {};
    switch (call.method) {
      case 'setAppGroupId':
        return true;
      case 'saveWidgetData':
        final id = args['id'] as String;
        final data = args['data'];
        if (data == null) {
          throw PlatformException(
            code: 'NSNull',
            message: '-[NSUserDefaults setObject:forKey:] aborts on NSNull',
          );
        }
        values[id] = data as Object;
        log.add(id);
        return true;
      case 'getWidgetData':
        return values[args['id']] ?? args['defaultValue'];
      case 'updateWidget':
        log.add('update');
        return true;
      default:
        return null;
    }
  }
}
