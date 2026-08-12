/// Dropping a file onto the note editor (OPH-250, DESIGN §29 D18's neighbour).
///
/// The upload path already existed and was reachable only through a picker —
/// §22's "a feature nobody can get to" in its milder form: on a desktop, the
/// obvious gesture did nothing at all.
///
/// The drop lands on the whole editor body rather than the text field, because
/// aiming at a caret while dragging a file is a precision task nobody wants;
/// every desktop editor that does this well accepts the whole document area.
library;

import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../data/picked_upload.dart';

/// Whether this platform can receive an OS file drop at all.
///
/// desktop_drop registers macOS, Windows, Linux, Android and web; there is no
/// iOS plugin class. Asking first means iOS gets the plain child instead of a
/// widget whose channel is never answered.
bool get supportsFileDrop {
  if (kIsWeb) return true;
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.android => true,
    _ => false,
  };
}

/// Reads a dropped [XFile] into the shape the upload pipeline already takes.
///
/// `PickedUpload.open` has to be RE-openable (a retry re-reads the source), so
/// a path-backed drop keeps the path and only the web falls back to bytes in
/// memory — the same split `pick_files_io.dart` / `pick_files_web.dart` make.
Future<PickedUpload> pickedFromDrop(XFile file) async {
  // `XFile.name` is not guaranteed: it is derived from the path on io, and a
  // drop can arrive with neither. An empty name would upload a blank row and
  // leave `mimeForName` nothing to guess from, so it gets a real fallback.
  final name = switch ((file.name, file.path)) {
    (final n, _) when n.isNotEmpty => n,
    (_, final p) when p.isNotEmpty => p.split(Platform.pathSeparator).last,
    _ => 'dropped',
  };
  final mime = file.mimeType;
  if (!kIsWeb && file.path.isNotEmpty) {
    final handle = File(file.path);
    return PickedUpload(
      name: name,
      sizeBytes: await handle.length(),
      mime: mime,
      open: () => handle.openRead(),
    );
  }
  return PickedUpload.fromBytes(
    name: name,
    bytes: await file.readAsBytes(),
    mime: mime,
  );
}

/// Wraps [child] in an OS-file drop target, with a visible landing state.
class NoteDropTarget extends StatefulWidget {
  const NoteDropTarget({super.key, required this.child, required this.onFiles});

  final Widget child;
  final Future<void> Function(List<PickedUpload> picks) onFiles;

  @override
  State<NoteDropTarget> createState() => _NoteDropTargetState();
}

class _NoteDropTargetState extends State<NoteDropTarget> {
  bool _hovering = false;

  Future<void> _onDone(DropDoneDetails detail) async {
    setState(() => _hovering = false);
    if (detail.files.isEmpty) return;
    final picks = <PickedUpload>[];
    for (final file in detail.files) {
      try {
        picks.add(await pickedFromDrop(file));
      } on Object {
        // A directory, or a file the sandbox will not open. Skipping it beats
        // failing the whole drop — the others are still perfectly good.
        continue;
      }
    }
    if (picks.isEmpty || !mounted) return;
    await widget.onFiles(picks);
  }

  @override
  Widget build(BuildContext context) {
    if (!supportsFileDrop) return widget.child;
    final scheme = Theme.of(context).colorScheme;

    return DropTarget(
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      onDragDone: (detail) => unawaited(_onDone(detail)),
      child: Stack(
        children: [
          widget.child,
          if (_hovering)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  key: const Key('note-drop-overlay'),
                  color: scheme.primary.withValues(alpha: 0.08),
                  alignment: Alignment.center,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(AwRadius.m),
                      ),
                      border: Border.all(color: context.awTokens.hairline),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AwSpace.x5,
                        vertical: AwSpace.x4,
                      ),
                      child: Text(
                        'file.dropHere'.tr(),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
