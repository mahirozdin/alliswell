import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/features/files/providers.dart';

/// OPH-244 — which named way opens where. Pure, so all six platforms are
/// covered without pumping a widget.
void main() {
  group('attachMenuSources', () {
    test('phones get Photos · Camera · Files', () {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        expect(attachMenuSources(isWeb: false, platform: platform), [
          AttachSource.photoLibrary,
          AttachSource.camera,
          AttachSource.anyFile,
        ], reason: '$platform');
      }
    });

    test('desktop offers only Files — its camera path would THROW', () {
      // image_picker's desktop implementations extend
      // CameraDelegatingImagePickerPlatform and throw StateError for
      // ImageSource.camera with no delegate. Hiding the row there is a
      // correctness requirement, not polish.
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(attachMenuSources(isWeb: false, platform: platform), [
          AttachSource.anyFile,
        ], reason: '$platform');
      }
    });

    test('the web offers only Files, whatever the host pretends to be', () {
      expect(attachMenuSources(isWeb: true, platform: TargetPlatform.iOS), [
        AttachSource.anyFile,
      ]);
    });
  });

  group('attachFileType', () {
    test('maps every document-browser source, and refuses the camera', () {
      expect(attachFileType(AttachSource.photoLibrary), FileType.media);
      expect(attachFileType(AttachSource.imageLibrary), FileType.image);
      expect(attachFileType(AttachSource.videoLibrary), FileType.video);
      expect(attachFileType(AttachSource.audioFiles), FileType.audio);
      expect(attachFileType(AttachSource.anyFile), FileType.any);
      expect(
        attachFileType(AttachSource.camera),
        isNull,
        reason: 'the camera is not a file_picker path at all',
      );
    });

    test('nothing maps to FileType.any except anyFile', () {
      // The whole bug was an untyped call resolving to `any`, which iOS routes
      // to the document browser. Anything else landing there is the bug back.
      for (final source in AttachSource.values) {
        if (source == AttachSource.anyFile) continue;
        expect(attachFileType(source), isNot(FileType.any), reason: '$source');
      }
    });
  });

  test('isMediaLibrarySource names exactly the photo-picker sources', () {
    expect(AttachSource.values.where(isMediaLibrarySource), [
      AttachSource.photoLibrary,
      AttachSource.imageLibrary,
      AttachSource.videoLibrary,
    ]);
  });

  test('a camera capture is renamed the way a gallery would', () {
    expect(
      cameraCaptureName(DateTime(2026, 8, 10, 0, 32, 15)),
      'IMG_20260810_003215.jpg',
    );
    expect(
      cameraCaptureName(DateTime(2026, 12, 1, 9, 5, 3), extension: 'heic'),
      'IMG_20261201_090503.heic',
    );
  });

  test('every source has a label key and a sheet key', () {
    for (final source in AttachSource.values) {
      expect(attachSourceLabelKey(source), isNotEmpty, reason: '$source');
      expect(attachSourceSheetKey(source), isNotEmpty, reason: '$source');
    }
  });
}
