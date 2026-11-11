import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/tr_locative.dart';

// #46 / OPH-422: "09:00’de çalar" was a hard-coded suffix. Turkish picks
// ’da/’de/’ta/’te from the last SPOKEN word: for a clock time that is the
// minutes, or the hour when the minutes are 00; for a name, the last vowel
// and the final consonant.
void main() {
  test('clock times take the suffix of their last spoken number '
      '(09:05’te, 09:30’da, 09:00’da, 10:00’da, 13:40’ta, 00:00’da)', () {
    expect(trLocative('09:05'), '09:05’te'); // beş
    expect(trLocative('09:30'), '09:30’da'); // otuz
    expect(trLocative('09:00'), '09:00’da'); // dokuz
    expect(trLocative('10:00'), '10:00’da'); // on
    expect(trLocative('13:40'), '13:40’ta'); // kırk
    expect(trLocative('00:00'), '00:00’da'); // sıfır
    // Every units word and every round tens word, once.
    const units = {
      1: '’de', // bir
      2: '’de', // iki
      3: '’te', // üç
      4: '’te', // dört
      5: '’te', // beş
      6: '’da', // altı
      7: '’de', // yedi
      8: '’de', // sekiz
      9: '’da', // dokuz
    };
    units.forEach((n, suffix) {
      expect(trLocative('09:1$n'), '09:1$n$suffix', reason: 'minute 1$n');
      expect(trLocative('$n:00'), '$n:00$suffix', reason: 'hour $n');
    });
    expect(trLocative('09:10'), '09:10’da'); // on
    expect(trLocative('09:20'), '09:20’de'); // yirmi
    expect(trLocative('09:50'), '09:50’de'); // elli
    expect(trLocative('20:00'), '20:00’de'); // yirmi
    expect(trLocative('12:00'), '12:00’de'); // on iki
    expect(trLocative('23:00'), '23:00’te'); // yirmi üç
  });

  test('device names follow vowel harmony and the hard-consonant rule '
      '(iPhone 16’da, MacBook Air’de, Pixel’de, Chrome’da)', () {
    expect(trLocative('iPhone 16'), 'iPhone 16’da');
    expect(trLocative('MacBook Air'), 'MacBook Air’de');
    expect(trLocative('Pixel'), 'Pixel’de');
    expect(trLocative('Chrome'), 'Chrome’da');
    // Harmony on the last vowel; f s t k ç ş h p (and x, read "ks") harden.
    expect(trLocative('iPhone'), 'iPhone’da');
    expect(trLocative('Firefox'), 'Firefox’ta');
    expect(trLocative('Windows'), 'Windows’ta');
    expect(trLocative('Safari'), 'Safari’de');
    expect(trLocative('Edge'), 'Edge’de');
    expect(trLocative('MacBook'), 'MacBook’ta');
    expect(trLocative('Galaxy S24'), 'Galaxy S24’te');
    expect(trLocative('Galaxy'), 'Galaxy’de');
    expect(trLocative('Telefon'), 'Telefon’da');
    expect(trLocative('Tablet'), 'Tablet’te');
    expect(trLocative('Ofis'), 'Ofis’te');
    expect(trLocative('IŞIK'), 'IŞIK’ta'); // four capitals: a word, not letters
    expect(trLocative('Ayşe'), 'Ayşe’de');
    expect(trLocative('Masaüstü'), 'Masaüstü’de');
    // Abbreviations are read letter by letter ("pe ce", "ö se").
    expect(trLocative('PC'), 'PC’de');
    expect(trLocative('9:05 ÖS'), '9:05 ÖS’de');
    // Round numbers take the word of their last non-zero place.
    expect(trLocative('Pixel 100'), 'Pixel 100’de'); // yüz
    expect(trLocative('Pixel 60'), 'Pixel 60’ta'); // altmış
    expect(trLocative('Pixel 0'), 'Pixel 0’da'); // sıfır
  });

  test('awAt suffixes in Turkish only and leaves other languages alone', () {
    expect(awAt('09:05', languageCode: 'tr'), '09:05’te');
    expect(awAt('09:05', languageCode: 'en'), '09:05');
    expect(awAt('iPhone 16', languageCode: 'en'), 'iPhone 16');
    expect(awAt('', languageCode: 'tr'), '');
  });
}
