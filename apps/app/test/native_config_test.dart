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
/// Swift with its comments stripped. These guards assert on the ABSENCE of
/// calls, and every one of those absences is worth explaining in the file —
/// so a naive substring search would be tripped by the sentence that documents
/// the rule it is enforcing.
String _code(String source) => source
    .split('\n')
    .where((line) {
      final trimmed = line.trimLeft();
      return !trimmed.startsWith('//') && !trimmed.startsWith('///');
    })
    .join('\n');

void main() {
  // OPH-242 / ADR-0029. The extension's own source used to CLAIM it was guarded
  // here; it was not — this file only ever read plists. These are the rules
  // that, if a refactor drops them, fail as silence again.
  group('AllisWellShare extension', () {
    late final String share = File(
      'ios/AllisWellShare/ShareViewController.swift',
    ).readAsStringSync();
    late final String notifier = File(
      'ios/AllisWellShare/ShareNotifier.swift',
    ).readAsStringSync();

    test('keeps its own compose sheet instead of auto-redirecting', () {
      expect(
        share,
        contains('shouldAutoRedirect'),
        reason:
            'An appex cannot open its host app on iOS 18+: the pre-18 selector '
            'walk is refused, and 1.8.1\'s replacement looks for a '
            'UIApplication in a responder chain that never has one. Returning '
            'false here is what makes the payload reachable at all — the sheet '
            'writes the App Group and the app drains it later (ADR-0029).',
      );
    });

    test('never asks for notification permission from the extension', () {
      expect(notifier, contains('UNUserNotificationCenter'));
      expect(
        // Code only: the file explains WHY it must not call this, and a
        // substring guard that cannot tell a rule from its explanation fails
        // on the very comment that states the rule.
        _code(notifier),
        isNot(contains('requestAuthorization')),
        reason:
            'An app extension has no context to present the system prompt in. '
            'It reads the decision the app already holds and stays quiet '
            'otherwise; a denied user still gets the share on next launch.',
      );
    });

    test('the shared text never reaches the notification', () {
      // The worst failure mode this feature has is someone\'s shared paragraph
      // on a lock screen. The banner is built from localized constants only.
      for (final line in notifier.split('\n')) {
        final assignsText =
            line.contains('content.body') || line.contains('content.title');
        if (!assignsText) continue;
        expect(
          line,
          contains('NSLocalizedString'),
          reason: 'notification copy must be a constant, never the payload',
        );
      }
    });

    test('does no network and no AI — ADR-0023 §3, kept by ADR-0029', () {
      for (final source in [_code(share), _code(notifier)]) {
        expect(source, isNot(matches(RegExp(r'URLSession|NSURLConnection'))));
        expect(source, isNot(contains('/ai/')));
      }
    });
  });

  group('iOS App Group drain', () {
    test('the bridge is registered, or the mailbox is never read', () {
      expect(
        File('ios/Runner/AppDelegate.swift').readAsStringSync(),
        contains('ShareInboxBridge'),
        reason:
            'receive_sharing_intent only fills its buffers from a URL open, '
            'and ADR-0029 stopped producing one. Without this registration the '
            'payload reaches the App Group and is never read — the exact '
            'silence round 17 #1 reported.',
      );
    });

    test('Runner declares the App Group it drains', () {
      expect(
        File('ios/Runner/Info.plist').readAsStringSync(),
        contains('AppGroupId'),
        reason:
            'The plugin falls back to group.<bundle id>, which happens to be '
            'right today. Stated explicitly so a bundle id change breaks the '
            'build instead of the feature.',
      );
    });
  });

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
