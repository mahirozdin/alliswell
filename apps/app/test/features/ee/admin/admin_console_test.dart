import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/features/ee/admin/admin_providers.dart';
import 'package:alliswell/src/features/ee/admin/data/admin_models.dart';
import 'package:alliswell/src/features/ee/admin/ui/admin_login_screen.dart';
import 'package:alliswell/src/features/ee/admin/ui/admin_packages_screen.dart';
import 'package:alliswell/src/features/ee/admin/ui/admin_usage_screen.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/theme/theme.dart';

/// EE-033 — the operator console's screens. The route guard is proven in
/// test/router_redirect_test.dart; what these check is what the surfaces
/// SHOW: that the second factor is not optional on the form, that a seat
/// banner tells the truth in both directions, and that a limit nothing
/// enforces says so instead of implying it does.
Widget harness(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: Scaffold(body: child),
      ),
    );

InstanceUsage usage({int used = 8, int? max = 10, bool exceeded = false}) =>
    InstanceUsage.fromJson({
      'instance': {
        'teams': {'used': 2, 'max': 5},
      },
      'teams': [
        {
          'id': 'T1',
          'name': 'Acme',
          'slug': 'acme',
          'status': 'active',
          'packageName': 'Business',
          'seats': {
            'used': used,
            'pending': 0,
            'max': max,
            'remaining': max == null ? null : (max - used).clamp(0, max),
            'exceeded': exceeded,
            'canAdd': !exceeded && (max == null || used < max),
          },
          'workspaces': 4,
        },
        {
          'id': 'T2',
          'name': 'Globex',
          'slug': 'globex',
          'status': 'suspended',
          'packageName': 'Starter',
          'seats': {
            'used': 1,
            'pending': 0,
            'max': null,
            'remaining': null,
            'exceeded': false,
            'canAdd': true,
          },
          'workspaces': 1,
        },
      ],
    });

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AwI18n.instance.setActiveCached(const Locale('en'));
  });

  testWidgets('signing in asks for all three factors, always', (tester) async {
    await tester.pumpWidget(harness(const AdminLoginScreen()));
    await tester.pumpAndSettle();

    // Three fields, and the third is the one that makes this realm different
    // from every other sign-in in the app.
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.text('Authenticator code'), findsOneWidget);
    expect(find.text('Six digits from your authenticator app'), findsOneWidget);
    // The screen never claims a password alone will do.
    expect(find.textContaining('Forgot'), findsNothing);
  });

  testWidgets('the dashboard shows the fullest team first', (tester) async {
    await tester.pumpWidget(
      harness(
        const AdminUsageScreen(),
        overrides: [
          adminUsageProvider.overrideWith(
            (ref) async => usage(used: 9, max: 10),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // An operator opens this to find the team about to hit a wall, not to
    // read an alphabetical list.
    final acme = tester.getTopLeft(find.text('Acme')).dy;
    final globex = tester.getTopLeft(find.text('Globex')).dy;
    expect(acme, lessThan(globex));
    expect(find.text('9 of 10 seats'), findsOneWidget);
    // An uncapped team is not "0% full" — it says so in words.
    expect(find.text('1 seats · no limit'), findsOneWidget);
    expect(find.text('Suspended'), findsOneWidget);
  });

  testWidgets('being over the plan reads differently from being full', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const AdminUsageScreen(),
        overrides: [
          adminUsageProvider.overrideWith(
            (ref) async => usage(used: 12, max: 10, exceeded: true),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(find.text('12 of 10 seats'));
    final theme = buildAwTheme(Brightness.light);
    // The number that is already past the line is drawn as a problem, not as
    // an ordinary count.
    expect(label.style?.color, theme.colorScheme.error);
  });

  testWidgets('the package editor is built from the server dictionary', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const AdminPackagesScreen(),
        overrides: [
          adminPackagesProvider.overrideWith(
            (ref) async => [
              AdminPackage.fromJson({
                'id': 'P1',
                'name': 'Business',
                'limits': {'seats': 250},
                'isDefault': true,
              }),
            ],
          ),
          adminLimitKeysProvider.overrideWith(
            (ref) async => [
              LimitKeyInfo.fromJson({
                'key': 'seats',
                'kind': 'quota',
                'unit': 'count',
                'enforced': true,
              }),
              LimitKeyInfo.fromJson({
                'key': 'transcribe_minutes_monthly',
                'kind': 'quota',
                'unit': 'minutes/month',
                'enforced': false,
              }),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Default'), findsOneWidget);

    await tester.tap(find.text('Business'));
    await tester.pumpAndSettle();

    // Fields come from the dictionary, so a limit added on the server appears
    // here without an app release (EE-029's promise, kept on the client).
    expect(find.text('Seats'), findsOneWidget);
    expect(find.text('Transcription minutes per month'), findsOneWidget);
    // And the one nothing counts yet says so rather than implying a ceiling.
    expect(find.text('Stored, not enforced yet'), findsOneWidget);
  });
}
