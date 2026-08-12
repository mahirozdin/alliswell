/// Somebody else's file, as a set of types (ADR-0030, OPH-255).
///
/// DESIGN §29.5 governs writing back to a file the app did not create, and
/// opens by naming the stakes: this is the only feature in the round that can
/// destroy a user's data. Two of its rules are carried by the type system here
/// rather than by convention, because a convention is a thing you can forget:
///
///   * **W3 — a dead save button is forbidden.** `probe()` does not return a
///     bool. It returns [ExternalAccess], and only [ExternalWritable] carries
///     an [ExternalSaver]. In the other two arms there is nothing to bind a
///     save action to, so the button cannot be built — the compiler enforces
///     "absent, not present-and-failing" (§22). A bool would have let the UI
///     build it and disable it, which is the dead affordance the rule forbids.
///
///   * **W5 — never silently overwrite.** [SaveIntent.force] is reachable only
///     from a [SaveConflict], so "overwrite without asking" is not something
///     a caller can express.
///
/// Nothing here touches a disk or a platform channel. That is the point: the
/// whole decision layer is testable with a fake (OPH-255), and OPH-256 is then
/// three native implementations behind an interface that is already proven.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

/// How a handle's token is meant to be read by the platform that minted it.
enum ExternalHandleKind {
  /// Base64 security-scoped bookmark (macOS/iOS).
  appleBookmark,

  /// A `content://` URI we hold a persisted grant for (Android).
  androidUri,

  /// A filesystem path, where there is no sandbox to satisfy.
  plainPath,

  /// The grant lives only as long as this process: reopening has to go back
  /// through the OS picker. OPH-256's written fallback for the case where
  /// app-scope bookmarks are not honoured.
  sessionOnly,
}

/// A durable reference to an external document (W6).
///
/// [token] is opaque and platform-shaped — a bookmark, a URI, a path — and is
/// never interpreted here. It is stored device-locally and **never synced**:
/// a bookmark resolves only on the device that minted it, so syncing one would
/// hand another device a recents list it cannot open (ADR-0030 §1).
@immutable
class ExternalDocHandle {
  const ExternalDocHandle({
    required this.token,
    required this.kind,
    required this.displayName,
  });

  final String token;
  final ExternalHandleKind kind;

  /// The file's own name, as the OS gave it — what W1's banner shows.
  final String displayName;

  Map<String, dynamic> toJson() => {
    'token': token,
    'kind': kind.name,
    'name': displayName,
  };

  /// Null on anything malformed, so one bad row cannot poison the list.
  ///
  /// Unknown keys are ignored rather than rejected, which is what lets a later
  /// task (OPH-251's project link) add a field without stranding the entries
  /// already on disk.
  static ExternalDocHandle? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final token = raw['token'];
    final name = raw['name'];
    if (token is! String || token.isEmpty) return null;
    if (name is! String) return null;
    final kind = ExternalHandleKind.values
        .where((k) => k.name == raw['kind'])
        .firstOrNull;
    if (kind == null) return null;
    return ExternalDocHandle(token: token, kind: kind, displayName: name);
  }

  @override
  bool operator ==(Object other) =>
      other is ExternalDocHandle &&
      other.token == token &&
      other.kind == kind &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(token, kind, displayName);
}

/// What the file looked like when we opened it (W5).
///
/// All three are captured, with a stated order of authority: the hash is the
/// decider, [sizeBytes] is implied by it, and [modifiedAt] is a cheap
/// pre-filter — trustworthy on Apple, and **not** on Android, where SAF's
/// `COLUMN_LAST_MODIFIED` is optional and cloud providers return null.
@immutable
class ExternalDocStamp {
  const ExternalDocStamp({
    required this.sizeBytes,
    required this.sha256,
    this.modifiedAt,
  });

  factory ExternalDocStamp.of(List<int> bytes, {DateTime? modifiedAt}) =>
      ExternalDocStamp(
        sizeBytes: bytes.length,
        sha256: crypto.sha256.convert(bytes).toString(),
        modifiedAt: modifiedAt,
      );

  final int sizeBytes;
  final String sha256;
  final DateTime? modifiedAt;

  /// Same contents? Only the hash answers this. A file can be touched without
  /// changing, and — on the providers that report neither size nor mtime —
  /// rewritten without either moving.
  bool matches(ExternalDocStamp other) => sha256 == other.sha256;

  @override
  bool operator ==(Object other) =>
      other is ExternalDocStamp &&
      other.sizeBytes == sizeBytes &&
      other.sha256 == sha256 &&
      other.modifiedAt == modifiedAt;

  @override
  int get hashCode => Object.hash(sizeBytes, sha256, modifiedAt);
}

/// What the bytes turned out to be (W4).
enum ExternalEncoding {
  utf8,

  /// UTF-8 behind a `EF BB BF` byte-order mark, which must be put back on
  /// save — dropping it silently is a byte change nobody asked for.
  utf8Bom,

  /// Not decodable as UTF-8. The file still opens; it just never saves.
  notText,
}

/// Why a file opened but cannot be written.
enum ReadOnlyReason {
  /// The OS gave us read access only.
  permissionReadOnly,

  /// The provider itself does not support writing (Android `COLUMN_FLAGS`).
  providerNoWrite,

  /// The whole volume is mounted read-only.
  volumeReadOnly,

  /// W4: the bytes are not UTF-8, so a round-trip would rewrite bytes we never
  /// touched.
  notUtf8,

  /// W4: the note's canonical form is a Delta, so "Save to file" would write
  /// a reflowed document over a hand-formatted one.
  notMarkdownCanonical,
}

/// Why a handle we used to hold no longer reaches anything.
enum LostAccessReason {
  /// An Apple security scope that has expired or gone stale.
  scopeExpired,

  /// An Android persisted URI grant that was revoked.
  grantRevoked,

  /// The file was moved or deleted.
  fileGone,

  /// No plugin on this platform — the honest-unavailable idiom, not a failure.
  unsupportedPlatform,
}

/// Writes markdown back to the file. Obtainable **only** from
/// [ExternalWritable], which is what makes W3 a compile-time rule.
abstract class ExternalSaver {
  /// [encoding] comes from the document we OPENED, never from what is on disk
  /// at save time. After a conflict the bytes on disk are somebody else's, and
  /// re-deriving the encoding from them would let another writer's byte-order
  /// mark decide how our document is written.
  Future<SaveOutcome> save(
    String markdown, {
    required ExternalDocStamp expected,
    required ExternalEncoding encoding,
    required SaveIntent intent,
  });
}

/// [SaveIntent.force] exists so the three-way conflict choice can be expressed.
/// It is not a default anyone can reach by accident.
enum SaveIntent { ifUnchanged, force }

/// The result of probing a handle (W3).
sealed class ExternalAccess {
  const ExternalAccess();
}

final class ExternalWritable extends ExternalAccess {
  const ExternalWritable(this.saver);
  final ExternalSaver saver;
}

final class ExternalReadOnly extends ExternalAccess {
  const ExternalReadOnly(this.reason);
  final ReadOnlyReason reason;
}

final class ExternalUnreachable extends ExternalAccess {
  const ExternalUnreachable(this.reason);
  final LostAccessReason reason;
}

/// The result of a save (W5).
sealed class SaveOutcome {
  const SaveOutcome();
}

final class SaveSucceeded extends SaveOutcome {
  const SaveSucceeded(this.stamp);

  /// The file's new stamp, so the editor can keep comparing without re-reading.
  final ExternalDocStamp stamp;
}

final class SaveConflict extends SaveOutcome {
  const SaveConflict(this.onDisk);

  /// What is there now. The three-way choice is: reload (open the handle
  /// again), overwrite ([SaveIntent.force]), or save a copy.
  final ExternalDocStamp onDisk;
}

final class SaveLostAccess extends SaveOutcome {
  const SaveLostAccess(this.reason);
  final LostAccessReason reason;
}

final class SaveFailed extends SaveOutcome {
  const SaveFailed(this.code);
  final String code;
}

/// An external file, open.
@immutable
class ExternalDocument {
  const ExternalDocument({
    required this.handle,
    required this.markdown,
    required this.encoding,
    required this.stamp,
  });

  final ExternalDocHandle handle;

  /// The text as shown. For [ExternalEncoding.notText] this is a LOSSY decode
  /// — good enough to read, which is why the file opens at all, and never
  /// good enough to write, which is why access is read-only.
  final String markdown;
  final ExternalEncoding encoding;
  final ExternalDocStamp stamp;

  String get name => handle.displayName;
}

/// Why an open did not produce a document.
enum ExternalOpenRefusal { cancelled, gone, tooLarge, denied, unsupported }

sealed class ExternalOpenResult {
  const ExternalOpenResult();
}

final class ExternalOpened extends ExternalOpenResult {
  const ExternalOpened(this.document, this.access);
  final ExternalDocument document;
  final ExternalAccess access;
}

final class ExternalRefused extends ExternalOpenResult {
  const ExternalRefused(this.reason);
  final ExternalOpenRefusal reason;
}

/// The UTF-8 byte-order mark.
const List<int> kUtf8Bom = [0xEF, 0xBB, 0xBF];

/// Decoded text plus what it turned out to be.
typedef ExternalDecoded = ({String text, ExternalEncoding encoding});

/// W4's read edge: **strict**, and lossy only when there is no other way.
///
/// `markdown_source.dart` reads with `allowMalformed: true`, which is right
/// for reading — one stray byte should not cost the whole document. It is
/// exactly wrong for a round trip: it turns every non-UTF-8 byte into U+FFFD
/// and would write those replacement characters back into somebody's file.
///
/// So the strict decode runs first and decides. A file that fails it still
/// opens (refusing to SHOW a file is worse than refusing to write it) with a
/// lossy decode for display and [ExternalEncoding.notText] recorded, which is
/// what makes its access read-only. We do not guess Latin-1: a wrong guess
/// writes a corrupted file and looks like success.
ExternalDecoded decodeExternalBytes(List<int> bytes) {
  final hasBom =
      bytes.length >= 3 &&
      bytes[0] == kUtf8Bom[0] &&
      bytes[1] == kUtf8Bom[1] &&
      bytes[2] == kUtf8Bom[2];
  final body = hasBom ? bytes.sublist(3) : bytes;
  try {
    return (
      text: const Utf8Decoder(allowMalformed: false).convert(body),
      encoding: hasBom ? ExternalEncoding.utf8Bom : ExternalEncoding.utf8,
    );
  } on FormatException {
    return (
      text: const Utf8Decoder(allowMalformed: true).convert(body),
      encoding: ExternalEncoding.notText,
    );
  }
}

/// W4's write edge. Puts the byte-order mark back if the file had one.
///
/// Line endings are NOT normalised and no trailing newline is added: the file
/// belongs to somebody else, and the only bytes that should change are the
/// ones they changed.
///
/// Throws on [ExternalEncoding.notText] rather than writing something
/// plausible — reaching here means [canWriteBack] was not consulted, which is
/// a bug, not a runtime condition.
List<int> encodeExternalText(String text, ExternalEncoding encoding) {
  if (encoding == ExternalEncoding.notText) {
    throw StateError('refusing to write a non-UTF-8 document (W4)');
  }
  final body = utf8.encode(text);
  return encoding == ExternalEncoding.utf8Bom ? [...kUtf8Bom, ...body] : body;
}

/// Narrows an OS-level answer with what W4 knows about the bytes.
///
/// `probe()` answers the question the OS can answer: may this process write
/// these bytes. It cannot answer W4's question, which is whether writing them
/// back would change bytes the user never touched. A file can be perfectly
/// writable and still refuse to be written.
///
/// Shared rather than duplicated in each platform implementation, because it
/// is a POLICY decision — and policy that lives in three native files is
/// policy that will eventually disagree with itself.
ExternalAccess narrowForEncoding(
  ExternalAccess osAccess,
  ExternalEncoding encoding,
) => encoding == ExternalEncoding.notText && osAccess is ExternalWritable
    ? const ExternalReadOnly(ReadOnlyReason.notUtf8)
    : osAccess;

/// The single place W4's question is asked.
///
/// Both halves matter. A Delta-canonical note would be written back as a
/// REFLOW of somebody's hand-formatted file; a non-UTF-8 file would be written
/// back with its undecodable bytes replaced. Either is data loss with good
/// intentions, so both get "Save as a note" instead.
bool canWriteBack({
  required bool markdownCanonical,
  required ExternalEncoding encoding,
}) => markdownCanonical && encoding != ExternalEncoding.notText;
