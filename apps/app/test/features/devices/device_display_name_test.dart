import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/devices/data/device_api.dart';
import 'package:alliswell/src/features/devices/device_display_name.dart';
import 'package:alliswell/src/i18n/i18n.dart';

/// OPH-448 — the server stores the raw User-Agent as `device_name` on insert
/// (OPH-284) and the app sends no name, so an unnamed row would read
/// "Dart/3.13 (dart:io)" or a whole browser string. Nobody recognises their
/// phone by that; every place that names a device goes through this.
DeviceInfo _device(String platform, String? name) =>
    DeviceInfo(id: 'D1', platform: platform, name: name);

void main() {
  test('a User-Agent name is shown as the platform label', () {
    const dart = 'Dart/3.13 (dart:io)';
    expect(deviceDisplayName(_device('ios', dart)), 'iPhone');
    expect(deviceDisplayName(_device('android', dart)), 'Android');
    expect(deviceDisplayName(_device('macos', dart)), 'Mac');
    expect(deviceDisplayName(_device('windows', dart)), 'Windows');
    expect(deviceDisplayName(_device('linux', dart)), 'Linux');

    // A browser row is named by what the browser string says it is.
    expect(
      deviceDisplayName(
        _device(
          'web',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        ),
      ),
      'Chrome · Windows',
    );
    expect(
      deviceDisplayName(
        _device(
          'web',
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
              '(KHTML, like Gecko) Version/18.1 Safari/605.1.15',
        ),
      ),
      'Safari · macOS',
    );
    expect(
      deviceDisplayName(
        _device(
          'web',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0',
        ),
      ),
      'Edge · Windows',
    );
    expect(
      deviceDisplayName(
        _device(
          'web',
          'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:133.0) Gecko/20100101 '
              'Firefox/133.0',
        ),
      ),
      'Firefox · Linux',
    );
    expect(
      deviceDisplayName(
        _device(
          'web',
          'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
        ),
      ),
      'Chrome · Android',
    );
    expect(
      deviceDisplayName(
        _device(
          'web',
          'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) '
              'AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/131.0 '
              'Mobile/15E148 Safari/604.1',
        ),
      ),
      'Chrome · iOS',
    );

    // Nothing to read: the generic word, in the active language.
    final browser = 'settings.devices.unknownBrowser'.tr();
    expect(browser, isNot('settings.devices.unknownBrowser'));
    expect(deviceDisplayName(_device('web', null)), browser);
    expect(deviceDisplayName(_device('web', '  ')), browser);
    expect(deviceDisplayName(_device('web', 'Mozilla/5.0')), browser);
    expect(deviceDisplayName(_device('ios', null)), 'iPhone');
    expect(deviceDisplayName(_device('android', '')), 'Android');
  });

  test('a user-set name is kept', () {
    expect(deviceDisplayName(_device('ios', 'iPhone 16')), 'iPhone 16');
    expect(
      deviceDisplayName(_device('macos', '  MacBook Air ')),
      'MacBook Air',
    );
    // Even on the web, and even when it mentions a browser.
    expect(
      deviceDisplayName(_device('web', 'İş bilgisayarı')),
      'İş bilgisayarı',
    );
    expect(
      deviceDisplayName(_device('web', 'Chrome at work')),
      'Chrome at work',
    );
  });
}
