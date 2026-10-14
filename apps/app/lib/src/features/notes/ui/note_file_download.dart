/// Browser download of an exported note (MD / DOCX). On every other platform
/// the export goes through the share sheet or the save panel instead, so the
/// non-web half is a stub that is never reached.
library;

export 'note_file_download_stub.dart'
    if (dart.library.js_interop) 'note_file_download_web.dart';
