import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../auth/providers.dart';
import '../data/csv_export_api.dart';

final eeCsvExportApiProvider = Provider<EeCsvExportApi>(
  (ref) => EeCsvExportApi(ref.watch(apiClientProvider)),
);

/// Where a downloaded CSV goes. A seam so a test records the bytes instead of
/// opening a platform save dialog (the note exporter's shape).
class EeCsvSink {
  const EeCsvSink();

  /// The chosen path (on the web: the browser's download), or null when the
  /// person backed out.
  Future<String?> save(Uint8List bytes, String filename) => FilePicker.saveFile(
    fileName: filename,
    bytes: bytes,
    type: FileType.custom,
    allowedExtensions: const ['csv'],
  );
}

final eeCsvSinkProvider = Provider<EeCsvSink>((ref) => const EeCsvSink());

/// Fetches one export and hands it to the device (OPH-360, UI-AUDIT #56).
///
/// Every outcome is said: saved (and, when the server stopped at its ceiling,
/// that the file says so inside it), backed out of (nothing), or refused —
/// the server's coded reason translated, e.g. the 10-a-minute export limit.
Future<void> eeDownloadCsv(
  BuildContext context,
  WidgetRef ref,
  Future<EeCsvFile> Function(EeCsvExportApi api) fetch,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final sink = ref.read(eeCsvSinkProvider);
  messenger?.showSnackBar(SnackBar(content: Text('ee.csv.preparing'.tr())));
  try {
    final file = await fetch(ref.read(eeCsvExportApiProvider));
    final saved = await sink.save(file.bytes, file.filename);
    messenger?.hideCurrentSnackBar();
    if (saved == null) return;
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          file.truncated
              ? 'ee.csv.savedTruncated'.tr(args: {'name': file.filename})
              : 'ee.csv.saved'.tr(args: {'name': file.filename}),
        ),
      ),
    );
  } catch (error) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(localizedError(error))));
  }
}
