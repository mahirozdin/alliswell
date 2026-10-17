import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/import/data/import_file_reader.dart';

/// OPH-371 — the device's only two jobs with an export: unzip a Todoist
/// backup and decode UTF-8. Everything else is the server's.
PickedImportFile picked(String name, List<int> bytes, {int? size}) =>
    PickedImportFile(
      name: name,
      size: size ?? bytes.length,
      read: () async => Uint8List.fromList(bytes),
    );

Uint8List zip(Map<String, String> files) {
  final archive = Archive();
  for (final e in files.entries) {
    archive.addFile(ArchiveFile.bytes(e.key, utf8.encode(e.value)));
  }
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  test('a backup ZIP gives back only its CSVs, names kept, folders and '
      '__MACOSX skipped', () async {
    final bytes = zip({
      'Inbox [1].csv': 'TYPE,CONTENT\ntask,Süt al\n',
      'Projeler/Ev İşleri [2].csv': 'TYPE,CONTENT\ntask,Çimleri biç\n',
      '__MACOSX/Projeler/._Ev İşleri [2].csv': 'junk',
      'readme.txt': 'not a csv',
    });
    final files = await readImportFiles([picked('backup.zip', bytes)]);
    expect(files.map((f) => f.name), ['Inbox [1].csv', 'Ev İşleri [2].csv']);
    expect(files[1].content, contains('Çimleri biç'));
  });

  test(
    'a CSV is decoded as UTF-8; the BOM goes, bad bytes become U+FFFD',
    () async {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('ad,ğüşıöçİ\n'), 0xFF];
      final files = await readImportFiles([picked('x.csv', bytes)]);
      expect(files.single.content.startsWith('ad,ğüşıöçİ'), isTrue);
      expect(files.single.content.endsWith('�'), isTrue);
    },
  );

  test('the size cap is checked BEFORE anything is read', () async {
    var read = false;
    final big = PickedImportFile(
      name: 'big.csv',
      size: kImportMaxBytes + 1,
      read: () async {
        read = true;
        return Uint8List(0);
      },
    );
    await expectLater(readImportFiles([big]), throwsA(isA<ImportTooLarge>()));
    expect(read, isFalse);
  });

  test('a ZIP with no CSV is refused', () async {
    final bytes = zip({'notes.txt': 'hello'});
    await expectLater(
      readImportFiles([picked('b.zip', bytes)]),
      throwsA(isA<ImportNoCsv>()),
    );
  });
}
