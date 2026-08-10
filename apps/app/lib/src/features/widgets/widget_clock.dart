/// The widget header's clock (round 17 — DESIGN §31 C1–C5).
///
/// **Why the rule lives in Dart when the drawing happens natively.** The clock
/// is the one part of the header the app cannot pre-render: it changes every
/// minute, and neither widget can call back into Flutter to ask. So the native
/// side has to *format* it — but it must not *decide* anything about it (W9).
/// This file is what it is told:
///
/// * [widgetClockPattern] resolves the ICU pattern the clock is drawn with, from
///   the SAME preference the task rows already obey (OPH-174: "a widget and an
///   app disagreeing about a date, side by side on one screen, is
///   indefensible"). It rides in the snapshot as `clockFormat`; iOS hands it to
///   `DateFormatter`, Android to `TextClock.setFormat12Hour/24Hour`. Note that
///   this is deliberately the app's format and not the raw device 12/24 toggle:
///   a header reading "2:37 PM" above rows reading "14:00" would be the exact
///   inconsistency OPH-174 forbids.
/// * [widgetClockIsFresh] is the honesty gate (C3). iOS cannot tick: a widget
///   renders the value baked into its timeline entry and holds it. When the
///   system stops honouring the timeline the entry being drawn is older than
///   its own minute, and the header must degrade to something TRUE — the date
///   block alone — rather than to a wrong time.
///
/// The two constants below are mirrored in `AllisWellWidget.swift`; the mirror
/// is pinned by `test/features/widgets/widget_clock_native_test.dart`, the same
/// way round 16 pinned `web/index.html`.
library;

import 'package:intl/intl.dart';

import '../../core/date_format.dart';

/// How old the entry being rendered may be before the clock is dropped.
///
/// The clock's own granularity is 60 s, so anything past 90 s means at least one
/// minute entry was never drawn — the timeline is not being honoured and the
/// number on screen is no longer the time.
const int kWidgetClockStaleSeconds = 90;

/// How far ahead iOS bakes minute-granular timeline entries.
///
/// Entries are free; only asking for a NEW timeline spends the widget's ~40–70
/// reloads a day. So the cost of a live clock is `1440 / horizon` reloads —
/// 6 a day at 240 minutes, under 15% of the floor. The ceiling is not the
/// budget but the entry count: WidgetKit renders and stores a view per entry,
/// and the field reports failures past ~400. Measured on device; if the system
/// truncates, C3 hides the clock rather than letting it lie.
const int kWidgetClockHorizonMinutes = 240;

/// The ICU pattern the header clock is drawn with — "HH:mm", "h:mm a", …
///
/// [format] is the user's `AwDateFormatSpec` id; the "follow the language"
/// default resolves to the locale's own clock, which is where 12h vs 24h comes
/// from when the user has not chosen otherwise.
String widgetClockPattern({required String format, required String locale}) {
  final spec = awDateFormatSpec(format);
  // A chosen format states its own time pattern; only the system default has to
  // be asked of the locale.
  return spec.time ?? DateFormat.jm(locale).pattern!;
}

/// Whether a timeline entry drawn at [renderedAt] may still show its clock (C3).
///
/// An entry from the future is not stale — WidgetKit is allowed to render one
/// slightly early, and a clock that vanished for being *too fresh* would be its
/// own bug.
bool widgetClockIsFresh({
  required DateTime entryDate,
  required DateTime renderedAt,
}) =>
    renderedAt.difference(entryDate).inSeconds <= kWidgetClockStaleSeconds;
