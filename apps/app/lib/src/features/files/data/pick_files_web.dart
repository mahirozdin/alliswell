import 'package:file_picker/file_picker.dart';

import 'picked_upload.dart';

/// Web: there are no paths, so the bytes come into memory — which also makes
/// retries trivial. The API's upload cap bounds the damage.
Future<List<PickedUpload>> pickUploads() async {
  final result = await FilePicker.pickFiles();
  if (result == null) return const [];
  // file_picker 12 reads bytes on demand rather than eagerly, so this is a
  // per-file await instead of a `withData` flag.
  final uploads = <PickedUpload>[];
  for (final f in result.files) {
    final bytes = await f.readAsBytes();
    uploads.add(PickedUpload.fromBytes(name: f.name, bytes: bytes));
  }
  return uploads;
}
