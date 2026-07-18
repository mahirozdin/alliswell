import 'package:file_picker/file_picker.dart';

import 'picked_upload.dart';

/// Web: there are no paths, so bytes come into memory (`withData`) — which
/// also makes retries trivial. The API's upload cap bounds the damage.
Future<List<PickedUpload>> pickUploads() async {
  final result = await FilePicker.pickFiles(
    allowMultiple: true,
    withData: true,
  );
  if (result == null) return const [];
  return [
    for (final f in result.files)
      if (f.bytes != null)
        PickedUpload.fromBytes(name: f.name, bytes: f.bytes!),
  ];
}
