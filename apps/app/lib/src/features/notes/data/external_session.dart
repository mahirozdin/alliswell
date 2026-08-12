/// The open external document, and the files we can get back to (OPH-251).
///
/// Two pieces of state, deliberately separate:
///   * [externalSessionProvider] — what is open RIGHT NOW, for as long as the
///     screen lives. W1's banner reads from it.
///   * [externalRecentsProvider] — the durable list (W6). Device-local, never
///     synced: a security-scoped bookmark resolves only on the device that
///     minted it, so syncing one would hand another device rows it cannot open
///     (ADR-0030 §1).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kv/local_kv.dart';
import 'external_document.dart';
import 'external_recents.dart';
import 'markdown_source.dart';

/// Where the recents list lives. `alliswell_*` per ADR-0003.
const String kExternalRecentsKey = 'alliswell_external_recents';

/// What is open, and what we may do to it.
class ExternalSession {
  const ExternalSession({required this.document, required this.access});

  final ExternalDocument document;

  /// Re-probed on resume and before every save, because a security scope
  /// expires and a persisted grant can be revoked. W3 is not a one-time
  /// answer.
  final ExternalAccess access;

  ExternalSession copyWith({
    ExternalDocument? document,
    ExternalAccess? access,
  }) => ExternalSession(
    document: document ?? this.document,
    access: access ?? this.access,
  );
}

class ExternalSessionNotifier extends Notifier<ExternalSession?> {
  @override
  ExternalSession? build() => null;

  MarkdownSource get _source => ref.read(markdownSourceProvider);

  void clear() => state = null;

  /// Opens the picker. Returns the refusal so the caller can say WHY nothing
  /// happened — "cancelled" and "this device cannot" deserve different words.
  Future<ExternalOpenRefusal?> pick() async =>
      _adopt(await _source.pickExternal());

  Future<ExternalOpenRefusal?> openHandle(ExternalDocHandle handle) async =>
      _adopt(await _source.open(handle));

  Future<ExternalOpenRefusal?> adoptOsToken(String osToken) async =>
      _adopt(await _source.adopt(osToken));

  Future<ExternalOpenRefusal?> _adopt(ExternalOpenResult result) async {
    switch (result) {
      case ExternalRefused(:final reason):
        // A handle that turned out to be gone should stop being offered.
        return reason;
      case ExternalOpened(:final document, :final access):
        state = ExternalSession(document: document, access: access);
        await ref
            .read(externalRecentsProvider.notifier)
            .remember(document.handle);
        return null;
    }
  }

  /// Re-asks the OS. Cheap, and the answer can differ from a minute ago.
  Future<void> reprobe() async {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      access: await _source.probe(current.document.handle),
    );
  }

  /// W5's reload leg: throw away our copy and take what is on disk.
  Future<ExternalOpenRefusal?> reload() async {
    final current = state;
    if (current == null) return null;
    return openHandle(current.document.handle);
  }

  /// Records a successful save so the next comparison uses the new bytes
  /// rather than the ones we opened with.
  void adoptStamp(ExternalDocStamp stamp, String markdown) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      document: ExternalDocument(
        handle: current.document.handle,
        markdown: markdown,
        encoding: current.document.encoding,
        stamp: stamp,
      ),
    );
  }
}

final externalSessionProvider =
    NotifierProvider<ExternalSessionNotifier, ExternalSession?>(
      ExternalSessionNotifier.new,
    );

/// The durable list (W6).
class ExternalRecents extends Notifier<List<ExternalDocHandle>> {
  @override
  List<ExternalDocHandle> build() {
    _hydrate();
    return const [];
  }

  Future<void> _hydrate() async {
    final raw = await localKv.get(kExternalRecentsKey);
    final parsed = parseExternalRecents(raw);
    if (parsed.isNotEmpty) state = parsed;
  }

  Future<void> remember(ExternalDocHandle handle) async {
    state = pushExternalRecent(state, handle);
    await _persist();
  }

  /// Binds a file to a project without importing it anywhere.
  Future<void> linkProject(String token, String? projectId) async {
    state = [
      for (final r in state)
        if (r.token == token) r.withProject(projectId) else r,
    ];
    await _persist();
  }

  /// A file that is gone stops being offered — a recents list of dead rows is
  /// worse than a short one.
  Future<void> forget(String token) async {
    state = dropExternalRecent(state, token);
    await _persist();
  }

  Future<void> _persist() =>
      localKv.set(kExternalRecentsKey, encodeExternalRecents(state));
}

final externalRecentsProvider =
    NotifierProvider<ExternalRecents, List<ExternalDocHandle>>(
      ExternalRecents.new,
    );
