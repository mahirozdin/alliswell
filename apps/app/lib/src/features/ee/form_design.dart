import 'data/services_models.dart';

/// EE-229 — the form designer's rules, in plain Dart so they are tested
/// without a screen.
///
/// ── THE SERVER'S GRAMMAR, RESTATED ONLY WHERE A DESIGNER CAN BREAK IT ──
///
/// `formSchemaError` in the overlay's `services.js` is the law, and a publish
/// it refuses comes back as its own sentence. What is restated here is the
/// part a designer breaks WITHOUT typing anything wrong: dragging a question
/// above the one it depends on, deleting the one it depends on, or taking an
/// option away from the picker it waits for. Each of those is a click that
/// was fine a moment ago, so the row says so the moment it happens instead
/// of the publish failing later with a key name the admin has to decode.

/// Why a designed form cannot be published yet — one reason per question.
enum FormDesignProblem {
  /// The question this one depends on is gone.
  conditionTargetMissing,

  /// The question this one depends on is now BELOW it. A condition may only
  /// look backwards: the portal reveals questions by submitting (it has no
  /// script at all), so a forward one would wait for an answer to a question
  /// nobody has been asked yet.
  conditionLooksForward,

  /// The answer it waits for can no longer be given — an option was removed,
  /// or the question it looks at changed type.
  conditionValueGone,
}

/// The problems of a designed form, keyed by the question that has one.
/// Empty = publishable as far as the device can tell; the server still has
/// the last word.
Map<String, FormDesignProblem> formDesignProblems(List<EeServiceField> fields) {
  final at = {for (var i = 0; i < fields.length; i++) fields[i].key: i};
  final problems = <String, FormDesignProblem>{};
  for (var i = 0; i < fields.length; i++) {
    final condition = fields[i].showIf;
    if (condition == null) continue;
    final target = at[condition.key];
    if (target == null) {
      problems[fields[i].key] = FormDesignProblem.conditionTargetMissing;
    } else if (target >= i) {
      problems[fields[i].key] = FormDesignProblem.conditionLooksForward;
    } else if (!conditionValueAccepted(fields[target], condition.equals)) {
      problems[fields[i].key] = FormDesignProblem.conditionValueGone;
    }
  }
  return problems;
}

/// The one value a checkbox condition may name (EE-247): ticked, spelled the
/// way both doors now send it.
const kCheckboxTicked = 'true';

/// Can [target] be answered with [value]? The server's rule per type: a
/// picker only with one of its options, a checkbox only ticked, anything else
/// with any non-empty string of at most 80 characters.
bool conditionValueAccepted(EeServiceField target, String value) =>
    switch (target.type) {
      'select' => target.options.contains(value),
      'checkbox' => value == kCheckboxTicked,
      _ => value.isNotEmpty && value.length <= 80,
    };

/// Has the design changed? Every property the server stores, in order —
/// the comparison the old setup screen made left `help` and `showIf` out,
/// which is half of how EE-246 stayed invisible.
bool sameFormDesign(List<EeServiceField> a, List<EeServiceField> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i].toJson();
    final y = b[i].toJson();
    if (x.length != y.length) return false;
    for (final entry in x.entries) {
      final other = y[entry.key];
      final same = switch (entry.value) {
        final List<Object?> list =>
          other is List && list.join('\x00') == other.join('\x00'),
        final Map<String, Object?> map =>
          other is Map &&
              map['key'] == other['key'] &&
              map['equals'] == other['equals'],
        final value => value == other,
      };
      if (!same) return false;
    }
  }
  return true;
}

/// The server's key grammar: `a-z0-9_`, starting with a letter, ≤ 32.
final kFieldKeyPattern = RegExp(r'^[a-z][a-z0-9_]{0,31}$');

/// A machine key from a label, when the admin does not type one.
///
/// Turkish letters fold to ASCII first — `ç→c`, `ı→i`, … — because a key is
/// `a-z0-9_` on the server, so "Hat numarası" must not become "hat_numaras".
String fieldKeyFromLabel(String label) {
  const fold = {
    'ç': 'c',
    'ğ': 'g',
    'ı': 'i',
    'i̇': 'i',
    'ö': 'o',
    'ş': 's',
    'ü': 'u',
  };
  var out = label.toLowerCase();
  fold.forEach((from, to) => out = out.replaceAll(from, to));
  out = out.replaceAll(RegExp('[^a-z0-9]+'), '_');
  out = out.replaceAll(RegExp(r'^_+|_+$'), '');
  if (out.isEmpty) return '';
  if (RegExp('^[0-9]').hasMatch(out)) out = 'f_$out';
  return out.length > 32 ? out.substring(0, 32) : out;
}

/// The server's ceilings, named once for the screen and its tests.
const kFormMaxFields = 20;
const kFormMaxOptions = 20;
const kFormLabelMax = 80;
const kFormHelpMax = 200;
