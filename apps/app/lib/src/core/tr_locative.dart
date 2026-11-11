/// The Turkish locative suffix (’da/’de/’ta/’te) for a value that is filled
/// into a sentence at runtime: a clock time or a device name (#46, OPH-422).
///
/// A catalogue string cannot carry the suffix itself: "{time}’de çalar" is
/// right for 09:20 and wrong for 09:05 ("dokuz beş’te"). Turkish picks the
/// suffix from the LAST SPOKEN WORD of the value:
/// - a clock time "H:MM" is read as hour then minutes, so the minutes decide,
///   or the hour when the minutes are 00 (00:00 is "sıfır");
/// - a number takes the word of its last non-zero place: the units word, the
///   round tens word (on, yirmi, otuz, kırk, elli, altmış…), yüz, bin…;
/// - a word takes its last vowel (a ı o u → a, e i ö ü → e) and its final
///   sound (f s t k ç ş h p → t, anything else → d);
/// - a 2–3 letter all-capital abbreviation is read letter by letter
///   ("pe ce", "ö se"), so its last letter's name decides.
///
/// Pure and locale-free; [awAt] is the call site's entry point.
library;

const String _apostrophe = '’';

/// [value] in Turkish with the locative suffix that its last spoken word
/// takes: "09:05" → "09:05’te", "iPhone 16" → "iPhone 16’da".
/// An empty value comes back unchanged.
String trLocative(String value) {
  final trimmed = value.trimRight();
  if (trimmed.isEmpty) return value;
  return '$value$_apostrophe${_suffixOf(trimmed)}';
}

/// [value] ready to stand where an English sentence says "at {value}": in
/// Turkish ([languageCode] `tr`) it carries the locative suffix, in every
/// other language it is returned as is (the catalogue string says "at").
String awAt(String value, {required String languageCode}) =>
    languageCode == 'tr' ? trLocative(value) : value;

final RegExp _clockAtEnd = RegExp(r'(\d{1,2}):(\d{2})$');
final RegExp _digitsAtEnd = RegExp(r'(\d+)$');
final RegExp _lastToken = RegExp(r'([^\s\d]+)$');

String _suffixOf(String value) {
  final clock = _clockAtEnd.firstMatch(value);
  if (clock != null) {
    final minutes = clock.group(2)!;
    return minutes == '00'
        ? _numberSuffix(int.parse(clock.group(1)!).toString())
        : _numberSuffix(int.parse(minutes).toString());
  }
  final digits = _digitsAtEnd.firstMatch(value);
  if (digits != null) return _numberSuffix(digits.group(1)!);
  final token = _lastToken.firstMatch(value)?.group(1) ?? value;
  return _wordSuffix(token);
}

/// The suffix after a written number, by the word it is read with last.
String _numberSuffix(String digits) {
  var zeros = 0;
  for (var i = digits.length - 1; i >= 0 && digits[i] == '0'; i--) {
    zeros++;
  }
  if (zeros == digits.length) return 'da'; // sıfır
  final last = int.parse(digits[digits.length - 1 - zeros]);
  if (zeros == 0) return _units[last]!;
  if (zeros == 1) return _tens[last]!;
  if (zeros == 2) return 'de'; // yüz
  if (zeros <= 5) return 'de'; // bin (on bin, yüz bin)
  return 'da'; // milyon, milyar, trilyon
}

const Map<int, String> _units = {
  1: 'de', // bir
  2: 'de', // iki
  3: 'te', // üç
  4: 'te', // dört
  5: 'te', // beş
  6: 'da', // altı
  7: 'de', // yedi
  8: 'de', // sekiz
  9: 'da', // dokuz
};

const Map<int, String> _tens = {
  1: 'da', // on
  2: 'de', // yirmi
  3: 'da', // otuz
  4: 'ta', // kırk
  5: 'de', // elli
  6: 'ta', // altmış
  7: 'te', // yetmiş
  8: 'de', // seksen
  9: 'da', // doksan
};

const String _backVowels = 'aıou';
const String _frontVowels = 'eiöü';
const String _hard = 'fstkçşhpx'; // x is read "ks"
const String _turkishOnly = 'çğıöşü';

String _turkishLower(String s) =>
    s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// The suffix after a word or abbreviation (trailing punctuation ignored).
String _wordSuffix(String token) {
  final letters = token.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '');
  if (letters.isEmpty) return 'de';
  if (letters.length <= 3 &&
      letters.length >= 2 &&
      letters == letters.toUpperCase() &&
      letters != _turkishLower(letters)) {
    return _letterNameSuffix(_turkishLower(letters[letters.length - 1]));
  }
  var word = _turkishLower(letters);
  final latinOnly = !word.split('').any(_turkishOnly.contains);
  if (latinOnly) {
    // A borrowed name is said the way it is said in English: the final e of
    // "Chrome" / "iPhone" is silent, and a final y after a consonant is "i".
    if (word.length >= 4 &&
        RegExp(r'[aeiou][b-df-hj-np-tv-z]e$').hasMatch(word)) {
      word = word.substring(0, word.length - 1);
    } else if (RegExp(r'[^aeiou]y$').hasMatch(word)) {
      word = '${word.substring(0, word.length - 1)}i';
    }
  }
  String? vowel;
  for (var i = word.length - 1; i >= 0; i--) {
    final c = word[i];
    if (_backVowels.contains(c) || _frontVowels.contains(c)) {
      vowel = c;
      break;
    }
  }
  final harmony = vowel == null || _frontVowels.contains(vowel) ? 'e' : 'a';
  final hard = _hard.contains(word[word.length - 1]);
  return '${hard ? 't' : 'd'}$harmony';
}

/// An abbreviation read letter by letter ends on its last letter's name:
/// a vowel is its own sound, "ka" (K) is back, every other consonant name
/// ends in "e" ("be", "ce", "pe", "se"…), which is soft.
String _letterNameSuffix(String letter) {
  if (_backVowels.contains(letter)) return 'da';
  if (_frontVowels.contains(letter)) return 'de';
  if (letter == 'k') return 'da';
  return 'de';
}
