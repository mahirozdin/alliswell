/// How loud a browser's notifications are on THIS device (OPH-316).
///
/// The report this came from asked for "a reminder which does not ring with
/// sound, but just pops up with a window on the computer screen … so it is
/// less disturbing to colleagues during office hours". That is not a privacy
/// setting and not a schedule — it is how insistent delivery is, which every
/// other delivery preference already treats as device-local (`providers.dart`:
/// each device owns how insistent they are).
///
/// Three values rather than a switch, because "off" and "silent" are different
/// promises: silent still shows the window.
enum WebAlertMode {
  /// Nothing arrives. The browser's subscription is dropped, so the server has
  /// nowhere to send — not a worker that receives and stays quiet, which it
  /// could not do anyway: a push subscription is `userVisibleOnly`, and a
  /// handler that shows nothing gets the browser's own generic card instead.
  off,

  /// The window opens without a sound. The default: permission is already an
  /// explicit opt-in, so the quieter of the two audible states is the safer
  /// thing to grant.
  silent,

  /// The window opens and the device makes noise, like any other platform.
  loud;

  /// Unknown text resolves to [silent] — the same rule every other persisted
  /// choice uses, and the value that surprises nobody.
  static WebAlertMode parse(String? raw) => switch (raw) {
    'off' => WebAlertMode.off,
    'loud' => WebAlertMode.loud,
    _ => WebAlertMode.silent,
  };

  String get id => name;

  /// Whether a notification this mode produces should arrive without a sound.
  /// `off` reads as silent so that a stale cache entry written before the user
  /// turned delivery off can never be the loud one.
  bool get silences => this != WebAlertMode.loud;
}
