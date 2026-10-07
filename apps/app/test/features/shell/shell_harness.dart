import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/app.dart';
import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/core/retry.dart';
import 'package:alliswell/src/features/auth/data/secret_store.dart';
import 'package:alliswell/src/features/auth/data/token_storage.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_bubble.dart';
import 'package:alliswell/src/router.dart';

import '../auth/test_support.dart';
import '../projects/fake_api.dart';
import '../../support/sync_overrides.dart';

/// The whole app, signed in, on a TEAM's address — the shell with the
/// service desk drawn (OPH-359's shell tests).
FakeApi teamApi() => FakeApi()
  ..eeState = 'active'
  ..eeFeatures = ['teams', 'itsm']
  ..eeBaseDomain = 'example.com';

Future<Widget> teamApp(
  FakeApi api, {
  List<Override> more = const [],
  String serverUrl = 'https://acme.example.com',
}) async {
  SharedPreferences.setMockInitialValues({});
  await resetQuickAccessPrefs();
  // The status cache is a process-wide singleton (see desk_tab_test).
  await localKv.remove('alliswell_ee_status::user-1');
  final store = InMemorySecretStore();
  await TokenStorage(store).save(fakeSession());
  return ProviderScope(
    retry: awRetry,
    overrides: [
      ...syncTestOverrides(),
      secretStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(
        fakeDio(FakeHttpClientAdapter(api.handle)),
      ),
      apiBaseUrlProvider.overrideWithValue(serverUrl),
      ...more,
    ],
    child: const AllisWellApp(),
  );
}

void sizeTo(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

GoRouter appRouter() => GoRouter.of(awRootNavigatorKey.currentContext!);
