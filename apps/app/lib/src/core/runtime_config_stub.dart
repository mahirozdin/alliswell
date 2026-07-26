/// Non-web builds have no runtime configuration file: iOS/Android/desktop
/// binaries are compiled per deployment, so the `--dart-define` is the whole
/// story. The web build swaps in `runtime_config_web.dart` via a conditional
/// import, exactly like `html_lang_stub.dart` does for `<html lang>`.
String? readRuntimeApiBaseUrl() => null;
