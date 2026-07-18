import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'picked_upload.dart';

/// io platforms: picked files come back as PATHS and are streamed from disk
/// at upload time — a video never has to fit in memory, and `open()` is
/// naturally re-openable for retries.
Future<List<PickedUpload>> pickUploads() async {
  final result = await FilePicker.pickFiles(
    allowMultiple: true,
    withData: false,
  );
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
