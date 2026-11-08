// OPH-398 (polish 3, D-4): the R-03 barrier rule reaches every menu path.
//
// Polish 2 moved the popup menus to AwPopupMenuButton, whose barrier node
// ("Dismiss menu") lies beside the menu. Material's dropdown fields
// (DropdownButtonFormField / DropdownButton, e.g. the task detail's Durum,
// Öncelik and Proje) still opened Material's own dropdown route, whose
// barrier node is the whole screen: its centre — where VoiceOver draws the
// focus and an accessibility tap lands — sat on the open list and picked the
// item there. These tests pin the dropdown's barrier to the free area, check
// that its centre and its own tap action close without choosing, that items
// (a null "none" item included) still choose, and that no Material menu route
// is left in the app's code.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alliswell/src/theme/theme.dart';
import 'package:alliswell/src/widgets/dropdown_field.dart';

void main() {
  late List<String?> changes;

  setUp(() => changes = []);

  List<DropdownMenuItem<String?>> items() => const [
    DropdownMenuItem(value: null, child: Text('None')),
    DropdownMenuItem(value: 'open', child: Text('Open')),
    DropdownMenuItem(value: 'done', child: Text('Done')),
    DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
  ];

  Future<void> pumpField(
    WidgetTester tester, {
    String? initial = 'open',
    bool bare = false,
    double top = 380,
  }) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAwTheme(Brightness.dark),
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.fromLTRB(16, top, 16, 0),
            child: Align(
              alignment: Alignment.topCenter,
              child: bare
                  ? _BareHost(initial: initial, onChanged: changes.add)
                  : AwDropdownField<String?>(
                      key: const Key('status-dropdown'),
                      isExpanded: true,
                      initialValue: initial,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: items(),
                      onChanged: changes.add,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Finder menuList() => find.byType(ListBody).last;

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final bare in [false, true]) {
      testWidgets('a dropdown\'s barrier sits beside its list, and its centre '
          'closes without choosing (${platform.name}, '
          '${bare ? 'bare button' : 'form field'})', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final handle = tester.ensureSemantics();
        await pumpField(tester, bare: bare);

        await tester.tap(find.byKey(const Key('status-dropdown')));
        await tester.pumpAndSettle();

        // The open list's entries (every label's last copy is the list's).
        final menu = ['None', 'Open', 'Done', 'Cancelled']
            .map((t) => tester.getRect(find.text(t).last))
            .reduce((a, b) => a.expandToInclude(b));
        final barrier = tester.getSemantics(
          find.bySemanticsLabel('Dismiss menu'),
        );
        expect(barrier.transform, isNull);
        expect(
          barrier.rect.overlaps(menu),
          isFalse,
          reason: 'barrier ${barrier.rect} vs list $menu',
        );
        expect(barrier.rect.width, greaterThanOrEqualTo(44));
        expect(barrier.rect.height, greaterThanOrEqualTo(44));

        await tester.tapAt(barrier.rect.center);
        await tester.pumpAndSettle();
        expect(find.text('Cancelled'), findsNothing);
        expect(changes, isEmpty);

        handle.dispose();
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  testWidgets('the barrier\'s own tap action closes the list without '
      'choosing', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final handle = tester.ensureSemantics();
    await pumpField(tester);
    await tester.tap(find.byKey(const Key('status-dropdown')));
    await tester.pumpAndSettle();

    tester.semantics.tap(find.semantics.byLabel('Dismiss menu'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelled'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(changes, isEmpty);

    handle.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('an item chooses, the current one is announced as selected, '
      'and the list is at least as wide as the field', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpField(tester);
    final field = tester.getRect(find.byKey(const Key('status-dropdown')));
    await tester.tap(find.byKey(const Key('status-dropdown')));
    await tester.pumpAndSettle();

    final menu = tester.getRect(menuList());
    expect(menu.width, greaterThanOrEqualTo(field.width - 0.5));
    // The list opens over the field, as Material's dropdown did.
    expect(menu.overlaps(field), isTrue);
    expect(
      tester.getSemantics(find.text('Open').last),
      isSemantics(isSelected: true, hasSelectedState: true),
    );
    expect(
      tester.getSemantics(find.text('Done').last),
      isSemantics(isSelected: false, hasSelectedState: true),
    );

    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    expect(changes, ['done']);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Cancelled'), findsNothing);

    // A null "none" entry is a real choice, not a cancel.
    await tester.tap(find.byKey(const Key('status-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None').last);
    await tester.pumpAndSettle();
    expect(changes, ['done', null]);
    expect(find.text('None'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a field whose initial value changes shows the new value, as '
      'DropdownButtonFormField did', (tester) async {
    await pumpField(tester);
    expect(find.text('Open'), findsOneWidget);
    await pumpField(tester, initial: 'cancelled');
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
  });

  testWidgets('a field without onChanged is disabled and does not open', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAwTheme(Brightness.light),
        home: Scaffold(
          body: AwDropdownField<String?>(
            key: const Key('status-dropdown'),
            initialValue: 'open',
            items: items(),
            onChanged: null,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('status-dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsNothing);
  });

  test('no Material menu route is left in the app (DESIGN §5 barrier rule)', () {
    // Material's PopupMenuButton, showMenu, DropdownButton and
    // DropdownButtonFormField all push a route whose barrier node is the
    // whole screen. AwPopupMenuButton / AwDropdownField / AwDropdownButton
    // replace them; MenuAnchor has no barrier and is fine.
    final banned = RegExp(
      r'\b(PopupMenuButton|DropdownButtonFormField|DropdownButton|DropdownMenu)\s*<'
      r'|\bshowMenu\s*[<(]',
    );
    final hits = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (banned.hasMatch(line)) hits.add('${file.path}:${i + 1}: $line');
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}

class _BareHost extends StatefulWidget {
  const _BareHost({required this.initial, required this.onChanged});

  final String? initial;
  final ValueChanged<String?> onChanged;

  @override
  State<_BareHost> createState() => _BareHostState();
}

class _BareHostState extends State<_BareHost> {
  late String? _value = widget.initial;

  @override
  Widget build(BuildContext context) => AwDropdownButton<String?>(
    key: const Key('status-dropdown'),
    value: _value,
    items: const [
      DropdownMenuItem(value: null, child: Text('None')),
      DropdownMenuItem(value: 'open', child: Text('Open')),
      DropdownMenuItem(value: 'done', child: Text('Done')),
      DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
    ],
    onChanged: (v) {
      widget.onChanged(v);
      setState(() => _value = v);
    },
  );
}
