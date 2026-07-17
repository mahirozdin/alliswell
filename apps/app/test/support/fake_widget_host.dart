import 'package:alliswell/src/features/widgets/widget_host.dart';

/// In-memory [WidgetHost] for tests — records what the bridge would push, with
/// no platform channels (OPH-130). Full-app tests use it via `syncTestOverrides`
/// so `widgetSyncProvider` (watched by HomeShell) never hits `home_widget`.
class FakeWidgetHost implements WidgetHost {
  bool configured = false;
  int updates = 0;
  final List<String> saved = [];

  String? get lastSaved => saved.isEmpty ? null : saved.last;

  @override
  Future<void> configure() async {
    configured = true;
  }

  @override
  Future<void> save(String key, String value) async {
    saved.add(value);
  }

  @override
  Future<void> requestUpdate() async {
    updates++;
  }
}
