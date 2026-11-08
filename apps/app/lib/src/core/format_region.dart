/// Where the formatter's CONVENTIONS come from (OPH-408, ADR-0063 #6).
///
/// The words of a date ("Kas", "Tomorrow") follow the app's language; the
/// order of its parts, the 12/24-hour clock and the number separators follow
/// the device's REGION. An English UI on a German phone is common — the app
/// has no German, so it falls back to English — and that person reads
/// "7 Nov 2026, 13:47" and "6,3 MB", never "11/7/2026 1:47 PM".
library;

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:intl/intl.dart';

import '../i18n/i18n.dart';

/// The order a date's day, month and year are written in.
enum AwDateOrder { dmy, mdy, ymd }

/// The resolved conventions for one (language, region) pair.
class AwConventions {
  const AwConventions({
    required this.locale,
    required this.order,
    required this.uses24h,
  });

  /// The `intl` locale whose separators and patterns stand for the region
  /// ("tr", "en_US", "de").
  final String locale;

  final AwDateOrder order;

  final bool uses24h;
}

/// Test seam: replaces the device-region lookup. Returning null means "the
/// device says nothing", and the app language's own conventions apply — what a
/// phone set to the app's language does. `test/flutter_test_config.dart` sets
/// this so a suite never depends on the machine running it.
@visibleForTesting
String? Function()? awDeviceRegionOverride;

/// The language a region is written in when the app's language is not one
/// `intl` knows for that region (an English UI in Germany → German
/// conventions). Regions missing here fall back to the app language.
const Map<String, String> _kRegionLanguage = {
  'AE': 'ar',
  'AR': 'es_419',
  'AT': 'de_AT',
  'AU': 'en_AU',
  'AZ': 'az',
  'BE': 'nl',
  'BG': 'bg',
  'BR': 'pt',
  'CA': 'en_CA',
  'CH': 'de_CH',
  'CL': 'es_419',
  'CN': 'zh',
  'CO': 'es_419',
  'CY': 'el',
  'CZ': 'cs',
  'DE': 'de',
  'DK': 'da',
  'EE': 'et',
  'EG': 'ar_EG',
  'ES': 'es_ES',
  'FI': 'fi',
  'FR': 'fr',
  'GB': 'en_GB',
  'GR': 'el',
  'HR': 'hr',
  'HU': 'hu',
  'ID': 'id',
  'IE': 'en_IE',
  'IL': 'he',
  'IN': 'en_IN',
  'IT': 'it',
  'JP': 'ja',
  'KR': 'ko',
  'KZ': 'kk',
  'LT': 'lt',
  'LU': 'fr',
  'LV': 'lv',
  'MX': 'es_MX',
  'MY': 'ms',
  'NL': 'nl',
  'NO': 'nb',
  'NZ': 'en_NZ',
  'PH': 'en',
  'PK': 'en',
  'PL': 'pl',
  'PT': 'pt_PT',
  'RO': 'ro',
  'RS': 'sr_Latn',
  'RU': 'ru',
  'SA': 'ar',
  'SE': 'sv',
  'SG': 'en_SG',
  'SI': 'sl',
  'SK': 'sk',
  'TR': 'tr',
  'TW': 'zh_TW',
  'UA': 'uk',
  'US': 'en_US',
  'ZA': 'en_ZA',
};

/// A device that names a language but no region ("de", "tr" — common on the
/// web): the region that language is most often read in.
const Map<String, String> _kLanguageRegion = {
  'de': 'DE',
  'en': 'US',
  'es': 'ES',
  'fr': 'FR',
  'it': 'IT',
  'nl': 'NL',
  'pt': 'PT',
  'ru': 'RU',
  'tr': 'TR',
};

/// The device's region ("TR", "DE"), or null when it says nothing usable.
///
/// Only the FIRST device locale counts: on the web a Turkish browser may list
/// "tr, en-US", and the second entry is not where its reader lives.
String? awDeviceRegion() {
  final hook = awDeviceRegionOverride;
  if (hook != null) return hook();
  final locales = PlatformDispatcher.instance.locales;
  if (locales.isEmpty) return null;
  final first = locales.first;
  final country = first.countryCode;
  if (country != null && country.isNotEmpty) return country.toUpperCase();
  return _kLanguageRegion[first.languageCode];
}

/// The UI language of a locale tag ("en-US" → "en"); null = the app's own.
String awLanguageOf(String? locale) {
  final tag = locale ?? AwI18n.instance.locale.languageCode;
  return tag.replaceAll('-', '_').split('_').first.toLowerCase();
}

bool _known(String locale) =>
    NumberFormat.localeExists(locale) && DateFormat.localeExists(locale);

final Map<String, AwConventions> _cache = {};

/// The conventions for [language] (the UI's) in [region] (the device's).
///
/// The first locale `intl` knows wins: the UI language in that region
/// ("en_GB"), then the region's own language ("de" for DE), then the UI
/// language alone. A junk region simply falls through to the last.
AwConventions awConventions({String? language, String? region}) {
  final lang = awLanguageOf(language);
  final reg = (region ?? awDeviceRegion())?.toUpperCase();
  final key = '$lang|$reg';
  final cached = _cache[key];
  if (cached != null) return cached;

  final candidates = <String>[
    if (reg != null && reg.isNotEmpty) ...[
      '${lang}_$reg',
      ?_kRegionLanguage[reg],
    ],
    lang,
  ];
  final locale = candidates.firstWhere(_known, orElse: () => 'en');

  // The region's own medium date says the order ("d MMM y", "MMM d, y",
  // "y. MMM d."); its own clock says 12 or 24 hours ("h:mm a" vs "HH:mm").
  final datePattern = DateFormat.yMMMd(locale).pattern ?? 'd MMM y';
  final d = datePattern.indexOf('d');
  final m = datePattern.indexOf('M');
  final y = datePattern.indexOf('y');
  final order = (y >= 0 && y < d && y < m)
      ? AwDateOrder.ymd
      : (m >= 0 && m < d)
      ? AwDateOrder.mdy
      : AwDateOrder.dmy;
  final clock = DateFormat.jm(locale).pattern ?? 'HH:mm';
  final uses24h = !clock.contains('a') && !clock.contains('h');

  return _cache[key] = AwConventions(
    locale: locale,
    order: order,
    uses24h: uses24h,
  );
}
