import 'dart:typed_data';

/// One file the user picked, ready to upload (OPH-153).
///
/// `open()` must be RE-OPENABLE — retry after a failed PUT re-reads the
/// source (a path on io platforms, in-memory bytes on the web) instead of
/// consuming a one-shot stream.
class PickedUpload {
  const PickedUpload({
    required this.name,
    required this.sizeBytes,
    required this.open,
    this.mime,
  });

  /// In-memory convenience (web, tests).
  PickedUpload.fromBytes({
    required this.name,
    required Uint8List bytes,
    this.mime,
  }) : sizeBytes = bytes.length,
       open = ((b) =>
           () => Stream<List<int>>.value(b))(bytes);

  final String name;
  final int sizeBytes;
  final String? mime;

  /// Opens a fresh byte stream over the picked source.
  final Stream<List<int>> Function() open;
}
