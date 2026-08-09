/// Turning a blob of text into a task's fields (OPH-243).
///
/// Pure and Flutter-free on purpose, like `core/fold.dart` and
/// `project_match.dart`: every rule here is a product decision that deserves a
/// unit test rather than a widget pump, and the `tasks` feature must not have
/// to import the `ai` feature to reuse it.
library;

/// The longest title we will generate. Longer text is not lost — it moves to
/// the description.
const int kTaskTitleMaxChars = 140;

/// The first line of [text], trimmed and clipped to [kTaskTitleMaxChars].
///
/// The clip is 139 characters plus an ellipsis so the result is exactly at the
/// limit, never one over it. Extracted from the AI bubble's `_clipTitle`
/// (OPH-224) so Inbox capture, "take note" and shared text all title things the
/// same way — three copies of this rule would drift.
///
/// The trim is new (OPH-243): pasted text routinely carries a space before its
/// newline, and a title with invisible trailing whitespace sorts and searches
/// strangely for a reason nobody can see.
String clipTaskTitle(String text) {
  final firstLine = text.split('\n').first.trim();
  return firstLine.length <= kTaskTitleMaxChars
      ? firstLine
      : '${firstLine.substring(0, kTaskTitleMaxChars - 1).trimRight()}…';
}

/// The title and description a shared blob of text becomes (OPH-243).
///
/// The rules, and why:
/// * the title is the first line, clipped — a person shares a paragraph and
///   means its opening as the name of the thing;
/// * the description carries the WHOLE text whenever the title is not already
///   the whole text, so nothing a person shared is ever silently dropped (this
///   is `captureToInbox`'s existing rule, kept identical on purpose);
/// * a shared URL goes at the END of the description, on its own line, because
///   it is provenance rather than content — and a link pasted into a title
///   makes the task unreadable in every list.
({String title, String? description}) taskFieldsFromSharedText(
  String text, {
  String? url,
}) {
  final trimmed = text.trim();
  final link = url?.trim();
  final title = clipTaskTitle(trimmed);

  // Compared by VALUE, not by length: the title is trimmed, so "Süt al  " and
  // "Süt al" must both count as "the title is already the whole text".
  final needsBody = trimmed != title;
  final hasLink = link != null && link.isNotEmpty && link != trimmed;

  if (!needsBody && !hasLink) return (title: title, description: null);

  final body = StringBuffer();
  if (needsBody) body.write(trimmed);
  if (hasLink) {
    if (body.isNotEmpty) body.write('\n');
    body.write(link);
  }
  return (title: title, description: body.toString());
}
