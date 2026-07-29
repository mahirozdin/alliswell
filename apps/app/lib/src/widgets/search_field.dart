import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../theme/tokens.dart';

/// The one search field (DESIGN §12 S1): body-level, `search` prefix, clear
/// suffix, debounced ~250 ms. Screens own their query state; this widget owns
/// only the text and the debounce.
class AwSearchField extends StatefulWidget {
  const AwSearchField({
    super.key,
    required this.onQuery,
    this.hintText,
    this.debounce = const Duration(milliseconds: 250),
  });

  final ValueChanged<String> onQuery;
  final String? hintText;
  final Duration debounce;

  @override
  State<AwSearchField> createState() => _AwSearchFieldState();
}

class _AwSearchFieldState extends State<AwSearchField> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {}); // clear-button visibility
    _debounce?.cancel();
    _debounce = Timer(widget.debounce, () => widget.onQuery(value));
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {});
    widget.onQuery(''); // instant — clearing restores the list (S5)
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: _onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hintText ?? 'common.search'.tr(),
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                key: const Key('search-clear'),
                tooltip: 'common.clear'.tr(),
                icon: const Icon(Icons.close, size: 18),
                onPressed: _clear,
              ),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AwRadius.m),
          borderSide: BorderSide.none,
        ),
        filled: true,
      ),
    );
  }
}

/// The same search, as an app-bar ACTION (feedback round 13 #5).
///
/// A pinned search row cost every screen a line above its own content, on the
/// phone where lines are scarcest — the same complaint that moved Home's view
/// controls into the app bar (DESIGN §16 H1). So the field lives in the bar
/// now: an icon until you want it, an input when you do.
///
/// The widget owns its open state, its controller and its focus node, which is
/// what lets a screen adopt it by deleting a row and adding one action — and
/// keeps the round-11 controller-disposal bug out of reach (§25 R5).
///
/// Closing CLEARS the query: leaving a filter applied behind a collapsed icon
/// is the "invisible filter" §16 already refuses for the calendar's selected
/// day.
class AwSearchAction extends StatefulWidget {
  const AwSearchAction({
    super.key,
    required this.onQuery,
    this.hintText,
    this.fieldKey,
    this.debounce = const Duration(milliseconds: 250),
  });

  final ValueChanged<String> onQuery;
  final String? hintText;

  /// Key for the expanded input, so tests can type into it.
  final Key? fieldKey;
  final Duration debounce;

  @override
  State<AwSearchAction> createState() => _AwSearchActionState();
}

class _AwSearchActionState extends State<AwSearchAction> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  bool _open = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _emit(String value) {
    _debounce?.cancel();
    _debounce = Timer(widget.debounce, () => widget.onQuery(value.trim()));
  }

  void _close() {
    _debounce?.cancel();
    _controller.clear();
    widget.onQuery('');
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return IconButton(
        key: const Key('search-open'),
        tooltip: 'common.search'.tr(),
        icon: const Icon(Icons.search),
        onPressed: () {
          setState(() => _open = true);
          // The field is built this frame; focus it on the next one.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _focus.requestFocus(),
          );
        },
      );
    }

    // Wide enough to type in, never wider than the bar can spare — the title
    // and the other actions keep their place instead of being pushed off.
    final width = (MediaQuery.sizeOf(context).width - 220).clamp(140.0, 280.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          child: TextField(
            key: widget.fieldKey ?? const Key('search-field'),
            controller: _controller,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: widget.hintText,
            ),
            onChanged: _emit,
          ),
        ),
        IconButton(
          key: const Key('search-close'),
          tooltip: 'common.cancel'.tr(),
          icon: const Icon(Icons.close),
          onPressed: _close,
        ),
      ],
    );
  }
}
