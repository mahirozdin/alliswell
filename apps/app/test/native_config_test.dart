import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Round 17 #1 (OPH-242) — the share pipeline's two ends live in native config
/// files, where no Dart test can reach the behaviour. This guards the rules,
/// the way `web_shell_test.dart` guards the Firefox selection fix.
///
/// The failure these prevent is the worst kind: **silence**. "Share to
/// AllisWell" listed the app, the sheet dismissed, and nothing happened — no
/// launch, no crash, no report — because the extension opened a URL scheme the
/// app had never registered. A missing line in a plist is invisible in review
/// and invisible at runtime; it is only visible here.
///
/// Both files are templated: `flutter create` rewrites `Info.plist` and
/// `AndroidManifest.xml` wholesale, and `ios/scripts/wire_share_extension.rb`
/// rewrites the Xcode project around them.
void main() {
  group('iOS Info.plist', () {
    late final String plist = File('ios/Runner/Info.plist').readAsStringSync();

    test('registers the share extension\'s callback scheme', () {
      expect(
        plist,
        contains('ShareMedia-\$(PRODUCT_BUNDLE_IDENTIFIER)'),
        reason:
            'AllisWellShare subclasses RSIShareViewController, whose only way '
            'back into the app is opening "ShareMedia-<host bundle id>:share". '
            'Unregistered, iOS drops that open silently and sharing does '
            'nothing at all (round 17 #1, OPH-242).',
      );
    });

    test('still declares the deep-link and markdown handlers', () {
      // The share scheme was ADDED to an existing array; a careless edit that
      // replaces it instead would break the widget taps (ADR-0016) and the
      // "Open with AllisWell" registration (OPH-241) without failing anything.
      expect(plist, contains('<string>alliswell</string>'));
      expect(plist, contains('net.daringfireball.markdown'));
      expect(plist, contains('LSSupportsOpeningDocumentsInPlace'));
    });
  });

  group('AndroidManifest', () {
    late final String manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    test('receives shared text', () {
      expect(manifest, contains('android.intent.action.SEND'));
      expect(
        manifest,
        contains('android:mimeType="text/plain"'),
        reason:
            'the share target only appears in the Android sheet for the mime '
            'types it declares (OPH-225).',
      );
    });

    test('opens markdown files by extension, not by mime type alone', () {
      // Android reports a .md as text/plain or application/octet-stream
      // depending on which app produced the intent, so a mime-only filter
      // misses most real files (OPH-241).
      expect(manifest, contains(r'.*\\.md'));
      expect(manifest, contains('text/markdown'));
    });
  });
}
