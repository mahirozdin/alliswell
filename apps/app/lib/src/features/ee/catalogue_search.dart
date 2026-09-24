import '../../core/fold.dart';

/// EE-212, EE-228 — "this catalogue entry matches what was typed", on the
/// device, ONE rule for both places a catalogue is searched: the requester's
/// picker (EE-225) and the admin's catalogue screen.
///
/// The catalogue arrives whole over REST and is not a sync entity, so it is
/// filtered in memory with ADR-0013's single fold (`foldSearchText`) —
/// `yazici` finds `Yazıcı` — and the server is not asked for a third
/// definition of "matches" (`check:no-server-search`). The typed text is one
/// folded substring of the entry's words, which is what the picker has done
/// since EE-225; an empty query matches everything.
bool catalogueMatches(String query, Iterable<String?> words) {
  final needle = foldSearchText(query);
  if (needle.isEmpty) return true;
  return foldSearchText(words.whereType<String>().join(' ')).contains(needle);
}
