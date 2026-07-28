import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'sound_store.dart';

/// Mobile/desktop backend for [SoundStore]: the app container's
/// `Library/Sounds` on Apple platforms, an equivalent app-support subfolder
/// elsewhere. Every call degrades to null/false rather than throwing — a sound
/// that cannot be installed must cost the user a DEFAULT ding, never an alarm.
class _FileSoundStore implements SoundStore {
  Directory? _cached;

  Future<Directory?> _dir() async {
    if (_cached != null) return _cached;
    try {
      // iOS/macOS: <container>/Library → the folder UNNotificationSound reads.
      final base = Platform.isIOS || Platform.isMacOS
          ? await getLibraryDirectory()
          : await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, 'Sounds'));
      if (!await dir.exists()) await dir.create(recursive: true);
      _cached = dir;
      return dir;
    } on Object {
      return null;
    }
  }

  @override
  Future<String?> installAsset(String assetPath) async {
    final name = p.basename(assetPath);
    final dir = await _dir();
    if (dir == null) return null;
    try {
      final file = File(p.join(dir.path, name));
      if (!await file.exists()) {
        final data = await rootBundle.load(assetPath);
        await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
      return name;
    } on Object {
      return null;
    }
  }

  @override
  Future<String?> installBytes(String name, List<int> bytes) async {
    final dir = await _dir();
    if (dir == null) return null;
    try {
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(bytes, flush: true);
      return name;
    } on Object {
      return null;
    }
  }

  @override
  Future<bool> isInstalled(String name) async {
    final dir = await _dir();
    if (dir == null) return false;
    try {
      return File(p.join(dir.path, name)).exists();
    } on Object {
      return false;
    }
  }

  @override
  Future<List<String>> installed() async {
    final dir = await _dir();
    if (dir == null) return const [];
    try {
      return [
        for (final entity in await dir.list().toList())
          if (entity is File) p.basename(entity.path),
      ];
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> remove(String name) async {
    final dir = await _dir();
    if (dir == null) return;
    try {
      final file = File(p.join(dir.path, name));
      if (await file.exists()) await file.delete();
    } on Object {
      // Nothing to do — a leftover sound file is harmless.
    }
  }
}

SoundStore createSoundStore() => _FileSoundStore();
