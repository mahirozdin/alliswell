import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/ee/new_ticket_providers.dart';
import 'package:alliswell/src/features/ee/ticket_drafts_providers.dart';
import 'package:alliswell/src/screens/home_shell.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// N2 (UI-AUDIT retest): a request draft written offline in the person's own
/// workspace waited on the device until somebody pressed "try again".
///
/// The courier that carries it (EE-225) was kept alive by the home shell —
/// and a page opened by its address ("my requests" after a reload, where the
/// retest stood) is not inside the shell. The app itself keeps it now, so it
/// runs whatever page is on screen, the shell's or not.
void main() {
  testWidgets('the draft courier and the "sent" listener run with no shell '
      'on screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var courierBuilt = 0;
    await tester.pumpWidget(
      ProviderScope(
        retry: awRetry,
        overrides: [
          ...syncTestOverrides(),
          secretStoreProvider.overrideWithValue(InMemorySecretStore()),
          apiClientProvider.overrideWithValue(
            fakeDio(FakeHttpClientAdapter(FakeApi().handle)),
          ),
          draftCourierProvider.overrideWith((ref) {
            courierBuilt += 1;
            return null;
          }),
        ],
        child: const AllisWellApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Signed out: the sign-in page, and no shell anywhere in the tree.
    expect(find.byType(HomeShell), findsNothing);
    expect(courierBuilt, greaterThan(0));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    expect(container.exists(sentDraftsProvider), isTrue);
  });
}
