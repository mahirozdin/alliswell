/// The one control that switches modes (DESIGN §29 D1, OPH-248 / OPH-274).
///
/// "One control switches them; the control shows which one is active and never
/// hides." Two segments, and both live for every note: ADR-0033 left one
/// canonical form, so the D1 amendment that made the third segment conditional
/// (and would have made it a dead affordance, which §22 forbids) is retired.
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
    NoteMode.source => 'note.modeSource',
  };

  static IconData iconFor(NoteMode mode) => switch (mode) {
    NoteMode.reading => Icons.menu_book_outlined,
    NoteMode.source => Icons.edit_note_outlined,
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
