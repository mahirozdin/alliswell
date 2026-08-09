import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'attach_source.dart';
import 'picked_upload.dart';

/// io platforms: picked files come back as PATHS and are streamed from disk
/// at upload time — a video never has to fit in memory, and `open()` is
/// naturally re-openable for retries.
///
/// OPH-244: the [source] decides WHICH system picker opens, and there are two
/// of them. Media from the OS library (and the camera) goes through
/// `image_picker`, everything else through `file_picker`'s document browser.
/// Round 17 #2 was one call that never said which it wanted.
Future<List<PickedUpload>> pickUploads(AttachSource source) async {
  if (isMediaLibrarySource(source) || source == AttachSource.camera) {
    return _pickMedia(source);
  }
  final type = attachFileType(source);
  if (type == null) return const [];
  // file_picker 12: `withData` is gone (bytes are pulled on demand via
  // PlatformFile.readAsBytes) and multi-select is `pickFiles`' own behaviour —
  // `pickFile` is the single-file call.
  final result = await FilePicker.pickFiles(type: type);
  if (result == null) return const [];
  return [
    for (final f in result.files)
      if (f.path != null) _fromPath(f.path!, f.name, f.size),
  ];
}

Future<List<PickedUpload>> _pickMedia(AttachSource source) async {
  _ensureAndroidPhotoPicker();
  final picker = ImagePicker();

  final files = switch (source) {
    AttachSource.photoLibrary => await picker.pickMultipleMedia(),
    AttachSource.imageLibrary => await picker.pickMultiImage(),
    AttachSource.videoLibrary => await _one(
      picker.pickVideo(source: ImageSource.gallery),
    ),
    AttachSource.camera => await _one(
      picker.pickImage(source: ImageSource.camera),
    ),
    _ => const <XFile>[],
  };

  final uploads = <PickedUpload>[];
  for (final file in files) {
    final length = await file.length();
    // A capture has no name of its own — `image_picker_5B1F….jpg` is the
    // plugin's temp path. Name it the way a phone gallery would (DESIGN §10 F6).
    final name = source == AttachSource.camera
        ? cameraCaptureName(DateTime.now(), extension: _extensionOf(file.name))
        : file.name;
    uploads.add(
      PickedUpload(
        name: name,
        sizeBytes: length,
        mime: file.mimeType,
        open: ((path) =>
            () => File(path).openRead())(file.path),
      ),
    );
  }
  return uploads;
}

/// The Android Photo Picker ships OFF (`image_picker_android.dart`:
/// `useAndroidPhotoPicker = false`). Without this the plugin falls back to
/// ACTION_GET_CONTENT — a document browser, which is the exact bug this round
/// exists to fix. A no-op on every other platform.
void _ensureAndroidPhotoPicker() {
  final platform = ImagePickerPlatform.instance;
  if (platform is ImagePickerAndroid) {
    platform.useAndroidPhotoPicker = true;
  }
}

Future<List<XFile>> _one(Future<XFile?> pick) async {
  final file = await pick;
  return file == null ? const [] : [file];
}

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? 'jpg' : name.substring(dot + 1).toLowerCase();
}

PickedUpload _fromPath(String path, String name, int size) => PickedUpload(
  name: name,
  sizeBytes: size,
  open: ((p) =>
      () => File(p).openRead())(path),
);
