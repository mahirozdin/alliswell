/// Turning the plugin's maps into the sealed types (ADR-0030, OPH-256).
///
/// The channel speaks maps because a method channel has to. Everything past
/// this file speaks [ExternalAccess] and [SaveOutcome], so an unknown string
/// from native cannot become a writable file by accident — every unrecognised
/// value falls to the most conservative answer, which is "you may not write".
library;

import 'dart:typed_data';

import 'package:alliswell_docref/alliswell_docref.dart';

import 'external_document.dart';

/// The platform implementation of the write edge.
class DocRefSource {
  const DocRefSource({
    this.plugin = const AlliswellDocref(),
    required this.maxBytes,
  });

  final AlliswellDocref plugin;
  final int maxBytes;

  Future<ExternalOpenResult> pickExternal() async =>
      _opened(await plugin.pickExternal(maxBytes: maxBytes));

  Future<ExternalOpenResult> open(ExternalDocHandle handle) async => _opened(
    await plugin.open(
      token: handle.token,
      kind: handle.kind.name,
      maxBytes: maxBytes,
    ),
  );

  Future<ExternalOpenResult> adopt(String osToken) async =>
      _opened(await plugin.adopt(osToken: osToken, maxBytes: maxBytes));

  Future<ExternalAccess> probe(ExternalDocHandle handle) async {
    final map = await plugin.probe(token: handle.token, kind: handle.kind.name);
    // No plugin on this platform: honest-unavailable, and — the point of the
    // sealed type — still no saver, so still no button.
    if (map == null) {
      return const ExternalUnreachable(LostAccessReason.unsupportedPlatform);
    }
    return _access(map, handle);
  }

  /// The document the OS opened while Dart was not listening, if any.
  Future<String?> takeOpenedDocument() async =>
      (await plugin.takeOpenedDocument())?['osToken'] as String?;

  Future<({String? html, Uint8List? imageBytes, String? imageMime})>
  clipboardRead() async {
    final map = await plugin.clipboardRead();
    return (
      html: map?['html'] as String?,
      imageBytes: map?['imageBytes'] as Uint8List?,
      imageMime: map?['imageMime'] as String?,
    );
  }

  // ── Mapping ────────────────────────────────────────────────────────────────

  ExternalOpenResult _opened(Map<Object?, Object?>? map) {
    if (map == null) {
      return const ExternalRefused(ExternalOpenRefusal.unsupported);
    }
    final refused = map['refused'];
    if (refused is String) return ExternalRefused(_refusal(refused));

    final bytes = map['bytes'];
    final token = map['token'];
    if (bytes is! Uint8List || token is! String) {
      return const ExternalRefused(ExternalOpenRefusal.gone);
    }

    final handle = ExternalDocHandle(
      token: token,
      kind: _kind(map['kind']),
      displayName: (map['name'] as String?) ?? token,
    );
    final decoded = decodeExternalBytes(bytes);
    final modified = map['modifiedAtMs'];

    final osAccess = (map['writable'] as bool?) ?? false
        ? ExternalWritable(_DocRefSaver(this, handle, decoded.encoding))
        : const ExternalReadOnly(ReadOnlyReason.permissionReadOnly);

    return ExternalOpened(
      ExternalDocument(
        handle: handle,
        markdown: decoded.text,
        encoding: decoded.encoding,
        stamp: ExternalDocStamp.of(
          bytes,
          modifiedAt: modified is int
              ? DateTime.fromMillisecondsSinceEpoch(modified)
              : null,
        ),
      ),
      // W4 narrows what the OS said: a file can be perfectly writable and
      // still refuse to be written.
      narrowForEncoding(osAccess, decoded.encoding),
    );
  }

  ExternalAccess _access(Map<Object?, Object?> map, ExternalDocHandle handle) {
    final reason = map['reason'] as String? ?? '';
    return switch (map['state']) {
      'writable' => ExternalWritable(
        // The encoding is not known from a probe alone; the caller re-checks
        // it with `canWriteBack` before offering the action, and the saver
        // takes it as an argument anyway.
        _DocRefSaver(this, handle, ExternalEncoding.utf8),
      ),
      'readOnly' => ExternalReadOnly(switch (reason) {
        'providerNoWrite' => ReadOnlyReason.providerNoWrite,
        'volumeReadOnly' => ReadOnlyReason.volumeReadOnly,
        _ => ReadOnlyReason.permissionReadOnly,
      }),
      // Anything unrecognised lands here, not on the writable arm.
      _ => ExternalUnreachable(_lost(reason)),
    };
  }

  static ExternalOpenRefusal _refusal(String raw) => switch (raw) {
    'cancelled' => ExternalOpenRefusal.cancelled,
    'tooLarge' => ExternalOpenRefusal.tooLarge,
    'denied' => ExternalOpenRefusal.denied,
    'unsupported' => ExternalOpenRefusal.unsupported,
    _ => ExternalOpenRefusal.gone,
  };

  static LostAccessReason _lost(String raw) => switch (raw) {
    'grantRevoked' => LostAccessReason.grantRevoked,
    'fileGone' => LostAccessReason.fileGone,
    'unsupportedPlatform' => LostAccessReason.unsupportedPlatform,
    _ => LostAccessReason.scopeExpired,
  };

  static ExternalHandleKind _kind(Object? raw) => switch (raw) {
    'androidUri' => ExternalHandleKind.androidUri,
    'plainPath' => ExternalHandleKind.plainPath,
    'sessionOnly' => ExternalHandleKind.sessionOnly,
    _ => ExternalHandleKind.appleBookmark,
  };
}

class _DocRefSaver implements ExternalSaver {
  _DocRefSaver(this.source, this.handle, this.openedAs);

  final DocRefSource source;
  final ExternalDocHandle handle;

  /// Kept so a probe-derived saver still writes the byte-order mark the
  /// document arrived with, even when the caller passes nothing better.
  final ExternalEncoding openedAs;

  @override
  Future<SaveOutcome> save(
    String markdown, {
    required ExternalDocStamp expected,
    required ExternalEncoding encoding,
    required SaveIntent intent,
  }) async {
    final bytes = encodeExternalText(
      markdown,
      encoding == ExternalEncoding.notText ? openedAs : encoding,
    );
    final map = await source.plugin.save(
      token: handle.token,
      kind: handle.kind.name,
      bytes: Uint8List.fromList(bytes),
      expectedSha256: expected.sha256,
      force: intent == SaveIntent.force,
    );
    if (map == null) {
      return const SaveLostAccess(LostAccessReason.unsupportedPlatform);
    }

    final size = map['sizeBytes'];
    final modified = map['modifiedAtMs'];
    ExternalDocStamp stampFrom(String sha) => ExternalDocStamp(
      sizeBytes: size is int ? size : bytes.length,
      sha256: sha,
      modifiedAt: modified is int
          ? DateTime.fromMillisecondsSinceEpoch(modified)
          : null,
    );

    return switch (map['outcome']) {
      'ok' => SaveSucceeded(stampFrom(map['sha256'] as String? ?? _sha(bytes))),
      'conflict' => SaveConflict(stampFrom(map['sha256'] as String? ?? '')),
      'lostAccess' => SaveLostAccess(
        DocRefSource._lost(map['reason'] as String? ?? ''),
      ),
      // An unknown outcome is a failure, never a success.
      _ => SaveFailed(map['reason'] as String? ?? 'unknown'),
    };
  }

  static String _sha(List<int> bytes) => ExternalDocStamp.of(bytes).sha256;
}
