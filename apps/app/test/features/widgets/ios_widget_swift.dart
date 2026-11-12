import 'dart:io';

/// The Swift the iOS widget extension compiles for its timeline and model.
///
/// OPH-451 moved the snapshot model and the day choice out of the widget's own
/// file into `ios/Shared/` (so RunnerTests can run them). A test that pins what
/// the native reader must keep saying reads this whole set, not one file: a
/// symbol that moves between these files is still the same reader.
/// `widget_clock_native_test.dart` pins that the widget target really compiles
/// every shared file listed here.
const kIosWidgetSwiftFile = 'ios/AllisWellWidget/AllisWellWidget.swift';
const kIosWidgetSharedSwift = [
  'ios/Shared/AWSnapshotModel.swift',
  'ios/Shared/AWWidgetDayPick.swift',
];

/// The widget's own file first, then the shared ones — order matters to the
/// tests that slice one struct out of the widget file.
String readIosWidgetSwift() => [
  kIosWidgetSwiftFile,
  ...kIosWidgetSharedSwift,
].map((path) => File(path).readAsStringSync()).join('\n');
