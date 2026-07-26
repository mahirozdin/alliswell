import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'picked_upload.dart';

/// io platforms: picked files come back as PATHS and are streamed from disk
/// at upload time — a video never has to fit in memory, and `open()` is
/// naturally re-openable for retries.
Future<List<PickedUpload>> pickUploads() async {
  // file_picker 12: `withData` is gone (bytes are pulled on demand via
  // PlatformFile.readAsBytes) and multi-select is `pickFiles`' own behaviour —
  // `pickFile` is the single-file call.
  final result = await FilePicker.pickFiles();
  if (result == null) return const [];
  return [
    for (final f in result.files)
      if (f.path != null)
        PickedUpload(
          name: f.name,
          sizeBytes: f.size,
          open: ((path) =>
              () => File(path).openRead())(f.path!),
        ),
  ];
}
