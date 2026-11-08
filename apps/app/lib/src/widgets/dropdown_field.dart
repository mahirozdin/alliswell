import 'package:flutter/material.dart';

import 'popup_menu.dart';

/// The app's dropdown field (OPH-398 polish 3 D-4, DESIGN §5 barrier rule).
///
/// It takes what `DropdownButtonFormField` took here — [DropdownMenuItem]
/// entries, an [initialValue], a [decoration], [onChanged] — and looks like
/// it: the field's label and value with ⌄, a list that opens over the field
/// at the field's width. The list is [showAwMenu]'s route, not Material's
/// dropdown route: Material's barrier ("Dismiss menu" to a screen reader)
/// spans the whole screen, so its centre — where VoiceOver draws the focus
/// and an accessibility tap lands — lay on the open list and picked the item
/// there. Here the barrier's node is the free strip beside the list; touch
/// still closes on any tap outside it.
///
/// Like `DropdownButtonFormField` it keeps its own value after the first
/// build and takes a new [initialValue] when the parent passes one. A `null`
/// item value is a real choice ("none"), never a cancel.
class AwDropdownField<T> extends StatefulWidget {
  const AwDropdownField({
    super.key,
    required this.items,
    required this.onChanged,
    this.initialValue,
    this.decoration,
    this.hint,
    this.isExpanded = false,
  });

  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final T? initialValue;
  final InputDecoration? decoration;
  final Widget? hint;

  /// Kept for parity with Material's API; the field always fills its width.
  final bool isExpanded;

  @override
  State<AwDropdownField<T>> createState() => _AwDropdownFieldState<T>();
}

class _AwDropdownFieldState<T> extends State<AwDropdownField<T>> {
  late T? _value = widget.initialValue;
  bool _open = false;
  bool _focused = false;

  @override
  void didUpdateWidget(AwDropdownField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _value = widget.initialValue;
    }
  }

  List<DropdownMenuItem<T>> get _items => widget.items ?? const [];

  bool get _enabled => widget.onChanged != null && _items.isNotEmpty;

  Future<void> _show() async {
    setState(() => _open = true);
    final picked = await showAwDropdownMenu<T>(
      context: context,
      items: _items,
      value: _value,
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (picked == null) return;
    setState(() => _value = picked.value);
    widget.onChanged?.call(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _items.where((i) => i.value == _value).firstOrNull;
    final showHint = selected == null && widget.hint != null;
    final decoration = (widget.decoration ?? const InputDecoration())
        .applyDefaults(theme.inputDecorationTheme)
        .copyWith(
          enabled: _enabled,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        );
    final style = theme.textTheme.titleMedium!.copyWith(
      color: _enabled ? null : theme.disabledColor,
    );
    return Semantics(
      button: true,
      expanded: _open,
      enabled: _enabled,
      child: InkWell(
        onTap: _enabled ? _show : null,
        onFocusChange: (f) => setState(() => _focused = f),
        canRequestFocus: _enabled,
        child: InputDecorator(
          decoration: decoration,
          isEmpty: selected == null && !showHint,
          isFocused: _focused || _open,
          child: DefaultTextStyle(
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: selected?.child ?? widget.hint ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// A controlled, bare dropdown (`DropdownButton`'s place, D-4): the current
/// item's child with ⌄, underlined unless under a
/// [DropdownButtonHideUnderline]. Same list and barrier as [AwDropdownField].
class AwDropdownButton<T> extends StatefulWidget {
  const AwDropdownButton({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.hint,
    this.isExpanded = false,
  });

  final List<DropdownMenuItem<T>>? items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final Widget? hint;
  final bool isExpanded;

  @override
  State<AwDropdownButton<T>> createState() => _AwDropdownButtonState<T>();
}

class _AwDropdownButtonState<T> extends State<AwDropdownButton<T>> {
  bool _open = false;

  List<DropdownMenuItem<T>> get _items => widget.items ?? const [];

  bool get _enabled => widget.onChanged != null && _items.isNotEmpty;

  Future<void> _show() async {
    setState(() => _open = true);
    final picked = await showAwDropdownMenu<T>(
      context: context,
      items: _items,
      value: widget.value,
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (picked != null) widget.onChanged?.call(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final index = _items.indexWhere((i) => i.value == widget.value);
    final color = _enabled ? null : theme.disabledColor;
    // Every item laid out, the current one shown: the button is as wide as
    // its widest item and does not jump when the value changes (Material's
    // IndexedStack, kept).
    final Widget current = IndexedStack(
      index: index >= 0 ? index : _items.length,
      alignment: AlignmentDirectional.centerStart,
      children: [
        for (final item in _items) item.child,
        widget.hint ?? const SizedBox.shrink(),
      ],
    );
    final Widget row = Row(
      mainAxisSize: widget.isExpanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (widget.isExpanded) Expanded(child: current) else current,
        Icon(Icons.arrow_drop_down, color: color),
      ],
    );
    final underline = !DropdownButtonHideUnderline.at(context);
    return Semantics(
      button: true,
      expanded: _open,
      enabled: _enabled,
      child: InkWell(
        onTap: _enabled ? _show : null,
        canRequestFocus: _enabled,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: kMinInteractiveDimension,
          ),
          child: DecoratedBox(
            decoration: underline
                ? BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: theme.colorScheme.outline),
                    ),
                  )
                : const BoxDecoration(),
            child: DefaultTextStyle(
              style: theme.textTheme.titleMedium!.copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: widget.isExpanded ? null : 1,
                child: row,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A picked entry: wraps the item's value so a `null` value ("none") is told
/// apart from closing the list without a choice.
class AwDropdownPick<T> {
  const AwDropdownPick(this.value);

  final T? value;
}

/// Opens [items] as a list over the widget at [context], at its width, the
/// current [value] checked, announced as selected and scrolled into view.
/// `null` when the list was closed without a choice.
Future<AwDropdownPick<T>?> showAwDropdownMenu<T>({
  required BuildContext context,
  required List<DropdownMenuItem<T>> items,
  required T? value,
}) {
  final box = context.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final rect = Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
  final scheme = Theme.of(context).colorScheme;
  return showAwMenu<AwDropdownPick<T>>(
    context: context,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    width: rect.width,
    items: [
      for (final item in items)
        PopupMenuItem<AwDropdownPick<T>>(
          value: AwDropdownPick<T>(item.value),
          enabled: item.enabled,
          onTap: item.onTap,
          child: _DropdownEntry(
            selected: item.value == value,
            check: scheme.primary,
            child: item,
          ),
        ),
    ],
  );
}

class _DropdownEntry extends StatefulWidget {
  const _DropdownEntry({
    required this.selected,
    required this.check,
    required this.child,
  });

  final bool selected;
  final Color check;
  final Widget child;

  @override
  State<_DropdownEntry> createState() => _DropdownEntryState();
}

class _DropdownEntryState extends State<_DropdownEntry> {
  @override
  void initState() {
    super.initState();
    if (widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Scrollable.ensureVisible(context, alignment: 0.5);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    selected: widget.selected,
    child: Row(
      children: [
        Expanded(child: widget.child),
        if (widget.selected)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: Icon(Icons.check, size: 20, color: widget.check),
          ),
      ],
    ),
  );
}
