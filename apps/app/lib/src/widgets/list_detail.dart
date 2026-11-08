import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// A list with its open item's detail beside it (OPH-405, U-08, DESIGN §51).
///
/// From [kAwPaneBreakpoint] a list no longer pushes a detail page over
/// itself: the item opens in a [kAwDetailPaneWidth] pane on the right, the
/// list stays where it was, Escape closes the pane and ↑/↓ open the
/// previous/next item of the list it was opened from. Below the breakpoint
/// nothing changes — [AwListDetailScope.maybeOf] answers null and the caller
/// pushes its page as before.
///
/// Three pieces, so any list can take part without knowing who hosts it:
///  * [AwListDetailScope] holds what is open, and the keys. It sits high
///    enough that everything that opens items is under it (the shell);
///  * [AwListDetailPane] lays the pane out beside its child;
///  * [AwListOrder] wraps a list and says its items' order, so ↑/↓ follow
///    what the person sees.
///
/// A [kind] keeps two scopes apart: a task row inside a request's detail
/// opens in the task pane, not in the request pane that is nearer to it.
const String kAwTaskPane = 'task';

/// What a row talks to. Only handed out while the pane can show (the window
/// is at least [kAwPaneBreakpoint] wide).
abstract interface class AwListDetailController {
  /// The item the pane shows, or null when it is closed.
  String? get selectedId;

  /// Shows [id] in the pane. [order] is the list it was opened from, for
  /// ↑/↓; without one the arrows do nothing.
  void open(String id, {AwListOrderHandle? order});

  void close();

  /// Opens the item [delta] places away in the list the pane was opened
  /// from. At either end it stays where it is.
  void step(int delta);
}

/// Whether the focused control is a text field — the field wins every key
/// a list shortcut would also want (DESIGN §40 P1's rule): an arrow moves
/// its caret, a letter is typed.
bool awTextInputFocused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  if (context.widget is EditableText) return true;
  return context.findAncestorStateOfType<EditableTextState>() != null;
}

class AwListDetailScope extends StatefulWidget {
  const AwListDetailScope({
    super.key,
    required this.kind,
    required this.child,
    this.resetToken,
    this.onShow,
  });

  final String kind;

  /// Called with each item the pane comes to show — opened from a row or
  /// reached with ↑/↓. The address never changes for a pane visit, so a
  /// route observer (the search recents, ADR-0055) cannot see it; the host
  /// records it here instead (P-07).
  final ValueChanged<String>? onShow;

  /// A change closes the pane: the shell passes its section, so switching
  /// sections does not leave a task from the last one open.
  final Object? resetToken;

  final Widget child;

  /// The nearest scope of [kind] when its pane can show, else null.
  ///
  /// [listen] false asks without subscribing — for a tap handler, which is
  /// not a build (OPH-410: the extension's "open this request" helper).
  static AwListDetailController? maybeOf(
    BuildContext context,
    String kind, {
    bool listen = true,
  }) {
    var element = context
        .getElementForInheritedWidgetOfExactType<_AwListDetailInherited>();
    while (element != null) {
      final scope = element.widget as _AwListDetailInherited;
      if (scope.kind == kind) {
        if (listen) context.dependOnInheritedElement(element);
        return scope.active ? scope.controller : null;
      }
      InheritedElement? outer;
      element.visitAncestorElements((ancestor) {
        if (ancestor is InheritedElement &&
            ancestor.widget is _AwListDetailInherited) {
          outer = ancestor;
          return false;
        }
        return true;
      });
      element = outer;
    }
    return null;
  }

  /// Whether the pane of [kind] is open beside its list — a page that keeps
  /// its wide form at a width it would otherwise give up asks this.
  static bool isOpen(BuildContext context, String kind) =>
      maybeOf(context, kind)?.selectedId != null;

  @override
  State<AwListDetailScope> createState() => _AwListDetailScopeState();
}

class _AwListDetailScopeState extends State<AwListDetailScope>
    implements AwListDetailController {
  final FocusNode _keys = FocusNode(
    debugLabel: 'list-detail-keys',
    skipTraversal: true,
  );
  String? _selected;
  AwListOrderHandle? _order;

  @override
  String? get selectedId => _selected;

  @override
  void didUpdateWidget(covariant AwListDetailScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetToken != oldWidget.resetToken) {
      _selected = null;
      _order = null;
    }
  }

  @override
  void dispose() {
    _keys.dispose();
    super.dispose();
  }

  @override
  void open(String id, {AwListOrderHandle? order}) {
    setState(() {
      _selected = id;
      _order = order;
      final at = order?.ids?.indexOf(id) ?? -1;
      _heldIndex = at < 0 ? null : at;
    });
    widget.onShow?.call(id);
    // The keys work at once, without a click into the pane first.
    if (!awTextInputFocused()) _keys.requestFocus();
  }

  @override
  void close() {
    if (_selected == null) return;
    setState(() {
      _selected = null;
      _order = null;
    });
  }

  @override
  void step(int delta) {
    final selected = _selected;
    final ids = _order?.ids;
    if (selected == null || ids == null) return;
    if (ids.isEmpty) return;
    final at = ids.indexOf(selected);
    final int next;
    if (at >= 0) {
      next = (at + delta).clamp(0, ids.length - 1);
      if (next == at) return;
    } else {
      // The open item left the list (completed from the pane): the arrows
      // go on from the place it held — the row that slid into it is "next".
      final held = (_heldIndex ?? 0).clamp(0, ids.length);
      next = (delta > 0 ? held : held - 1).clamp(0, ids.length - 1);
    }
    _heldIndex = next;
    setState(() => _selected = ids[next]);
    _order?.reached(ids[next]);
    widget.onShow?.call(ids[next]);
    _order?.reveal(ids[next], forward: delta > 0);
  }

  /// Where the open item stood in its list when it was last found there.
  int? _heldIndex;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_selected == null || !_active) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      // In a field Escape first leaves the field; the next one closes.
      if (awTextInputFocused()) {
        FocusManager.instance.primaryFocus?.unfocus();
        _keys.requestFocus();
      } else {
        close();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (awTextInputFocused()) return KeyEventResult.ignored;
      if (HardwareKeyboard.instance.isShiftPressed ||
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isAltPressed) {
        return KeyEventResult.ignored;
      }
      step(key == LogicalKeyboardKey.arrowUp ? -1 : 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _active = false;

  @override
  Widget build(BuildContext context) {
    _active = MediaQuery.sizeOf(context).width >= kAwPaneBreakpoint;
    // Narrowed below the desktop: the pane is gone, and so is what it held —
    // widening again shows the list, not a detail from minutes ago.
    if (!_active) {
      _selected = null;
      _order = null;
    }
    return Focus(
      focusNode: _keys,
      // A key handler, not a control: nothing for a screen reader.
      includeSemantics: false,
      onKeyEvent: _onKey,
      child: _AwListDetailInherited(
        kind: widget.kind,
        active: _active,
        selected: _selected,
        controller: this,
        child: widget.child,
      ),
    );
  }
}

class _AwListDetailInherited extends InheritedWidget {
  const _AwListDetailInherited({
    required this.kind,
    required this.active,
    required this.selected,
    required this.controller,
    required super.child,
  });

  final String kind;
  final bool active;
  final String? selected;
  final AwListDetailController controller;

  @override
  bool updateShouldNotify(_AwListDetailInherited old) =>
      active != old.active || selected != old.selected || kind != old.kind;
}

/// The list beside the open item's pane. [detailBuilder] gets the item and
/// the way to close it; the detail is keyed by the item, so moving with ↑/↓
/// starts each one fresh.
class AwListDetailPane extends StatelessWidget {
  const AwListDetailPane({
    super.key,
    required this.kind,
    required this.detailBuilder,
    required this.child,
  });

  final String kind;
  final Widget Function(BuildContext context, String id, VoidCallback close)
  detailBuilder;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = AwListDetailScope.maybeOf(context, kind);
    final selected = controller?.selectedId;
    final scheme = Theme.of(context).colorScheme;
    // One shape open or closed (OPH-410): the list stays the same element
    // when the pane opens beside it, so it keeps its scroll offset and the
    // order ↑/↓ were handed — returning the bare child when closed rebuilt
    // the list from scratch on every open.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: child),
        if (controller != null && selected != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              0,
              AwSpace.x3,
              AwSpace.x3,
              AwSpace.x3,
            ),
            child: SizedBox(
              key: const Key('list-detail-pane'),
              width: kAwDetailPaneWidth,
              // Content, not chrome (G1): a solid surface with a hairline, the
              // same radius as the rail's panel on the other side.
              child: Material(
                color: scheme.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AwRadius.xl),
                  ),
                  side: BorderSide(color: scheme.outlineVariant),
                ),
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: KeyedSubtree(
                    key: ValueKey('list-detail-$selected'),
                    child: AwPaneCloser(
                      close: controller.close,
                      child: detailBuilder(context, selected, controller.close),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// What ↑/↓ walk: the current order of the list an item was opened from.
abstract interface class AwListOrderHandle {
  /// The ids in the order the list shows them; null once the list is gone.
  List<String>? get ids;

  /// Scrolls [id]'s row into view, when the row is built — to the bottom
  /// edge moving [forward], to the top one moving back.
  void reveal(String id, {required bool forward});

  /// ↑/↓ have brought [id] into the pane — the list's chance to do what a
  /// tap on its row would also do first (E35 polish P-09: the all-units
  /// list opens the request's own unit).
  void reached(String id);
}

/// Wraps a list whose rows open items in a pane: [ids] is the order the
/// rows are drawn in. A row passes [maybeOf] to the controller's `open`.
class AwListOrder extends StatefulWidget {
  const AwListOrder({
    super.key,
    required this.ids,
    required this.child,
    this.onReached,
  });

  final List<String> ids;
  final Widget child;

  /// Called with each item ↑/↓ open from this list; see
  /// [AwListOrderHandle.reached].
  final ValueChanged<String>? onReached;

  static AwListOrderHandle? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_AwListOrderInherited>()?.handle;

  /// The row [id] registers its context here so ↑/↓ can scroll it into view.
  static void registerRow(BuildContext context, String id) =>
      context
              .getInheritedWidgetOfExactType<_AwListOrderInherited>()
              ?.handle
              ._rows[id] =
          context;

  @override
  State<AwListOrder> createState() => _AwListOrderState();
}

class _AwListOrderState extends State<AwListOrder>
    implements AwListOrderHandle {
  final Map<String, BuildContext> _rows = {};

  @override
  List<String>? get ids => mounted ? widget.ids : null;

  @override
  void reveal(String id, {required bool forward}) {
    final row = _rows[id];
    if (row == null || !row.mounted) return;
    Scrollable.ensureVisible(
      row,
      alignmentPolicy: forward
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      duration: AwMotion.fast,
    );
  }

  @override
  void reached(String id) {
    if (mounted) widget.onReached?.call(id);
  }

  @override
  Widget build(BuildContext context) =>
      _AwListOrderInherited(handle: this, child: widget.child);
}

class _AwListOrderInherited extends InheritedWidget {
  const _AwListOrderInherited({required this.handle, required super.child});

  final _AwListOrderState handle;

  @override
  bool updateShouldNotify(_AwListOrderInherited old) => false;
}

/// How a page drawn inside an [AwListDetailPane] leaves it (OPH-410).
///
/// A screen that also lives as a page reaches its way out through
/// `awRouteLeading`; inside the pane that way out is the pane's close, never
/// a back button that would pop the list behind it. Every screen the pane
/// shows — a request's detail and the pages that stand in for it when the
/// device holds no copy — gets the same close without knowing it is in one.
class AwPaneCloser extends InheritedWidget {
  const AwPaneCloser({super.key, required this.close, required super.child});

  final VoidCallback close;

  static VoidCallback? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AwPaneCloser>()?.close;

  @override
  bool updateShouldNotify(AwPaneCloser old) => false;
}
