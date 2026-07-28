import 'sound_store.dart';

/// Web backend for [SoundStore]: there is no app container and no OS alarm on
/// the web (NOTIFICATIONS §3), so nothing can be installed. The in-app bed —
/// the web's ONLY alarm surface — plays Flutter assets directly and needs none
/// of this.
class _NoSoundStore implements SoundStore {
  const _NoSoundStore();

  @override
  Future<String?> installAsset(String assetPath) async => null;

  @override
  Future<String?> installBytes(String name, List<int> bytes) async => null;

  @override
  Future<bool> isInstalled(String name) async => false;

  @override
  Future<List<String>> installed() async => const [];

  @override
  Future<void> remove(String name) async {}
}

SoundStore createSoundStore() => const _NoSoundStore();
