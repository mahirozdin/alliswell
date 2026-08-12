/// The recently-opened external files list (DESIGN §29.5 W6, OPH-255).
///
/// W6 is not a nicety: "a file the OS handed us once is otherwise unreachable
/// forever" — §22 again. A security-scoped bookmark or a persisted `content://`
/// grant is the only way back to that file without making the user hunt for it
/// in a picker a second time.
///
/// Modelled on `quick_access/emoji_input.dart`'s recents (most-recent-first,
/// deduplicated, capped, tolerant of junk), with **one deliberate difference**:
/// emoji recents join with a comma because an emoji cannot contain one. A
/// `content://` URI and a base64 bookmark both can, so these are a JSON array.
library;

import 'dart:convert';

import 'external_document.dart';

/// Enough to cover "the files I am actually working on", short enough that the
/// list stays scannable.
const int kExternalRecentsLimit = 12;

/// Reads the stored list, dropping anything that no longer parses.
///
/// Tolerant like every other stored preference: a handle written by an older
/// build, or plain junk, is skipped rather than thrown — losing one row beats
/// losing the list.
List<ExternalDocHandle> parseExternalRecents(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];

  final out = <ExternalDocHandle>[];
  final seen = <String>{};
  for (final entry in decoded) {
    final handle = ExternalDocHandle.fromJson(entry);
    if (handle == null || !seen.add(handle.token)) continue;
    out.add(handle);
    if (out.length == kExternalRecentsLimit) break;
  }
  return out;
}

/// Most-recent-first, deduplicated **by token**, capped.
///
/// Dedup is on the token, not the whole handle: reopening a file whose name
/// changed on disk is the same file, and should move to the top rather than
/// appear twice. Re-minting a stale bookmark also lands here, which is why the
/// incoming handle wins over the stored one.
List<ExternalDocHandle> pushExternalRecent(
  List<ExternalDocHandle> recents,
  ExternalDocHandle handle,
) {
  final out = [handle, ...recents.where((r) => r.token != handle.token)];
  return out.length <= kExternalRecentsLimit
      ? out
      : out.sublist(0, kExternalRecentsLimit);
}

/// Removes a handle — for a file that turned out to be gone.
List<ExternalDocHandle> dropExternalRecent(
  List<ExternalDocHandle> recents,
  String token,
) => [
  for (final r in recents)
    if (r.token != token) r,
];

String encodeExternalRecents(List<ExternalDocHandle> recents) =>
    jsonEncode([for (final r in recents) r.toJson()]);
