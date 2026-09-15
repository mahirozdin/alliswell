import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/web_alert_mode.dart';

/// OPH-316 — the office's request: a window, not a noise. Three values,
/// because "off" and "silent" promise different things.
void main() {
  test('parses the three values and nothing else', () {
    expect(WebAlertMode.parse('off'), WebAlertMode.off);
    expect(WebAlertMode.parse('silent'), WebAlertMode.silent);
    expect(WebAlertMode.parse('loud'), WebAlertMode.loud);
  });

  test('anything unreadable is silent, including an upgrade from nothing', () {
    // The value a device had before this setting existed is the empty string,
    // and a stored value from a future version is just as unknown here.
    expect(WebAlertMode.parse(''), WebAlertMode.silent);
    expect(WebAlertMode.parse(null), WebAlertMode.silent);
    expect(WebAlertMode.parse('LOUD'), WebAlertMode.silent);
    expect(WebAlertMode.parse('whisper'), WebAlertMode.silent);
  });

  test('only "loud" lets a notification make a sound', () {
    expect(WebAlertMode.loud.silences, isFalse);
    expect(WebAlertMode.silent.silences, isTrue);
    // `off` reads as silent so a cache entry written before delivery was
    // turned off can never be the loud one if it is somehow looked up.
    expect(WebAlertMode.off.silences, isTrue);
  });

  test('round-trips through the id it is stored under', () {
    for (final mode in WebAlertMode.values) {
      expect(WebAlertMode.parse(mode.id), mode);
    }
  });
}
