import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:alliswell/src/features/ee/data/ee_models.dart';
import 'package:alliswell/src/features/ee/providers.dart';

/// A permission answer fixed for a screen test (OPH-356).
///
/// `canProvider` answers no while the permissions load, and the units list
/// and the service glances read them too — so a screen pumped on its own,
/// with nobody signed in, must be HANDED an answer rather than left to start
/// a sign-in restore it has no use for.
class FixedPermissions extends EePermissionsController {
  FixedPermissions(this.value);
  final EePermissions value;

  @override
  Future<EePermissions> build() async => value;
}

/// [permissions] — ungoverned by default: every verb, as on a plain build.
Override fixedPermissions([
  EePermissions permissions = EePermissions.unknown,
]) => eePermissionsProvider.overrideWith(() => FixedPermissions(permissions));
