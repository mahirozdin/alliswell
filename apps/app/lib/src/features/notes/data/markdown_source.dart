/// Getting a `.md` file into the app (round 16 follow-up).
///
/// Two ways in, one model out:
///   * the user picks a file from inside the app, and
///   * the OS hands us one because AllisWell is registered to open `.md`
///     (Android `ACTION_VIEW`, iOS/macOS `CFBundleDocumentTypes`).
///
/// Reading a file needs a platform, so it sits behind [MarkdownSource] — tests
/// inject a fake and never touch a disk or a plugin.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'external_docref.dart';
import 'external_document.dart';

/// The extensions we claim. `.markdown` is the long form Jekyll and friends
/// write; `.mdown`/`.mkd` are old but still in the wild.
const kMarkdownExtensions = ['md', 'markdown', 'mdown', 'mkd'];

bool isMarkdownPath(String path) {
  final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
  return kMarkdownExtensions.contains(ext);
}

/// A markdown file the user wants to read or import.
@immutable
class MarkdownDocument {
  const MarkdownDocument({required this.name, required this.markdown});

  /// The file's own name, e.g. `yayla-plani.md` — shown as provenance so an
  /// imported note says where it came from.
  final String name;
  final String markdown;

  /// The name without its extension, used as the note title when the document
  /// has no leading `# H1`.
  String get baseName => p.basenameWithoutExtension(name);

  @override
  bool operator ==(Object other) =>
      other is MarkdownDocument &&
      other.name == name &&
      other.markdown == markdown;

  @override
  int get hashCode => Object.hash(name, markdown);
}

/// A file bigger than this is not a note someone typed — it is a data dump, and
/// converting it would freeze the UI. Refused with an honest message.
const kMarkdownMaxBytes = 2 * 1024 * 1024;

class MarkdownTooLarge implements Exception {
  const MarkdownTooLarge(this.bytes);
  final int bytes;
}

abstract class MarkdownSource {
  /// Opens the system picker. Null when the user backs out.
  Future<MarkdownDocument?> pick();

  /// Reads a path the OS handed us.
  Future<MarkdownDocument?> read(String path);

  // ── The write edge (ADR-0030, OPH-255) ────────────────────────────────────
  //
  // [pick] and [read] both throw the file's IDENTITY away — `pick` reads only
  // `file.name` and `file.readAsBytes()`, and `read` drops the path it was
  // given. That was fine while importing was the only thing we did with a
  // file. It is the first thing that has to change for OPH-251, because you
  // cannot save back to something you did not keep a handle on.

  /// Opens the system picker for a document we intend to EDIT, keeping a
  /// durable handle to it.
  ///
  /// Not the same call as [pick]: `file_picker` hands iOS a copy
  /// (`asCopy: true`, always — ADR-0030 §Context), so import and edit cannot
  /// share a picker.
  Future<ExternalOpenResult> pickExternal();

  /// Reopens a handle from the recents list (W6), or re-reads it after a
  /// conflict (W5's "reload" leg).
  Future<ExternalOpenResult> open(ExternalDocHandle handle);

  /// Turns a token the OS handed us — a URL on Apple, a `content://` URI on
  /// Android — into a durable handle we can come back to.
  Future<ExternalOpenResult> adopt(String osToken);

  /// W3: asks whether this handle can be written RIGHT NOW.
  ///
  /// Cheap, and meant to be re-asked — on resume, and again immediately before
  /// a save. A security scope expires; a persisted grant can be revoked.
  Future<ExternalAccess> probe(ExternalDocHandle handle);
}

class PlatformMarkdownSource implements MarkdownSource {
  const PlatformMarkdownSource({
    this.docRef = const DocRefSource(maxBytes: kMarkdownMaxBytes),
  });

  /// The write edge (ADR-0030). Injectable so a test can drive the mapping
  /// without a channel; the app always gets the real one.
  final DocRefSource docRef;

  @override
  Future<ExternalOpenResult> pickExternal() => docRef.pickExternal();

  @override
  Future<ExternalOpenResult> open(ExternalDocHandle handle) =>
      docRef.open(handle);

  @override
  Future<ExternalOpenResult> adopt(String osToken) => docRef.adopt(osToken);

  @override
  Future<ExternalAccess> probe(ExternalDocHandle handle) =>
      docRef.probe(handle);

  @override
  Future<MarkdownDocument?> pick() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: kMarkdownExtensions,
    );
    final file = result?.files.singleOrNull;
    if (file == null) return null;
    // Checked BEFORE reading: the point is not to pull a huge file into memory.
    if (file.size > kMarkdownMaxBytes) throw MarkdownTooLarge(file.size);
    return MarkdownDocument(
      name: file.name,
      markdown: _decode(await file.readAsBytes()),
    );
  }

  @override
  Future<MarkdownDocument?> read(String path) async {
    if (kIsWeb) return null; // no filesystem to read from
    final file = File(path);
    if (!await file.exists()) return null;
    final length = await file.length();
    if (length > kMarkdownMaxBytes) throw MarkdownTooLarge(length);
    return MarkdownDocument(
      name: p.basename(path),
      markdown: _decode(await file.readAsBytes()),
    );
  }

  /// Markdown in the wild is UTF-8, but a file written by an older Windows
  /// editor may not be — decoding strictly would throw on a single stray byte
  /// and lose the whole document, so malformed sequences become U+FFFD.
  static String _decode(List<int> bytes) =>
      const Utf8Decoder(allowMalformed: true).convert(bytes);
}

final markdownSourceProvider = Provider<MarkdownSource>(
  (ref) => const PlatformMarkdownSource(),
);
