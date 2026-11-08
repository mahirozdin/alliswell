import 'package:flutter/widgets.dart';

/// The shell's section on show (its branch index), told to the screens
/// inside it.
///
/// The shell keeps every branch mounted (an indexed stack), so a screen
/// left for another section is neither disposed nor told it was left. A
/// screen holding something only while it is on show — a pane that lent a
/// unit (E35 S-G1 review r1) — reads this: the value changes on every
/// section switch, and a page pushed over the shell does not change it.
/// Outside a shell (a page on the root navigator, a test) it is null.
class AwShellSection extends InheritedWidget {
  const AwShellSection({super.key, required this.index, required super.child});

  final int index;

  /// The section on show, or null outside a shell. [listen] false asks
  /// without subscribing — for a tap handler, which is not a build.
  static int? of(BuildContext context, {bool listen = true}) =>
      (listen
              ? context.dependOnInheritedWidgetOfExactType<AwShellSection>()
              : context.getInheritedWidgetOfExactType<AwShellSection>())
          ?.index;

  @override
  bool updateShouldNotify(AwShellSection oldWidget) => oldWidget.index != index;
}
