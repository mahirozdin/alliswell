import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/format.dart';

/// OPH-408 (U-09, ADR-0063 #6): one formatter. The words follow the app
/// language, the order / clock / separators follow the device region — and the
/// three readers the task names each get their own answer: TR, EN-US, and an
/// English UI on a German phone (EN-DE).
void main() {
  const sys = kAwSystemDateFormat;
  // A Friday afternoon in 2026; "now" is pinned so "this year" is testable.
  final now = DateTime(2026, 11, 7, 9, 30);
  final at = DateTime(2026, 11, 7, 13, 47);
  final tomorrow = DateTime(2026, 11, 8, 11, 0);
  final yesterday = DateTime(2026, 11, 6, 8, 5);
  final laterThisYear = DateTime(2026, 12, 24, 13, 47);
  final lastYear = DateTime(2025, 11, 7, 13, 47);

  // No numeric date in the default, ever: 07.11.2026, 11/7/2026, 2026-11-07.
  final numericDate = RegExp(r'\d{1,4}[./-]\d{1,2}[./-]\d{1,4}');
  const nbsp = ' ';
  const nnbsp = ' ';

  group('TR (tr UI, TR region)', () {
    String row(DateTime v) =>
        awFormatShort(v, format: sys, locale: 'tr', region: 'TR', now: now);
    String full(DateTime v) =>
        awFormatDateTime(v, format: sys, locale: 'tr', region: 'TR', now: now);

    test('a row: today is a bare time, then the day word, then the date', () {
      expect(row(at), '13:47');
      expect(row(tomorrow), 'Yarın${nbsp}11:00');
      expect(row(yesterday), 'Dün${nbsp}08:05');
      expect(row(laterThisYear), '24 Ara,${nbsp}13:47');
      expect(row(lastYear), '7 Kas 2025,${nbsp}13:47');
    });

    test('a detail line names today', () {
      expect(full(at), 'Bugün${nbsp}13:47');
      expect(full(laterThisYear), '24 Ara,${nbsp}13:47');
    });

    test('a date alone carries the year only when it is not this year', () {
      expect(
        awFormatDate(at, format: sys, locale: 'tr', region: 'TR', now: now),
        '7 Kas',
      );
      expect(
        awFormatDate(
          lastYear,
          format: sys,
          locale: 'tr',
          region: 'TR',
          now: now,
        ),
        '7 Kas 2025',
      );
    });

    test('numbers, money, percent, file size', () {
      expect(awFormatNumber(48500, locale: 'tr', region: 'TR'), '48.500');
      expect(
        awFormatMoney(4850000, 'TRY', locale: 'tr', region: 'TR'),
        '48.500${nbsp}TL',
      );
      expect(
        awFormatMoney(38500050, 'TRY', locale: 'tr', region: 'TR'),
        '385.000,50${nbsp}TL',
      );
      expect(
        awFormatMoney(4850000, 'TRY', locale: 'tr', region: 'TR'),
        isNot(contains('TRY')),
      );
      expect(awFormatPercent(51.4, locale: 'tr', region: 'TR'), '%51,4');
      expect(
        awFormatFileSize(6606029, locale: 'tr', region: 'TR'),
        '6,3${nbsp}MB',
      );
      expect(
        awFormatFileSize(722, locale: 'tr', region: 'TR'),
        "1 KB'den küçük",
      );
      expect(awFormatNumberText('48500', locale: 'tr', region: 'TR'), '48.500');
    });

    test('durations are whole words, no "g" or "sa"', () {
      expect(awFormatDuration(45, locale: 'tr'), '45 dk');
      expect(awFormatDuration(120, locale: 'tr'), '2 saat');
      expect(awFormatDuration(90, locale: 'tr'), '1 saat 30 dk');
      expect(awFormatDuration(3600, locale: 'tr'), '2 gün 12 saat');
      expect(awFormatDuration(1500, days: false, locale: 'tr'), '25 saat');
    });
  });

  group('EN-US (en UI, US region)', () {
    String row(DateTime v) =>
        awFormatShort(v, format: sys, locale: 'en', region: 'US', now: now);

    test('a 12-hour clock, the month first', () {
      expect(row(at), '1:47${nnbsp}PM');
      expect(row(tomorrow), 'Tomorrow${nbsp}11:00${nnbsp}AM');
      expect(row(laterThisYear), 'Dec 24,${nbsp}1:47${nnbsp}PM');
      expect(
        awFormatDate(
          lastYear,
          format: sys,
          locale: 'en',
          region: 'US',
          now: now,
        ),
        'Nov 7, 2025',
      );
      expect(
        awFormatDateTime(at, format: sys, locale: 'en', region: 'US', now: now),
        'Today${nbsp}1:47${nnbsp}PM',
      );
    });

    test('numbers, money, percent, file size', () {
      expect(awFormatNumber(48500, locale: 'en', region: 'US'), '48,500');
      expect(
        awFormatMoney(4850000, 'USD', locale: 'en', region: 'US'),
        r'$48,500',
      );
      expect(awFormatPercent(51.4, locale: 'en', region: 'US'), '51.4%');
      expect(
        awFormatFileSize(6606029, locale: 'en', region: 'US'),
        '6.3${nbsp}MB',
      );
      expect(awFormatFileSize(12, locale: 'en', region: 'US'), 'Under 1 KB');
    });

    test('durations say days and hours in full, with plurals', () {
      expect(awFormatDuration(3600, locale: 'en'), '2 days 12 hours');
      expect(awFormatDuration(60, locale: 'en'), '1 hour');
      expect(awFormatDuration(1440, locale: 'en'), '1 day');
      expect(awFormatDuration(75, locale: 'en'), '1 hour 15 min');
    });
  });

  group('EN-DE (English UI on a German phone — D#39)', () {
    test('English words, German order and a 24-hour clock', () {
      expect(
        awFormatDateTime(
          at,
          format: sys,
          locale: 'en',
          region: 'DE',
          now: DateTime(2027, 1, 2),
        ),
        '7 Nov 2026,${nbsp}13:47',
        reason: 'the ADR-0063 example, read in 2027',
      );
      expect(
        awFormatShort(at, format: sys, locale: 'en', region: 'DE', now: now),
        '13:47',
      );
      expect(
        awFormatShort(
          laterThisYear,
          format: sys,
          locale: 'en',
          region: 'DE',
          now: now,
        ),
        '24 Dec,${nbsp}13:47',
      );
    });

    test('German separators under English words', () {
      expect(awFormatNumber(48500, locale: 'en', region: 'DE'), '48.500');
      expect(
        awFormatFileSize(6606029, locale: 'en', region: 'DE'),
        '6,3${nbsp}MB',
      );
      expect(awFormatPercent(51.4, locale: 'en', region: 'DE'), '51,4$nbsp%');
      expect(
        awFormatMoney(4850050, 'EUR', locale: 'en', region: 'DE'),
        '48.500,50$nbsp€',
      );
    });

    test('a typed "5/11" is day-first in Germany, month-first in the US', () {
      expect(awMonthFirst(format: sys, locale: 'en', region: 'DE'), isFalse);
      expect(awMonthFirst(format: sys, locale: 'en', region: 'US'), isTrue);
      expect(awMonthFirst(format: 'mdy_12h', locale: 'tr'), isTrue);
    });
  });

  group('region resolution', () {
    test('a Turkish UI in the US keeps Turkish words on a 12-hour clock', () {
      expect(
        awFormatTime(at, format: sys, locale: 'tr', region: 'US'),
        '1:47$nnbspÖS',
      );
    });

    test('no region, or a junk one, falls back to the language', () {
      expect(awConventions(language: 'tr', region: 'ZZ').uses24h, isTrue);
      expect(awConventions(language: 'en', region: '').order, AwDateOrder.mdy);
      expect(awConventions(language: 'en').order, AwDateOrder.mdy);
    });

    test('the device region is read once, from the first locale', () {
      final saved = awDeviceRegionOverride;
      addTearDown(() => awDeviceRegionOverride = saved);
      awDeviceRegionOverride = () => 'GB';
      expect(awFormatTime(at, format: sys, locale: 'en'), '13:47');
      expect(awConventions(language: 'en').order, AwDateOrder.dmy);
    });

    test('the widget clock draws with the same clock', () {
      expect(awTimePattern(format: sys, locale: 'en', region: 'DE'), 'HH:mm');
      expect(
        awTimePattern(format: sys, locale: 'en', region: 'US'),
        'h:mm a'.replaceAll(' ', nnbsp),
      );
      expect(awTimePattern(format: 'mdy_12h', locale: 'tr'), 'h:mm a');
    });
  });

  group('rules every reader shares', () {
    test('the default never writes a numeric date', () {
      for (final (locale, region) in [
        ('tr', 'TR'),
        ('en', 'US'),
        ('en', 'DE'),
        ('en', 'JP'),
      ]) {
        for (final v in [at, tomorrow, laterThisYear, lastYear]) {
          for (final text in [
            awFormatShort(
              v,
              format: sys,
              locale: locale,
              region: region,
              now: now,
            ),
            awFormatDateTime(
              v,
              format: sys,
              locale: locale,
              region: region,
              now: now,
            ),
            awFormatDate(
              v,
              format: sys,
              locale: locale,
              region: region,
              now: now,
            ),
          ]) {
            expect(
              text,
              isNot(matches(numericDate)),
              reason: '$locale-$region',
            );
          }
        }
      }
    });

    test('a ratio over nothing is a dash, not 0 %', () {
      expect(awFormatPercent(null), kAwNoValue);
      expect(awFormatPercent(double.nan), kAwNoValue);
    });

    test('a chosen format still wins (round 9 #5)', () {
      expect(
        awFormatDateTime(
          kAwDateFormatSample,
          format: 'dmy_dot',
          locale: 'tr',
          region: 'US',
        ),
        '31.12.2026 23:59',
      );
    });

    test('currencies that share a symbol stay apart (G-C-R6)', () {
      // In the US, USD keeps "$"; CAD, AUD and MXN — also "$" in intl's
      // table — are named by their code, so a worklog total in mixed
      // currencies never shows three identical "$100".
      String us(String code) =>
          awFormatMoney(10000, code, locale: 'en', region: 'US');
      expect(us('USD'), r'$100');
      expect(us('CAD'), 'CAD${nbsp}100');
      expect(us('AUD'), 'AUD${nbsp}100');
      expect({us('USD'), us('CAD'), us('AUD'), us('MXN')}, hasLength(4));
      // The region's own currency keeps its symbol: "$" is CAD in Canada.
      expect(awFormatMoney(10000, 'CAD', locale: 'en', region: 'CA'), r'$100');
      expect(
        awFormatMoney(10000, 'USD', locale: 'en', region: 'CA'),
        'USD${nbsp}100',
      );
      // Other shared symbols — "¥", "kr", "£" — follow the same rule; a
      // symbol only one currency uses stays.
      expect(
        awFormatMoney(10000, 'CNY', locale: 'en', region: 'US'),
        'CNY${nbsp}100',
      );
      expect(
        awFormatMoney(10050, 'NOK', locale: 'tr', region: 'TR'),
        'NOK${nbsp}100,50',
      );
      expect(
        awFormatMoney(10000, 'USD', locale: 'en', region: 'DE'),
        '100${nbsp}USD',
      );
      expect(awFormatMoney(10000, 'EUR', locale: 'en', region: 'US'), '€100');
      expect(awFormatMoney(10000, 'GBP', locale: 'en', region: 'GB'), '£100');
      expect(
        awFormatMoney(-10000, 'CAD', locale: 'en', region: 'US'),
        '-CAD${nbsp}100',
      );
    });

    test('a typed number keeps every decimal it was typed with (G-C-R7)', () {
      expect(awFormatNumberText('0.001', locale: 'en', region: 'US'), '0.001');
      expect(awFormatNumberText('0.001', locale: 'tr', region: 'TR'), '0,001');
      expect(
        awFormatNumberText('48500.125', locale: 'tr', region: 'TR'),
        '48.500,125',
      );
      expect(awFormatNumberText('2.50', locale: 'en', region: 'US'), '2.5');
      expect(awFormatNumberText('1e-3', locale: 'en', region: 'US'), '0.001');
      expect(awFormatNumberText('1.5e2', locale: 'en', region: 'US'), '150');
    });

    test('text that is not a number stays as typed', () {
      expect(awFormatNumberText('yaklaşık 5'), 'yaklaşık 5');
    });
  });
}
