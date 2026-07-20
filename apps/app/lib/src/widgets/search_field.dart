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
