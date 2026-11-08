// P-01 (OPH-395, ADR-0063 #7) — missing glyphs on the web come from the app.
//
// When a text run has a character no registered font covers (会议, 😀, ★),
// the web engine fetches a Noto slice from `fontFallbackBaseUrl`. Its default
// is `https://fonts.gstatic.com/s/`, so every self-hosted browser that showed
// an emoji or a CJK title called Google. `web/flutter_bootstrap.js` now points
// the engine at the app's own `fonts/noto/`, and this tool fills that folder
// at BUILD time with exactly the files the installed engine asks for (its own
// `font_fallback_data.dart`, ~720 slices, ~21 MB; a browser fetches only the
// few slices its text needs).
//
// The build machine downloads them once; the user's browser never talks to
// Google. A bundle built without this step still makes no Google request: a
// missing glyph draws as a box instead.
//
// Usage (from apps/app, after `flutter build web`):
//   dart run tool/mirror_noto_fallback.dart [--out build/web/fonts/noto]
//
// Run it with the SAME Flutter SDK that built the bundle: the list (and the
// file versions in it) belongs to that engine revision.
import 'dart:async';
import 'dart:io';

/// The folder, relative to the page, that `fontFallbackBaseUrl` names.
const notoFallbackWebDir = 'fonts/noto/';

/// Where the engine's own default points; only the build machine reads it.
const _upstream = 'https://fonts.gstatic.com/s/';

/// The Flutter SDK root: `FLUTTER_ROOT` when the flutter tool set it, else the
/// SDK the running executable lives in (`bin/cache/dart-sdk/bin/dart`,
/// `bin/cache/artifacts/engine/<host>/flutter_tester`).
Directory flutterRootFromEnvironment() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return Directory(env);
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.parent.path != dir.path) {
    if (Directory('${dir.path}/bin/cache').existsSync() &&
        Directory('${dir.path}/packages/flutter').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  throw StateError(
    'cannot find the Flutter SDK; set FLUTTER_ROOT or pass --engine-data',
  );
}

/// The engine's generated fallback list inside a Flutter SDK.
File fallbackDataFile(Directory flutterRoot) => File(
  '${flutterRoot.path}/bin/cache/flutter_web_sdk/lib/_engine/engine/'
  'font_fallback_data.dart',
);

/// Every font path in [source] (the engine's `font_fallback_data.dart`),
/// relative to the fallback base URL, once each, in file order.
List<String> parseFallbackFontPaths(String source) {
  final pattern = RegExp(
    r"'([a-z0-9]+/v\d+/[A-Za-z0-9_.\-]+\.(?:woff2|ttf|otf))'",
  );
  final seen = <String>{};
  return [
    for (final m in pattern.allMatches(source))
      if (seen.add(m.group(1)!)) m.group(1)!,
  ];
}

Future<void> main(List<String> args) async {
  var out = 'build/web/$notoFallbackWebDir';
  String? enginePath;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--out' when i + 1 < args.length:
        out = args[++i];
      case '--engine-data' when i + 1 < args.length:
        enginePath = args[++i];
      default:
        stderr.writeln('unknown or incomplete argument: ${args[i]}');
        exitCode = 64;
        return;
    }
  }

  final data = enginePath != null
      ? File(enginePath)
      : fallbackDataFile(flutterRootFromEnvironment());
  if (!data.existsSync()) {
    stderr.writeln(
      'engine fallback list not found: ${data.path} '
      '(run `flutter build web` first so the web SDK is cached)',
    );
    exitCode = 1;
    return;
  }
  final paths = parseFallbackFontPaths(data.readAsStringSync());
  if (paths.isEmpty) {
    stderr.writeln('no font paths in ${data.path}: the engine format changed');
    exitCode = 1;
    return;
  }

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final failed = <String>[];
  var bytes = 0;
  var next = 0;

  Future<void> worker() async {
    while (next < paths.length) {
      final path = paths[next++];
      final file = File('$out/$path');
      if (file.existsSync() && file.lengthSync() > 0) {
        bytes += file.lengthSync();
        continue;
      }
      var ok = false;
      for (var attempt = 1; attempt <= 3 && !ok; attempt++) {
        try {
          final request = await client.getUrl(Uri.parse('$_upstream$path'));
          final response = await request.close();
          if (response.statusCode != 200) {
            await response.drain<void>();
            await Future<void>.delayed(Duration(seconds: attempt));
            continue;
          }
          final body = <int>[];
          await response.forEach(body.addAll);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(body);
          bytes += body.length;
          ok = true;
        } on IOException {
          await Future<void>.delayed(Duration(seconds: attempt));
        }
      }
      if (!ok) failed.add(path);
    }
  }

  await Future.wait([for (var i = 0; i < 16; i++) worker()]);
  client.close();

  if (failed.isNotEmpty) {
    stderr.writeln(
      '${failed.length} of ${paths.length} fallback fonts failed, '
      'e.g. ${failed.first}',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'mirrored ${paths.length} fallback fonts '
    '(${(bytes / 1048576).toStringAsFixed(1)} MB) into $out',
  );
}
