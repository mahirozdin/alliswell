import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings became an index of five groups (OPH-260, DESIGN §32), so a row
/// that used to sit on the root now lives one level down.
///
/// Shared rather than copied into each suite: the next regrouping should be one
/// edit, not five.
Future<void> openSettingsGroup(WidgetTester tester, String groupKey) async {
  await tester.tap(find.byIcon(Icons.settings_outlined).first);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(groupKey)));
  await tester.pumpAndSettle();
}

const kSettingsGeneral = 'settings-group-general';
const kSettingsNotifications = 'settings-group-notifications';
const kSettingsData = 'settings-group-data';
const kSettingsAccount = 'settings-group-account';
const kSettingsIntegrations = 'settings-group-integrations';
