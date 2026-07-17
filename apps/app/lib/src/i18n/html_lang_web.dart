import 'package:web/web.dart' as web;

/// Web build: reflect the active language on `<html lang>` for accessibility and
/// SEO (screen readers pick pronunciation/voice from it) — OPH-128.
void setHtmlLang(String languageCode) {
  web.document.documentElement?.setAttribute('lang', languageCode);
}
