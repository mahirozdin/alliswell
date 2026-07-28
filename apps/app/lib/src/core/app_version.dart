import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app's version, mirrored from `pubspec.yaml`.
///
/// Flutter cannot read the pubspec at runtime without pulling in a
/// platform-channel package, so this is the one place the string lives in Dart.
/// It cannot drift: the release workflow refuses to publish a tag unless the
/// tag, `pubspec.yaml` and this constant all agree — which is exactly the check
/// the Settings screen's hardcoded "0.1.0" went three releases without.
const kAppVersion = '0.5.0';

final appVersionProvider = Provider<String>((_) => kAppVersion);
