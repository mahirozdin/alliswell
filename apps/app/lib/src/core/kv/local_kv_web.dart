import 'package:web/web.dart' as web;

import 'local_kv.dart';

/// Web backend: window.localStorage, fully synchronous — cannot hang startup.
class _WebLocalKv implements LocalKv {
  @override
  Future<String?> get(String key) async {
    try {
      return web.window.localStorage.getItem(key);
    } on Object {
      return null; // storage blocked (private mode etc.)
    }
  }

  @override
  Future<void> set(String key, String value) async {
    try {
      web.window.localStorage.setItem(key, value);
    } on Object {
      // Quota/blocked — in-memory state still applies.
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      web.window.localStorage.removeItem(key);
    } on Object {
      // Ignore.
    }
  }

  @override
  Future<void> removeWhere(bool Function(String key) test) async {
    try {
      final storage = web.window.localStorage;
      final doomed = <String>[
        for (var i = 0; i < storage.length; i++)
          if (storage.key(i) case final key? when test(key)) key,
      ];
      for (final key in doomed) {
        storage.removeItem(key);
      }
    } on Object {
      // Ignore.
    }
  }
}

LocalKv createLocalKv() => _WebLocalKv();
