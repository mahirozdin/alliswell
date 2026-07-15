import 'dart:math';

const _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
final _random = Random.secure();

/// Generates a ULID (26 Crockford-base32 chars: 48-bit ms timestamp +
/// 80-bit randomness) — the id format every AllisWell entity uses (ADR-0004).
/// Client-side ids let offline creates pick their identity before the server
/// ever sees them (BLUEPRINT §6.3).
String newUlid({DateTime? now}) {
  var millis = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final chars = List.filled(26, '0');
  for (var i = 9; i >= 0; i--) {
    chars[i] = _crockford[millis % 32];
    millis ~/= 32;
  }
  for (var i = 10; i < 26; i++) {
    chars[i] = _crockford[_random.nextInt(32)];
  }
  return chars.join();
}
