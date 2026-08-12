import 'dart:convert';

import 'package:alliswell/src/features/notes/data/external_document.dart';
import 'package:alliswell/src/features/notes/data/markdown_source.dart';

/// A [MarkdownSource] whose filesystem is a Map (OPH-255).
///
/// The write edge is the one that can destroy a user's data, so every state it
/// has to survive — read-only, an expired scope, a revoked grant, a file that
/// changed underneath — is scriptable here and reachable with no disk and no
/// platform channel. OPH-256's native code then has to satisfy an interface
/// that is already proven rather than one that is merely written down.
class FakeMarkdownSource implements MarkdownSource {
  FakeMarkdownSource({
    this.picked,
    this.files = const {},
    Map<String, FakeExternalFile>? external,
    this.pickExternalToken,
  }) : external = external ?? {};

  // ── The legacy import edge ────────────────────────────────────────────────
  final MarkdownDocument? picked;
  final Map<String, String> files;
  final List<String> reads = [];
  var pickCalls = 0;

  // ── The write edge ────────────────────────────────────────────────────────

  /// token → file.
  final Map<String, FakeExternalFile> external;

  /// What [pickExternal] returns; null means the user backed out.
  String? pickExternalToken;

  /// Tokens whose security scope has died. Probing one is unreachable.
  final Set<String> expiredTokens = {};

  /// Tokens whose grant vanishes at save time — writable a moment ago, gone
  /// when it mattered. The gap W3 exists to make survivable.
  final Set<String> revokeOnSave = {};

  /// Applied ONCE, immediately before the next save of that token: somebody
  /// else's editor wrote the file while ours was open (W5).
  final Map<String, String> mutateBeforeNextSave = {};

  /// Every write that reached "disk", in order.
  final List<({String token, List<int> bytes, SaveIntent intent})> writes = [];

  @override
  Future<MarkdownDocument?> pick() async {
    pickCalls++;
    return picked;
  }

  @override
  Future<MarkdownDocument?> read(String path) async {
    reads.add(path);
    final markdown = files[path];
    if (markdown == null) return null;
    return MarkdownDocument(name: path.split('/').last, markdown: markdown);
  }

  @override
  Future<ExternalOpenResult> pickExternal() async {
    final token = pickExternalToken;
    if (token == null) {
      return const ExternalRefused(ExternalOpenRefusal.cancelled);
    }
    return open(_handleFor(token));
  }

  @override
  Future<ExternalOpenResult> adopt(String osToken) async =>
      open(_handleFor(osToken));

  @override
  Future<ExternalOpenResult> open(ExternalDocHandle handle) async {
    final file = external[handle.token];
    if (file == null) return const ExternalRefused(ExternalOpenRefusal.gone);
    if (file.bytes.length > kMarkdownMaxBytes) {
      return const ExternalRefused(ExternalOpenRefusal.tooLarge);
    }
    final decoded = decodeExternalBytes(file.bytes);
    return ExternalOpened(
      ExternalDocument(
        handle: _handleFor(handle.token),
        markdown: decoded.text,
        encoding: decoded.encoding,
        stamp: ExternalDocStamp.of(file.bytes, modifiedAt: file.modifiedAt),
      ),
      narrowForEncoding(await probe(handle), decoded.encoding),
    );
  }

  @override
  Future<ExternalAccess> probe(ExternalDocHandle handle) async {
    if (expiredTokens.contains(handle.token)) {
      return const ExternalUnreachable(LostAccessReason.scopeExpired);
    }
    final file = external[handle.token];
    if (file == null) {
      return const ExternalUnreachable(LostAccessReason.fileGone);
    }
    if (!file.writable) {
      return const ExternalReadOnly(ReadOnlyReason.permissionReadOnly);
    }
    return ExternalWritable(_FakeSaver(this, handle.token));
  }

  ExternalDocHandle _handleFor(String token) => ExternalDocHandle(
    token: token,
    kind: ExternalHandleKind.plainPath,
    displayName: external[token]?.name ?? token.split('/').last,
  );
}

/// One file in the fake's filesystem.
class FakeExternalFile {
  FakeExternalFile({
    required this.name,
    required List<int> bytes,
    this.writable = true,
    this.modifiedAt,
  }) : bytes = List.of(bytes);

  FakeExternalFile.text(
    String name,
    String text, {
    bool writable = true,
    DateTime? modifiedAt,
  }) : this(
         name: name,
         bytes: utf8.encode(text),
         writable: writable,
         modifiedAt: modifiedAt,
       );

  final String name;
  List<int> bytes;
  bool writable;
  DateTime? modifiedAt;
}

class _FakeSaver implements ExternalSaver {
  _FakeSaver(this.source, this.token);

  final FakeMarkdownSource source;
  final String token;

  @override
  Future<SaveOutcome> save(
    String markdown, {
    required ExternalDocStamp expected,
    required ExternalEncoding encoding,
    required SaveIntent intent,
  }) async {
    // Scripted mutation lands BEFORE the check, which is the only ordering
    // that reproduces the race W5 is about.
    final pending = source.mutateBeforeNextSave.remove(token);
    final file = source.external[token];
    if (pending != null && file != null) file.bytes = utf8.encode(pending);

    if (source.revokeOnSave.contains(token)) {
      return const SaveLostAccess(LostAccessReason.grantRevoked);
    }
    if (file == null) {
      return const SaveLostAccess(LostAccessReason.fileGone);
    }

    final onDisk = ExternalDocStamp.of(file.bytes, modifiedAt: file.modifiedAt);
    if (intent == SaveIntent.ifUnchanged && !onDisk.matches(expected)) {
      return SaveConflict(onDisk);
    }

    // The encoding the DOCUMENT arrived with, so a file opened with a BOM
    // keeps it (W4) even when a conflicting writer dropped theirs.
    final bytes = encodeExternalText(markdown, encoding);
    file.bytes = bytes;
    source.writes.add((token: token, bytes: bytes, intent: intent));
    return SaveSucceeded(
      ExternalDocStamp.of(bytes, modifiedAt: file.modifiedAt),
    );
  }
}
