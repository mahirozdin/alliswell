import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/notifications/alarmkit_identity.dart';
import 'package:alliswell/src/notifications/gateway.dart';

/// OPH-424 — the Dart half of the AlarmKit identity pair (NOTIFICATIONS.md
/// §2b.3). Dart is the fixture's author: `UPDATE_FIXTURES=1 flutter test` writes
/// `test/fixtures/alarmkit_identity_cases.json` from the cases below; every
/// other run compares byte for byte. The Swift tests read the same file and
/// never write it.
const _fixturePath = 'test/fixtures/alarmkit_identity_cases.json';

const _base = {
  'title': 'Görev',
  'body': 'Hatırlatma',
  'soundName': 'aw_alarm.caf',
  'stopLabel': 'Onayla',
  'snoozeLabel': '5 dk',
  'snoozePreset': '5_min',
};

/// Inputs only; ids, fingerprints and seeds are computed.
final List<Map<String, Object?>> _cases = [
  {
    'name': 'single member, whole second',
    'members': ['01JTASK0000000000000000001'],
    'rawFireAtMs': 1784116800000,
  },
  {
    'name': 'fireAt with a millisecond part is floored',
    'members': ['01JTASK0000000000000000001'],
    'rawFireAtMs': 1784116800999,
  },
  {
    'name': 'one ms before a second boundary',
    'members': ['01JTASK0000000000000000001'],
    'rawFireAtMs': 1767225599999,
  },
  {
    'name': 'unsorted members',
    'members': ['T3', 'T1', 'T2'],
    'rawFireAtMs': 1784116800000,
  },
  {
    'name': 'duplicated members collapse',
    'members': ['T2', 'T1', 'T2', 'T1'],
    'rawFireAtMs': 1784116800000,
  },
  {
    'name': 'members sort by UTF-16 code unit (upper before lower)',
    'members': ['b', 'B', 'a', 'A'],
    'rawFireAtMs': 1784116860000,
  },
  {
    'name': 'Turkish letters in the title',
    'members': ['T1'],
    'rawFireAtMs': 1784116800000,
    'title': 'ğüşıöçİ Ğ Ü Ş Ö Ç toplantısı',
  },
  {
    'name': 'emoji surrogate pair in title and body',
    'members': ['T1'],
    'rawFireAtMs': 1784116800000,
    'title': 'İlaç 💊',
    'body': 'Şimdi 🔔 al',
  },
  {
    'name': 'null sound (system alarm sound)',
    'members': ['T1'],
    'rawFireAtMs': 1784116800000,
    'soundName': null,
  },
  {
    'name': 'empty sound hashes like null',
    'members': ['T1'],
    'rawFireAtMs': 1784116800000,
    'soundName': '',
  },
  {
    'name': 'tomorrow_morning preset and its label',
    'members': ['T1'],
    'rawFireAtMs': 1784185200000,
    'snoozeLabel': 'Yarın sabah',
    'snoozePreset': 'tomorrow_morning',
  },
  {
    'name': 'English labels',
    'members': ['T1'],
    'rawFireAtMs': 1784116800000,
    'stopLabel': 'Acknowledge',
    'snoozeLabel': '30 min',
    'snoozePreset': '30_min',
  },
  {
    'name': 'privacy mode presentation',
    'members': ['T1'],
    'rawFireAtMs': 1784116800000,
    'title': 'AllisWell',
    'body': 'Bir hatırlatman var',
  },
  {
    'name': 'empty title and body',
    'members': ['T1'],
    'rawFireAtMs': 1784116800000,
    'title': '',
    'body': '',
  },
  {
    'name': 'separator characters inside text',
    'members': ['T1'],
    'rawFireAtMs': 1784116800000,
    'title': 'a|b,c',
    'body': '|',
  },
  {
    'name': 'group of ULID members, same minute',
    'members': ['01JZZ00000000000000000000B', '01JZZ00000000000000000000A'],
    'rawFireAtMs': 1784116830500,
  },
  {
    'name': 'epoch-scale fireAt far in the future',
    'members': ['T1'],
    'rawFireAtMs': 4102444799123,
  },
];

Map<String, Object?> _row(Map<String, Object?> input) {
  final p = {..._base, ...input};
  final members = (p['members']! as List).cast<String>();
  final fireAtMs = alarmKitFireAtMs(
    DateTime.fromMillisecondsSinceEpoch(p['rawFireAtMs']! as int, isUtc: true),
  );
  String s(String k) => p[k]! as String;
  final sound = p['soundName'] as String?;
  return {
    'name': p['name'],
    'members': members,
    'rawFireAtMs': p['rawFireAtMs'],
    'title': s('title'),
    'body': s('body'),
    'soundName': sound,
    'stopLabel': s('stopLabel'),
    'snoozeLabel': s('snoozeLabel'),
    'snoozePreset': s('snoozePreset'),
    'fireAtMs': fireAtMs,
    'sortedMembers': alarmKitMembers(members),
    'idSeed': alarmKitOccurrenceSeed(members, fireAtMs),
    'id': alarmKitOccurrenceId(members, fireAtMs),
    'fpSeed': alarmKitFingerprintSeed(
      title: s('title'),
      body: s('body'),
      soundName: sound,
      stopLabel: s('stopLabel'),
      snoozeLabel: s('snoozeLabel'),
      snoozePreset: s('snoozePreset'),
    ),
    'fp': alarmKitFingerprint(
      title: s('title'),
      body: s('body'),
      soundName: sound,
      stopLabel: s('stopLabel'),
      snoozeLabel: s('snoozeLabel'),
      snoozePreset: s('snoozePreset'),
    ),
  };
}

String _render() =>
    '${const JsonEncoder.withIndent('  ').convert({
      'contract': 'NOTIFICATIONS.md 2b.3 Identity',
      'note': 'Written by the Dart test (UPDATE_FIXTURES=1); every other reader only compares. fnv1a over UTF-16 code units, masked & 0x7fffffff.',
      'cases': [for (final c in _cases) _row(c)],
    })}\n';

void main() {
  test('FNV-1a matches the published 32-bit vectors (masked positive)', () {
    // fnv1a32('') = 0x811c9dc5, fnv1a32('a') = 0xe40c292c,
    // fnv1a32('foobar') = 0xbf9cf968 (reference vectors), masked & 0x7fffffff.
    expect(notificationIdFor(''), 0x811c9dc5 & 0x7fffffff);
    expect(notificationIdFor('a'), 0xe40c292c & 0x7fffffff);
    expect(notificationIdFor('foobar'), 0xbf9cf968 & 0x7fffffff);
    expect(alarmKitOccurrenceSeed(const [], 0), 'akv2||0');
    expect(
      alarmKitOccurrenceId(['T1'], 60000),
      notificationIdFor('akv2|T1|60000'),
    );
    expect(
      alarmKitFingerprintSeed(
        title: 't',
        body: 'b',
        soundName: null,
        stopLabel: 's',
        snoozeLabel: 'z',
        snoozePreset: 'p',
      ),
      'fp1|t|b||s|z|p',
    );
  });

  test('occurrence id and fingerprint match the shared fixture', () {
    final file = File(_fixturePath);
    final rendered = _render();
    if (Platform.environment['UPDATE_FIXTURES'] == '1') {
      file.writeAsStringSync(rendered);
    }
    expect(file.existsSync(), isTrue, reason: 'run with UPDATE_FIXTURES=1');
    final cases =
        ((jsonDecode(file.readAsStringSync()) as Map)['cases'] as List)
            .cast<Map<String, dynamic>>();
    expect(cases.length, greaterThanOrEqualTo(12));
    for (final c in cases) {
      final members = (c['members'] as List).cast<String>();
      final fireAtMs = alarmKitFireAtMs(
        DateTime.fromMillisecondsSinceEpoch(
          c['rawFireAtMs'] as int,
          isUtc: true,
        ),
      );
      final name = c['name'];
      expect(fireAtMs, c['fireAtMs'], reason: '$name fireAtMs');
      expect(fireAtMs % 1000, 0, reason: '$name floored');
      expect(
        alarmKitOccurrenceSeed(members, fireAtMs),
        c['idSeed'],
        reason: '$name idSeed',
      );
      expect(
        alarmKitOccurrenceId(members, fireAtMs),
        c['id'],
        reason: '$name id',
      );
      expect(
        alarmKitFingerprint(
          title: c['title'] as String,
          body: c['body'] as String,
          soundName: c['soundName'] as String?,
          stopLabel: c['stopLabel'] as String,
          snoozeLabel: c['snoozeLabel'] as String,
          snoozePreset: c['snoozePreset'] as String,
        ),
        c['fp'],
        reason: '$name fp',
      );
    }
    // Byte-stable: the committed file is exactly what the code renders.
    expect(file.readAsStringSync(), rendered);
  });

  test('ids depend only on the sorted unique members and the second', () {
    expect(
      alarmKitOccurrenceId(['T2', 'T1', 'T1'], 1000),
      alarmKitOccurrenceId(['T1', 'T2'], 1000),
    );
    expect(
      alarmKitOccurrenceId(['T1'], 1000),
      isNot(alarmKitOccurrenceId(['T1'], 2000)),
    );
    expect(
      alarmKitFireAtMs(DateTime.fromMillisecondsSinceEpoch(1999, isUtc: true)),
      1000,
    );
    // A local DateTime is read as its UTC instant.
    final utc = DateTime.utc(2026, 7, 15, 9, 0, 0, 450);
    expect(alarmKitFireAtMs(utc.toLocal()), alarmKitFireAtMs(utc));
  });

  test('null and empty sound share a fingerprint; any label changes it', () {
    int fp({
      String title = 'x',
      String? sound,
      String stop = 'Onayla',
      String snooze = '5 dk',
      String preset = '5_min',
    }) => alarmKitFingerprint(
      title: title,
      body: 'b',
      soundName: sound,
      stopLabel: stop,
      snoozeLabel: snooze,
      snoozePreset: preset,
    );
    expect(fp(sound: null), fp(sound: ''));
    final all = {
      fp(),
      fp(title: 'y'),
      fp(sound: 'aw_chime.caf'),
      fp(stop: 'Stop'),
      fp(snooze: '30 dk'),
      fp(preset: '30_min'),
    };
    expect(all, hasLength(6));
  });
}
