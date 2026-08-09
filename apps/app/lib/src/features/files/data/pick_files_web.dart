import 'package:file_picker/file_picker.dart';

import 'attach_source.dart';
import 'picked_upload.dart';

/// Web: there are no paths, so the bytes come into memory — which also makes
/// retries trivial. The API's upload cap bounds the damage.
///
/// OPH-244: the [source] becomes the file dialog's `accept` filter. There is no
/// camera path here — `attachMenuSources` never offers one on the web, and a
/// direct call answers "picked nothing" rather than throwing.
Future<List<PickedUpload>> pickUploads(AttachSource source) async {
  final type = attachFileType(source);
  if (type == null) return const [];
  final result = await FilePicker.pickFiles(type: type);
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
