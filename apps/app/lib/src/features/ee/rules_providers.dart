import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/providers.dart';
import 'data/rules_api.dart';
import 'data/rules_models.dart';
import 'providers.dart';

/// EE-308 — the rules screen's state.
///
/// Every mutation re-reads the list (the SLA admin idiom): the server may have
/// refused, cleared a pause or placed a copy, and one request back means the
/// screen cannot disagree with what was stored. The one exception is the
/// ORDER, which is optimistic — a dragged row must not jump back while the
/// request is in flight — and on any refusal the list is re-read and the
/// error rethrown so the screen can say why.
final eeRulesApiProvider = Provider<EeRulesApi>(
  (ref) => EeRulesApi(ref.watch(apiClientProvider)),
);

/// What the editors may offer. Null when the team is not this person's to
/// shape (403/404) — the editors then say so instead of offering nothing.
final eeRuleOptionsProvider = FutureProvider.autoDispose<EeRuleOptions?>((
  ref,
) async {
  if (!ref.watch(eeFeatureProvider('teams'))) return null;
  return ref.watch(eeRulesApiProvider).options();
});

final eeAutomationRulesProvider =
    AsyncNotifierProvider<EeAutomationRulesController, List<EeAutomationRule>?>(
      EeAutomationRulesController.new,
    );

class EeAutomationRulesController
    extends AsyncNotifier<List<EeAutomationRule>?> {
  @override
  Future<List<EeAutomationRule>?> build() async {
    if (!ref.watch(eeFeatureProvider('teams'))) return null;
    return ref.watch(eeRulesApiProvider).loadAutomation();
  }

  EeRulesApi get _api => ref.read(eeRulesApiProvider);

  Future<T> _then<T>(Future<T> Function(EeRulesApi api) action) async {
    try {
      return await action(_api);
    } finally {
      state = await AsyncValue.guard(_api.loadAutomation);
    }
  }

  /// A create (no [before]) or a PATCH of only what moved. Returns the id.
  Future<String> save(EeAutomationRule? before, EeAutomationRule after) =>
      _then((api) async {
        final body = after.changesFrom(before);
        if (before == null) return api.createAutomation(body);
        if (body.isNotEmpty || before.paused) {
          await api.patchAutomation(before.id, body);
        }
        return before.id;
      });

  Future<void> setEnabled(EeAutomationRule rule, bool enabled) =>
      _then((api) => api.patchAutomation(rule.id, {'enabled': enabled}));

  /// A paused rule runs again — any PATCH clears the pause on the server.
  Future<void> resume(EeAutomationRule rule) =>
      _then((api) => api.patchAutomation(rule.id, {'enabled': true}));

  Future<String> duplicate(String id) =>
      _then((api) => api.duplicateAutomation(id));

  Future<void> delete(String id) => _then((api) => api.deleteAutomation(id));

  Future<void> reorder(List<String> ids) async {
    final current = state.value;
    if (current != null) {
      final byId = {for (final r in current) r.id: r};
      state = AsyncData([
        for (final id in ids)
          if (byId[id] != null) byId[id]!,
      ]);
    }
    try {
      await _api.reorderAutomation(ids);
    } catch (_) {
      state = await AsyncValue.guard(_api.loadAutomation);
      rethrow;
    }
  }
}

final eeRoutingRulesProvider =
    AsyncNotifierProvider<
      EeRoutingRulesController,
      List<EeClassificationRule>?
    >(EeRoutingRulesController.new);

class EeRoutingRulesController
    extends AsyncNotifier<List<EeClassificationRule>?> {
  @override
  Future<List<EeClassificationRule>?> build() async {
    if (!ref.watch(eeFeatureProvider('teams'))) return null;
    return ref.watch(eeRulesApiProvider).loadRouting();
  }

  EeRulesApi get _api => ref.read(eeRulesApiProvider);

  Future<T> _then<T>(Future<T> Function(EeRulesApi api) action) async {
    try {
      return await action(_api);
    } finally {
      state = await AsyncValue.guard(_api.loadRouting);
    }
  }

  /// A new rule goes LAST (first match wins, so a new rule must not silently
  /// take requests from the rules above it); an edit sends only what moved.
  Future<String> save(
    EeClassificationRule? before,
    EeClassificationRule after,
  ) => _then((api) async {
    final body = after.changesFrom(before);
    if (before == null) {
      final current = state.value ?? const <EeClassificationRule>[];
      final last = current.fold<int>(
        -1,
        (top, r) => r.position > top ? r.position : top,
      );
      return api.createRouting({...body, 'position': last + 1});
    }
    if (body.isNotEmpty) await api.patchRouting(before.id, body);
    return before.id;
  });

  Future<void> setEnabled(EeClassificationRule rule, bool enabled) =>
      _then((api) => api.patchRouting(rule.id, {'enabled': enabled}));

  Future<String> duplicate(String id) =>
      _then((api) => api.duplicateRouting(id));

  Future<void> delete(String id) => _then((api) => api.deleteRouting(id));

  Future<void> reorder(List<String> ids) async {
    final current = state.value;
    if (current != null) {
      final byId = {for (final r in current) r.id: r};
      state = AsyncData([
        for (final id in ids)
          if (byId[id] != null) byId[id]!,
      ]);
    }
    try {
      await _api.reorderRouting(ids);
    } catch (_) {
      state = await AsyncValue.guard(_api.loadRouting);
      rethrow;
    }
  }
}
