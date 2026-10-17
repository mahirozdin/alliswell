import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/deep_link.dart';

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

  // OPH-298 (amends ADR-0029): the callback ADR-0029 was sure could not
  // happen. On iOS 26 the appex's open ARRIVES, no plugin claims it under the
  // UIScene lifecycle, and Flutter turns an unclaimed URL into a ROUTE — which
  // put a share that had already been saved on the error screen. The scene
  // delegate drops it; this is the line that keeps it dropped.
  group('iOS scene delegate', () {
    late final String scene = File(
      'ios/Runner/SceneDelegate.swift',
    ).readAsStringSync();

    test('forwards the FILTERED contexts, never the raw set', () {
      expect(
        _code(scene),
        contains('super.scene(scene, openURLContexts: forwarded)'),
        reason:
            'Handing the raw set to super forwards the share callback to '
            'Flutter, which routes it, which is OPH-298 all over again.',
      );
      expect(
        _code(scene),
        isNot(contains('super.scene(scene, openURLContexts: URLContexts)')),
      );
    });

    test('recognizes the callback by scheme, and only that', () {
      // Derived from the bundle id so a flavor needs no edit, and lowercased
      // because iOS normalizes the scheme it delivers.
      expect(_code(scene), contains('sharemedia-'));
      expect(_code(scene), contains('Bundle.main.bundleIdentifier'));
      expect(
        _code(scene),
        contains('isFileURL'),
        reason:
            'the document handle still takes file URLs only (ADR-0030) — a '
            'filter that swallowed those would break "Open in AllisWell".',
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
  // OPH-370 / ADR-0051 — the Windows and Linux downloads carry these shells;
  // `flutter create` would put Flutter's defaults back without a sound.
  group('desktop runners', () {
    test('the Linux window is titled AllisWell', () {
      final cc = _code(
        File('linux/runner/my_application.cc').readAsStringSync(),
      );
      expect(
        RegExp(
          r'gtk_header_bar_set_title\(header_bar, "AllisWell"\)',
        ).hasMatch(cc),
        isTrue,
      );
      expect(
        RegExp(r'gtk_window_set_title\(window, "AllisWell"\)').hasMatch(cc),
        isTrue,
      );
      expect(cc.contains('"alliswell")'), isFalse);
    });

    test('the Windows window is titled AllisWell', () {
      final cpp = File('windows/runner/main.cpp').readAsStringSync();
      expect(cpp.contains('window.Create(L"AllisWell"'), isTrue);
    });

    test('Runner.rc names the product, the binary name is unchanged', () {
      final rc = File('windows/runner/Runner.rc').readAsStringSync();
      expect(rc.contains('VALUE "ProductName", "AllisWell"'), isTrue);
      expect(rc.contains('VALUE "CompanyName", "BubiApps"'), isTrue);
      expect(rc.contains('VALUE "OriginalFilename", "alliswell.exe"'), isTrue);
    });

    test('app_icon.ico is the AllisWell mark, not Flutter\'s default', () {
      final ico = File(
        'windows/runner/resources/app_icon.ico',
      ).readAsBytesSync();
      // Flutter's template icon is exactly 33,772 bytes.
      expect(ico.length, isNot(33772));
      expect(ico.sublist(0, 4), [0, 0, 1, 0]); // ICONDIR, type 1 = icon
      final count = ico[4] | (ico[5] << 8);
      final widths = [
        for (var i = 0; i < count; i++) ico[6 + i * 16],
      ]; // 0 means 256
      expect(widths, contains(0));
      expect(widths, containsAll([16, 32, 48]));
    });
  });
  // OPH-376 (ADR-0057): "Hey Siri, add a task in AllisWell". The Swift cannot
  // be compiled on Linux, so what can be checked here is the wiring — a file in
  // no target never runs, and a phrase without a translation is not heard.
  group('iOS/macOS App Shortcuts', () {
    late final String iosProject = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    late final String macProject = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    late final String swift = _code(
      File('ios/Shared/AWAppShortcuts.swift').readAsStringSync(),
    );

    /// Every `Sources` build phase of [project], as its text block.
    List<String> sourcePhases(String project) => RegExp(
      r'/\* Sources \*/ = \{[^}]*isa = PBXSourcesBuildPhase;[^}]*\};',
    ).allMatches(project).map((m) => m.group(0)!).toList();

    test('the Swift is in the iOS Runner and in no extension', () {
      final phases = sourcePhases(iosProject);
      final runner = phases.where(
        (p) => p.contains('AppDelegate.swift in Sources'),
      );
      expect(runner, hasLength(1));
      expect(runner.single, contains('AWAppShortcuts.swift in Sources'));
      expect(
        phases.where((p) => p.contains('AWAppShortcuts.swift in Sources')),
        hasLength(1),
        reason:
            'an AppShortcutsProvider belongs to the app only — in the widget '
            'extension its intents would run in the wrong process',
      );
    });

    test('the macOS Runner compiles the same file', () {
      final runner = sourcePhases(
        macProject,
      ).where((p) => p.contains('MainFlutterWindow.swift in Sources'));
      expect(runner.single, contains('AWAppShortcuts.swift in Sources'));
      expect(macProject, contains('path = ../ios/Shared;'));
    });

    test('both projects ship the en and tr strings', () {
      for (final project in [iosProject, macProject]) {
        expect(project, contains('AppShortcuts.strings in Resources'));
        expect(project, contains('Localizable.strings in Resources'));
        expect(project, contains('path = tr.lproj/AppShortcuts.strings;'));
        expect(project, contains('path = tr.lproj/Localizable.strings;'));
        final regions = RegExp(
          r'knownRegions = \(([^)]*)\);',
        ).firstMatch(project)!.group(1)!;
        expect(regions, contains('tr,'));
      }
    });

    test('both app delegates construct the bridge', () {
      expect(
        _code(File('ios/Runner/AppDelegate.swift').readAsStringSync()),
        contains('AWCaptureBridge(messenger:'),
      );
      expect(
        _code(File('macos/Runner/MainFlutterWindow.swift').readAsStringSync()),
        contains('AWCaptureBridge(messenger:'),
      );
    });

    test('the intents bring the app forward, never run headless', () {
      expect(
        'openAppWhenRun: Bool = true'.allMatches(swift),
        hasLength(2),
        reason:
            'a task added in the background would not arm its alarm until '
            'the app next ran (ADR-0057)',
      );
      expect(swift, isNot(contains('openAppWhenRun: Bool = false')));
      expect(swift, contains('AppShortcutsProvider'));
      expect(swift, isNot(contains('LiveActivityIntent')));
      expect(swift, contains('"alliswell/capture"'));
      expect(swift, contains('"aw_capture_pending"'));
    });

    Map<String, String> strings(String path) => {
      for (final m in RegExp(
        r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";',
        multiLine: true,
      ).allMatches(File(path).readAsStringSync()))
        m.group(1)!: m.group(2)!,
    };

    test('every phrase names the app, in both languages', () {
      final en = strings('ios/Shared/en.lproj/AppShortcuts.strings');
      final tr = strings('ios/Shared/tr.lproj/AppShortcuts.strings');
      expect(en, isNotEmpty);
      expect(tr.keys.toSet(), en.keys.toSet());
      for (final entry in [...en.entries, ...tr.entries]) {
        expect(entry.key, contains(r'${applicationName}'));
        expect(entry.value, contains(r'${applicationName}'));
      }
    });

    test('every Swift phrase has its strings key', () {
      final en = strings('ios/Shared/en.lproj/AppShortcuts.strings');
      final phrases = RegExp(r'"([^"]*\\\(\.applicationName\)[^"]*)"')
          .allMatches(swift)
          .map(
            (m) => m
                .group(1)!
                .replaceAll(r'\(.applicationName)', r'${applicationName}'),
          );
      expect(phrases, hasLength(6));
      for (final phrase in phrases) {
        expect(en.keys, contains(phrase));
      }
    });

    test('the intent titles are translated, key for key', () {
      final en = strings('ios/Shared/en.lproj/Localizable.strings');
      final tr = strings('ios/Shared/tr.lproj/Localizable.strings');
      expect(tr.keys.toSet(), en.keys.toSet());
      for (final key in [
        'Add task',
        'Show today',
        'Today',
        'Task',
        "What's the task?",
        r'Add ${text} to AllisWell',
      ]) {
        expect(en.keys, contains(key));
      }
    });
  });

  group('Android launcher shortcuts', () {
    late final String manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    late final String shortcuts = File(
      'android/app/src/main/res/xml/shortcuts.xml',
    ).readAsStringSync();
    String withoutComments(String xml) =>
        xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    Set<String> stringNames(String path) => RegExp(
      r'<string name="([^"]+)"',
    ).allMatches(File(path).readAsStringSync()).map((m) => m.group(1)!).toSet();

    test('MainActivity declares them', () {
      final activity = RegExp(
        r'<activity\s+android:name="\.MainActivity".*?</activity>',
        dotAll: true,
      ).firstMatch(withoutComments(manifest))!.group(0)!;
      expect(activity, contains('android:name="android.app.shortcuts"'));
      expect(activity, contains('android:resource="@xml/shortcuts"'));
    });

    test('every shortcut is a navigation the router knows (ADR-0016)', () {
      final data = RegExp(
        r'android:data="([^"]+)"',
      ).allMatches(shortcuts).map((m) => m.group(1)!).toList();
      expect(data, hasLength(2));
      for (final uri in data) {
        expect(awRouteForUri(Uri.parse(uri)), isNotNull, reason: uri);
      }
      expect(
        RegExp(
          r'android:targetPackage="com\.alliswell\.alliswell"',
        ).allMatches(shortcuts),
        hasLength(2),
      );
    });

    test('every label exists in English and Turkish', () {
      final en = stringNames('android/app/src/main/res/values/strings.xml');
      final tr = stringNames('android/app/src/main/res/values-tr/strings.xml');
      expect(tr, en, reason: 'values-tr keeps every key of values');
      final used = RegExp(
        r'@string/(\w+)',
      ).allMatches(shortcuts).map((m) => m.group(1)!).toSet();
      expect(used, hasLength(4));
      expect(en, containsAll(used));
    });

    test('no assistant write path: no capability, no AUTO_SEND', () {
      final code = withoutComments(manifest) + withoutComments(shortcuts);
      expect(code, isNot(contains('<capability')));
      expect(code, isNot(contains('AUTO_SEND')));
      expect(code, isNot(contains('CREATE_NOTE')));
    });
  });
}
