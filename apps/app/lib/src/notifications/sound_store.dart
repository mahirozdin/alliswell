import 'sound_store_io.dart'
    if (dart.library.js_interop) 'sound_store_web.dart'
    as impl;

/// Where a notification sound has to LIVE to be usable (OPH-181,
/// NOTIFICATIONS §2c).
///
/// `UNNotificationSound(named:)` resolves a name against the app container's
/// `Library/Sounds` **before** the app bundle, which is the whole reason a sound
/// can be added — or uploaded by the user — without touching Xcode. This is the
/// filesystem half, behind the same io/web seam as `LocalKv`: on the web there
/// is no container and no OS alarm, so every call is a no-op.
abstract interface class SoundStore {
  /// Copies a bundled Flutter asset into `Library/Sounds` if it is not there
  /// yet, and answers its file name (what the payload should carry).
  Future<String?> installAsset(String assetPath);

  /// Writes downloaded [bytes] as `<name>` in `Library/Sounds`.
  Future<String?> installBytes(String name, List<int> bytes);

  /// Whether `Library/Sounds/<name>` exists — the resolution guard (a name iOS
  /// cannot resolve silently degrades to the default ding, so we check instead
  /// of hoping).
  Future<bool> isInstalled(String name);

  /// Installed names, so stale uploads can be pruned.
  Future<List<String>> installed();

  Future<void> remove(String name);
}

/// Process-wide instance — the sounds directory has no per-caller state.
final SoundStore soundStore = impl.createSoundStore();
