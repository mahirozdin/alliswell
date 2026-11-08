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

/// OPH-409 (U-18) — the request queue's "all units" view.
///
/// A manager of eight units opened the queue onto the team's general space,
/// which is not a unit, and got "choose a unit" as the first picture of the
/// product. "All units" is now the queue's default wherever the selected
/// space is not one of the person's units; inside a unit the unit's own
/// queue stays the default (the person chose it), and the chip still offers
/// all of them. Choosing a unit chip clears the choice again.
final eeQueueAllUnitsChosenProvider =
    NotifierProvider<EeQueueAllUnitsChosen, bool>(EeQueueAllUnitsChosen.new);

class EeQueueAllUnitsChosen extends Notifier<bool> {
  @override
  bool build() {
    // A new person, or a new unit list, starts from the default.
    ref.watch(currentUserIdProvider);
    return false;
  }

  void set(bool value) => state = value;
}

/// True when the queue shows every unit's open requests (the live list)
/// instead of one unit's replica. Never on "unknown": with no answer about
/// units the queue draws what it always drew.
final eeQueueShowsAllUnitsProvider = Provider<bool>((ref) {
  final here = ref.watch(eeUnitHereProvider);
  return switch (here.state) {
    EeUnitHereState.unknown => false,
    EeUnitHereState.notUnit => here.units.isNotEmpty,
    EeUnitHereState.unit => ref.watch(eeQueueAllUnitsChosenProvider),
  };
});

/// R-15 — a unit opened only to read one of its requests, and what was open
/// before it.
///
/// The device holds one unit's copy at a time, so a request of another unit
/// is read by opening that unit (EE-267). That selection is the same one
/// Home and every other screen follow, and it used to stay: reading an İSG
/// request from "All units" silently made Home İSG. Now the unit is lent for
/// the reading — [from] is what was open before the first lend, [to] the
/// unit lent — and [EeUnitLoan.giveBack] restores it when the request
/// closes.
typedef EeLentUnit = ({String from, String to, bool allUnitsChosen});

final eeLentUnitProvider = NotifierProvider<EeUnitLoan, EeLentUnit?>(
  EeUnitLoan.new,
);

class EeUnitLoan extends Notifier<EeLentUnit?> {
  @override
  EeLentUnit? build() {
    // A new person starts with nothing lent.
    ref.watch(currentUserIdProvider);
    return null;
  }

  /// Opens [workspaceId] to read a request there. [keepAllUnits]: the
  /// request was opened from the across-units list, which stays on screen
  /// (E35 polish P-08) instead of turning into the lent unit's queue.
  Future<void> lend(String workspaceId, {bool keepAllUnits = false}) async {
    final here = ref.read(currentWorkspaceProvider).value?.id;
    final chosen = ref.read(eeQueueAllUnitsChosenProvider.notifier);
    if (here == null || here == workspaceId) {
      if (keepAllUnits) chosen.set(true);
      return;
    }
    final held = state;
    // A second lend (↓ to the next request, in yet another unit) keeps what
    // was open before the FIRST one: that is what comes back.
    state = (
      from: held?.from ?? here,
      to: workspaceId,
      allUnitsChosen:
          held?.allUnitsChosen ?? ref.read(eeQueueAllUnitsChosenProvider),
    );
    if (keepAllUnits) chosen.set(true);
    await ref.read(selectedWorkspaceIdProvider.notifier).select(workspaceId);
  }

  /// The request is closed: the unit open before comes back — unless the
  /// person moved somewhere else meanwhile, on purpose, which stands.
  Future<void> giveBack() async {
    final held = state;
    if (held == null) return;
    state = null;
    final here = ref.read(currentWorkspaceProvider).value?.id;
    if (here != held.to) return;
    ref.read(eeQueueAllUnitsChosenProvider.notifier).set(held.allUnitsChosen);
    await ref.read(selectedWorkspaceIdProvider.notifier).select(held.from);
  }

  /// The person chose a unit themselves: nothing is lent any more.
  void forget() => state = null;
}
