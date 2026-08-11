/// The one control that switches modes (DESIGN §29 D1, OPH-248).
///
/// "One control switches them; the control shows which one is active and never
/// hides." It shows the modes this note actually offers — two, under the D1
/// amendment recorded in `note_document.dart` — because a disabled third
/// segment is the dead affordance §22 exists to forbid.
library;

import 'package:flutter/material.dart';

import '../../../../i18n/i18n.dart';
import '../../data/note_document.dart';

class NoteModeControl extends StatelessWidget {
  const NoteModeControl({
    super.key,
    required this.modes,
    required this.active,
    required this.onChanged,
  });

  final List<NoteMode> modes;
  final NoteMode active;
  final ValueChanged<NoteMode> onChanged;

  static String labelKey(NoteMode mode) => switch (mode) {
    NoteMode.reading => 'note.modeReading',
    NoteMode.live => 'note.modeLive',
    NoteMode.source => 'note.modeSource',
  };

  static IconData iconFor(NoteMode mode) => switch (mode) {
    NoteMode.reading => Icons.menu_book_outlined,
    NoteMode.live => Icons.edit_note_outlined,
    NoteMode.source => Icons.data_object,
  };

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<NoteMode>(
      key: const Key('note-mode-control'),
      showSelectedIcon: false,
      segments: [
        for (final mode in modes)
          ButtonSegment<NoteMode>(
            value: mode,
            icon: Icon(iconFor(mode), size: 18),
            label: Text(labelKey(mode).tr()),
          ),
      ],
      selected: {active},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
