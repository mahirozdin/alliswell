/// Non-web platforms have no `<html lang>` — this is a no-op. The web build
/// swaps in `html_lang_web.dart` via a conditional import (OPH-128).
void setHtmlLang(String languageCode) {}
