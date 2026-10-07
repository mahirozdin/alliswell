import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/kv/local_kv.dart';
import '../workspaces/workspaces.dart';
import 'data/unit_tickets_api.dart';
import 'providers.dart';
import 'unit_tickets_providers.dart';

/// Which units this person works in (OPH-359, UI-AUDIT #29).
///
/// The desk's lists — requests, knowledge base, changes, problems, meetings —
/// each show ONE workspace's copy, the selected one. After sign-in that is the
/// team's general space, which is not a unit, so every one of those lists said
/// "nothing in this unit" while the person's units were full of work. The
/// lists need to tell "this is a unit and it is empty" from "this is not a
/// unit at all", and only the server knows which workspaces are units: its
/// across-units answer (`/ee/team/tickets/my-units`) names them, so that is
/// what is asked — once, one row, alerts only.
///
/// The last answer is kept per person, so a device with no signal still
/// knows; with no answer ever, it is null and the lists behave as before.
final eeMyUnitsScopeProvider = FutureProvider<List<EeUnitScope>?>((ref) async {
  if (!ref.watch(eeFeatureProvider('teams'))) return null;
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  // Asked again whenever the person's workspace list is: joining or leaving
  // a unit changes both.
  ref.watch(workspacesProvider);
  final key = '$kEeMyUnitsCachePrefix$userId';
  try {
    final page = await ref
        .watch(eeUnitTicketsApiProvider)
        .list(alertsOnly: true, limit: 1);
    await localKv.set(
      key,
      jsonEncode([
        for (final u in page.units)
          {
            'unitId': u.unitId,
            'unitName': u.unitName,
            'workspaceId': u.workspaceId,
          },
      ]),
    );
    return page.units;
  } catch (_) {
    final cached = await localKv.get(key);
    if (cached == null) return null;
    try {
      return [
        for (final u in jsonDecode(cached) as List)
          EeUnitScope.fromJson((u as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return null;
    }
  }
});

const String kEeMyUnitsCachePrefix = 'alliswell_ee_my_units::';

/// Where the selected workspace stands among this person's units.
enum EeUnitHereState {
  /// Not known (no team feature, still loading, never answered): the lists
  /// draw what they always drew.
  unknown,

  /// The selected workspace is one of this person's units.
  unit,

  /// It is not a unit — the team's general space, or one's own.
  notUnit,
}

typedef EeUnitHere = ({
  EeUnitHereState state,
  EeUnitScope? unit,
  List<EeUnitScope> units,
});

final eeUnitHereProvider = Provider<EeUnitHere>((ref) {
  final units = ref.watch(eeMyUnitsScopeProvider).value;
  // Nothing known about units: nothing else is asked either.
  if (units == null) {
    return (state: EeUnitHereState.unknown, unit: null, units: const []);
  }
  final here = ref.watch(currentWorkspaceProvider.select((w) => w.value?.id));
  if (here == null) {
    return (state: EeUnitHereState.unknown, unit: null, units: const []);
  }
  for (final unit in units) {
    if (unit.workspaceId == here) {
      return (state: EeUnitHereState.unit, unit: unit, units: units);
    }
  }
  return (state: EeUnitHereState.notUnit, unit: null, units: units);
});
