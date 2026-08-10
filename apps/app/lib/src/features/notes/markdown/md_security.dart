/// A markdown document is untrusted input (DESIGN §29 D10, OPH-247).
///
/// §24 AI6 was written for model output, but the rule was never about AI: it is
/// about rendering text somebody else wrote. A `README.md` from a stranger's
/// repository is exactly that, and it arrives through OPH-241's "open with"
/// handler without anyone vouching for it.
///
/// Two things follow, and they are the whole of this file:
///   * a link is only a link if its scheme is one we allow — everything else
///     renders as inert text, not as a tappable span that quietly does nothing;
///   * HTML is never live. It is shown as source.
///
/// The allowlist is deliberate. A denylist of `javascript:`/`data:` invites the
/// next scheme nobody thought of (`vbscript:`, `blob:`, `intent:`), which is the
/// same reasoning `scripts/android/assert-permissions.sh` uses for permissions.
library;

/// Schemes a rendered document may turn into a tappable link.
///
/// `alliswell` is here because our own notes embed `alliswell://file/{id}` and
/// `alliswell://task/{id}` (ADR-0016); it is in-app navigation, not the web.
const Set<String> kMdAllowedSchemes = {'http', 'https', 'mailto', 'alliswell'};

/// Whether [href] may become a tappable link.
///
/// Relative links (`./other.md`, `#heading`) have no scheme and are allowed
/// through: an in-document anchor is OPH-249's job and a relative path is
/// OPH-251's, and both are resolved against a base the reader controls — never
/// executed.
bool isSafeMarkdownLink(String? href) {
  if (href == null) return false;
  final trimmed = href.trim();
  if (trimmed.isEmpty) return false;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return false;
  if (!uri.hasScheme) return true; // relative or fragment

  return kMdAllowedSchemes.contains(uri.scheme.toLowerCase());
}

/// Whether [href] points somewhere inside the document rather than out of it.
String? inDocumentAnchor(String? href) {
  if (href == null) return null;
  final trimmed = href.trim();
  if (!trimmed.startsWith('#') || trimmed.length < 2) return null;
  return trimmed.substring(1);
}
