import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'import_models.dart';

/// Getting another app's export off the disk (OPH-371).
///
/// The device does exactly two things to a file: unzip a Todoist backup and
/// decode UTF-8. Everything else — CSV, dates, recurrences — happens on the
/// server, so there is one parser for the app, the API and curl (ADR-0052).

/// What the server accepts in one request. Its body limit is 10 MiB, and the
/// JSON envelope is not free: every quote and line break in a CSV is escaped,
/// which grows a fully quoted TickTick backup by about 16 % — so the files
/// themselves stop at 8 MiB, never at a size the server would then refuse.
const kImportMaxBytes = 8 * 1024 * 1024;

class ImportTooLarge implements Exception {
  const ImportTooLarge(this.bytes);
  final int bytes;
}

class ImportNoCsv implements Exception {
  const ImportNoCsv();
}

/// A file the person chose, before it is read. [size] is known up front so a
/// huge file is refused BEFORE it is pulled into memory (DESIGN §28 M7).
class PickedImportFile {
  const PickedImportFile({
    required this.name,
    required this.size,
    required this.read,
  });

  final String name;
  final int size;
  final Future<Uint8List> Function() read;
}

/// Decodes bytes as UTF-8, tolerating a BOM and stray bytes (they become
/// U+FFFD rather than losing the whole file).
String decodeImportText(List<int> bytes) {
  final text = const Utf8Decoder(allowMalformed: true).convert(bytes);
  return text.startsWith('﻿') ? text.substring(1) : text;
}

bool _isCsv(String name) => name.toLowerCase().endsWith('.csv');

/// The chosen files as text: CSVs as they are, ZIPs opened and their CSVs
/// taken out (nested folders included, macOS `__MACOSX/` skipped).
Future<List<ImportFileText>> readImportFiles(
  List<PickedImportFile> picked,
) async {
  final total = picked.fold<int>(0, (n, f) => n + f.size);
  if (total > kImportMaxBytes) throw ImportTooLarge(total);

  final out = <ImportFileText>[];
  var unpacked = 0;
  for (final file in picked) {
    final bytes = await file.read();
    if (file.name.toLowerCase().endsWith('.zip')) {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final name = entry.name;
        if (name.startsWith('__MACOSX/') || name.contains('/__MACOSX/')) {
          continue;
        }
        final base = name.split('/').last;
        if (base.startsWith('._') || !_isCsv(base)) continue;
        unpacked += entry.size;
        if (unpacked > kImportMaxBytes) throw ImportTooLarge(unpacked);
        out.add(
          ImportFileText(
            name: base,
            content: decodeImportText(entry.content),
            bytes: entry.size,
          ),
        );
      }
    } else if (_isCsv(file.name)) {
      out.add(
        ImportFileText(
          name: file.name,
          content: decodeImportText(bytes),
          bytes: file.size,
        ),
      );
    }
  }
  if (out.isEmpty) throw const ImportNoCsv();
  return out;
}

/// The system picker, behind a seam so tests never touch a plugin.
abstract class ImportFilePicker {
  /// Null when the person backs out.
  Future<List<PickedImportFile>?> pick({required bool multiple});
}

class PlatformImportFilePicker implements ImportFilePicker {
  const PlatformImportFilePicker();

  @override
  Future<List<PickedImportFile>?> pick({required bool multiple}) async {
    // A Todoist backup is a ZIP, but a person may have exported projects one
    // CSV at a time — so Todoist takes several files; TickTick has one.
    final List<PlatformFile> files;
    if (multiple) {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'zip'],
      );
      files = result?.files ?? const [];
    } else {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'zip'],
      );
      files = [?file];
    }
    if (files.isEmpty) return null;
    return [
      for (final f in files)
        PickedImportFile(name: f.name, size: f.size, read: f.readAsBytes),
    ];
  }
}

final importFilePickerProvider = Provider<ImportFilePicker>(
  (ref) => const PlatformImportFilePicker(),
);
