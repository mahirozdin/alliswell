import 'dart:convert';

/// The two pure rules request tags need on the device (EE-235), in a file of
/// their own so the queue's filter and the tag providers can both read them
/// without importing each other.

/// OPH-350's column as a list: the JSON the server sent, or empty.
List<String> decodeTagNames(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw);
    return list is List ? [for (final name in list) '$name'] : const [];
  } on FormatException {
    // A malformed cell costs this row its chips, not the screen.
    return const [];
  }
}

/// The server's fold for "the same word" (`tickets/tags.js`): Turkish lower
/// case, so `İ`→`i` and `I`→`ı`, over trimmed, single-spaced text.
String foldTag(String name) {
  final text = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(switch (char) {
      'I' => 'ı',
      'İ' => 'i',
      _ => char.toLowerCase(),
    });
  }
  return buffer.toString();
}
