import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// The named ways a file gets into AllisWell (DESIGN §30 A1) — OPH-244.
///
/// Round 17 #2: "Add file" opened the iPhone's document browser, where photos
/// simply are not. That was not a bug in the picker; it was a call with no
/// intent. `FilePicker.pickFiles()` with no `type:` means `FileType.any`, and
/// file_picker's iOS handler routes `any` to `UIDocumentPickerViewController`
/// while only `image`/`video`/`media` reach `PHPickerViewController`.
///
/// So the seam carries the intent now, and the parameter is REQUIRED: a default
/// would let the next call site forget the same way this one did.
enum AttachSource {
  /// The system photo picker: images AND videos. Needs no permission on either
  /// platform (A2/A3) — it runs out of process and hands back only what the
  /// user chose.
  photoLibrary,

  /// The photo library, images only — the note toolbar's "insert image".
  imageLibrary,

  /// The photo library, videos only — "insert video".
  videoLibrary,

  /// One capture from the camera. Mobile only: the desktop implementations of
  /// image_picker throw for [ImageSource.camera] without a delegate, so
  /// offering it there would be a crash, not a rough edge.
  camera,

  /// The document browser, filtered to audio — the ringtone picker.
  audioFiles,

  /// The document browser, unfiltered. What every call site used to do.
  anyFile,
}

/// The sources the attach MENU offers on this platform.
///
/// A different question from "which sources exist": `imageLibrary`,
/// `videoLibrary` and `audioFiles` are chosen by their own buttons elsewhere
/// and degrade to a filtered file dialog everywhere.
///
/// Takes the platform as DATA rather than reading it, so one unit test can walk
/// every platform without pumping a widget — the `widgetsSupportedPlatform`
/// pattern.
List<AttachSource> attachMenuSources({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return const [AttachSource.anyFile];
  return switch (platform) {
    TargetPlatform.iOS || TargetPlatform.android => const [
      AttachSource.photoLibrary,
      AttachSource.camera,
      AttachSource.anyFile,
    ],
    _ => const [AttachSource.anyFile],
  };
}

/// Does this source come from the OS media library (which means the photo
/// picker on mobile), or from a document browser?
bool isMediaLibrarySource(AttachSource source) =>
    source == AttachSource.photoLibrary ||
    source == AttachSource.imageLibrary ||
    source == AttachSource.videoLibrary;

/// The `file_picker` type for the document-browser sources, and for the media
/// ones on the platforms that have no photo picker. Null for [camera], which is
/// not a file_picker path at all.
FileType? attachFileType(AttachSource source) => switch (source) {
  AttachSource.photoLibrary => FileType.media,
  AttachSource.imageLibrary => FileType.image,
  AttachSource.videoLibrary => FileType.video,
  AttachSource.audioFiles => FileType.audio,
  AttachSource.anyFile => FileType.any,
  AttachSource.camera => null,
};

/// The widget key of this source's row in the attach menu. Public and defined
/// beside the enum so the sheet and the tests that drive it cannot drift.
String attachSourceSheetKey(AttachSource source) => switch (source) {
  AttachSource.photoLibrary ||
  AttachSource.imageLibrary => 'attach-source-photos',
  AttachSource.camera => 'attach-source-camera',
  AttachSource.videoLibrary => 'attach-source-video',
  AttachSource.audioFiles => 'attach-source-audio',
  AttachSource.anyFile => 'attach-source-files',
};

/// The i18n key naming this source to the user.
String attachSourceLabelKey(AttachSource source) => switch (source) {
  AttachSource.photoLibrary => 'file.fromPhotos',
  AttachSource.camera => 'file.fromCamera',
  AttachSource.anyFile => 'file.fromFiles',
  AttachSource.imageLibrary => 'file.insertImage',
  AttachSource.videoLibrary => 'file.insertVideo',
  AttachSource.audioFiles => 'sound.upload',
};

/// A camera capture arrives named `image_picker_5B1F….jpg` — the plugin's temp
/// path, not a name anyone would choose. Name it the way a phone gallery does,
/// so raw plumbing never reaches a file row (DESIGN §10 F6).
///
/// [now] is a parameter rather than `DateTime.now()` so the format is testable.
String cameraCaptureName(DateTime now, {String extension = 'jpg'}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp =
      '${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  return 'IMG_$stamp.$extension';
}
