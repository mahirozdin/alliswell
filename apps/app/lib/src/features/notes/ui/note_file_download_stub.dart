import 'dart:typed_data';

/// Not reachable off the web — `NoteFileSink` only calls this under `kIsWeb`.
Future<void> downloadNoteFile(
  Uint8List bytes,
  String filename,
  String mimeType,
) async => throw UnsupportedError('downloadNoteFile is web-only');
