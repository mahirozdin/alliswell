import 'package:alliswell/src/features/quick_access/data/quick_link.dart';
import 'package:alliswell/src/features/quick_access/ui/quick_access_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

/// OPH-203 — the kind × target-state table, as a pure function.
QuickAccessRow row(
  QuickKind kind, {
  String? targetId = 'T1',
  String? url,
  bool broken = false,
  bool archived = false,
}) => QuickAccessRow(
  link: QuickLink(
    id: 'Q1',
    workspaceId: 'W1',
    userId: 'user-1',
    kind: kind,
    title: 'Kısayol',
    targetId: kind == QuickKind.url ? null : targetId,
    url: url,
  ),
  targetTitle: broken || kind == QuickKind.url ? null : 'Hedef',
  isBroken: broken,
  isArchived: archived,
);

void main() {
  test('every live kind has a destination', () {
    expect(
      (quickDestinationFor(row(QuickKind.project)) as QuickGo).location,
      '/projects/T1',
    );
    expect(
      (quickDestinationFor(row(QuickKind.note)) as QuickGo).location,
      '/notes/T1',
    );
    // A task detail is a ROOT route, so it stacks above the shell like every
    // other detail screen — `push`, not `go`.
    expect(
      (quickDestinationFor(row(QuickKind.task)) as QuickPush).location,
      '/tasks/T1',
    );
    expect(
      (quickDestinationFor(row(QuickKind.folder)) as QuickGo).location,
      '/files/folder/T1',
    );
    // Files has no per-file route: the file's "page" IS its action sheet.
    expect(
      (quickDestinationFor(row(QuickKind.file)) as QuickFileSheet).fileId,
      'T1',
    );
    expect(
      (quickDestinationFor(row(QuickKind.url, url: 'https://x.dev'))
              as QuickExternal)
          .url
          .toString(),
      'https://x.dev',
    );
  });

  test('an archived target still navigates — archives are reversible', () {
    for (final kind in [QuickKind.project, QuickKind.note, QuickKind.task]) {
      final destination = quickDestinationFor(row(kind, archived: true));
      expect(
        destination,
        isNot(isA<QuickBroken>()),
        reason: '$kind must stay reachable while archived',
      );
    }
  });

  test('broken dominates kind — there is nowhere to go', () {
    for (final kind in [
      QuickKind.project,
      QuickKind.note,
      QuickKind.task,
      QuickKind.folder,
      QuickKind.file,
    ]) {
      expect(
        quickDestinationFor(row(kind, broken: true)),
        isA<QuickBroken>(),
        reason: '$kind with a missing target',
      );
    }
    // A target id that never arrived is the same story.
    expect(
      quickDestinationFor(row(QuickKind.project, targetId: null)),
      isA<QuickBroken>(),
    );
  });

  test('a url row we cannot parse is broken, not a crash', () {
    for (final url in [null, '', 'not a url', 'ftp:/x']) {
      expect(
        quickDestinationFor(row(QuickKind.url, url: url)),
        isA<QuickBroken>(),
        reason: 'url "$url"',
      );
    }
  });
}
