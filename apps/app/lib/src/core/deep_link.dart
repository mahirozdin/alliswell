/// The `alliswell://` URL contract (OPH-189, ADR-0016).
///
/// The scheme has existed since ADR-0003, but only as a MARKER — the string we
/// write into a calendar event so the backend can map it back to a task.
/// Nothing consumed it, while three surfaces produced it: the home-screen
/// widgets (`alliswell://open`), note embeds (`alliswell://file/{id}`) and
/// calendar events (`alliswell://task/{id}`). Round 10 hit the consequence:
/// tapping the widget produced **"No route for alliswell://open/"**.
///
/// The rule that shapes everything here: **a URL is untrusted input.** It can
/// arrive from a calendar event synced out of somebody else's invite, from a
/// note another device wrote, from a link in an email. So this table only ever
/// NAVIGATES. Writes travel over signed App Intents into the App Group queue
/// (OPH-188) and never over a URL — `alliswell://complete?id=…` is deliberately
/// absent and must stay absent.
library;

/// The scheme this app answers to. Registered with both operating systems
/// (`CFBundleURLTypes`, the Android `intent-filter`); without that the OS never
/// launches us and the failure is silent.
const String kAwScheme = 'alliswell';

/// Crockford base32 (ULID) — no I, L, O or U, so a typo cannot masquerade as a
/// valid id. Anything that fails this is not routed.
final RegExp _ulid = RegExp(r'^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$');

/// Resolves an incoming URL to an in-app location, or null when there is
/// nothing sensible to do with it.
///
/// Null is NOT an error state: the sender may be a newer version of the app, or
/// a stale link from an older one. The caller opens normally instead of showing
/// a failure the user cannot act on.
String? awRouteForUri(Uri uri) {
  if (uri.scheme != kAwScheme) return null;
  // `alliswell://open` parses with host 'open' and no path; `alliswell:///x`
  // parses with an empty host. Treat the first segment as the verb either way.
  final segments = [
    if (uri.host.isNotEmpty) uri.host,
    ...uri.pathSegments.where((s) => s.isNotEmpty),
  ];
  if (segments.isEmpty) return null;

  switch (segments.first) {
    case 'open':
      // Extra segments mean a URL we do not understand — open Home rather than
      // guess, but only for the bare form.
      return segments.length == 1 ? '/home' : null;
    case 'task':
      if (segments.length != 2 || !_ulid.hasMatch(segments[1])) return null;
      return '/tasks/${segments[1]}';
    case 'file':
      if (segments.length != 2 || !_ulid.hasMatch(segments[1])) return null;
      // Files has no per-file route BY DECISION (OPH-199/203): a file's
      // "page" in this app is its action sheet, not a screen, so the section
      // is the honest destination for a link that arrives from outside.
      return '/files';
    default:
      return null;
  }
}

/// True for URLs this app owns but does not route — today only the widget's
/// background actions, which are handled by the App Intent queue long before
/// anything reaches the router. Kept explicit so a future reader sees that the
/// omission is a decision, not an oversight (ADR-0016).
bool awIsBackgroundAction(Uri uri) =>
    uri.scheme == kAwScheme && (uri.host == 'complete' || uri.host == 'add');

/// The iOS share extension's callback scheme: `ShareMedia-<host bundle id>`
/// (OPH-298, amends ADR-0029).
///
/// `RSIShareViewController.redirectToHostApp()` opens
/// `ShareMedia-<bundle id>:share` AFTER it has written the App Group.
/// ADR-0029 measured that open as a no-op on iOS 18 and built the App Group
/// drain because of it — but on iOS 26 it ARRIVES, and under the UIScene
/// lifecycle no plugin claims it, so Flutter hands the URL to the router as a
/// plain LOCATION. It matched no route, so the share ended on the error screen
/// ("Bu bağlantı … bir yere gitmiyor") — worse than the silence it replaced,
/// because that screen lives OUTSIDE the shell and the shell is what drains
/// the payload.
///
/// So this is not a destination, it is a NUDGE: the shared text never travels
/// in the URL (it is in the App Group), and the only thing the app owes this
/// URL is to come forward without an error.
///
/// Matched on the prefix alone, deliberately. The suffix is the host bundle id,
/// which differs per flavor, and the worst a forged `sharemedia-…:` link can
/// achieve is Home — this table only ever navigates.
const String kAwShareCallbackPrefix = 'sharemedia-';

/// True for the share extension's callback URL. `Uri` lowercases the scheme
/// and so does iOS on delivery; the extra `toLowerCase()` costs nothing and
/// makes the match independent of both.
bool awIsShareCallback(Uri uri) =>
    uri.scheme.toLowerCase().startsWith(kAwShareCallbackPrefix);
