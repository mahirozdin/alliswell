import 'package:flutter/material.dart';

import '../../../i18n/i18n.dart';

/// Rapid-entry task bar (feedback round 2): submit clears the field
/// immediately and KEEPS focus, so type → Enter → type → Enter chains work
/// without touching the mouse. Saving happens in the background; failures
/// surface as a snackbar carrying the lost title.
class QuickAddBar extends StatefulWidget {
  const QuickAddBar({
    super.key,
    required this.hintText,
    required this.onAdd,
    this.autofocus = false,
    this.controller,
    this.focusNode,
  });

  final String hintText;
  final Future<void> Function(String title) onAdd;
  final bool autofocus;

  /// Hand these in when the bar can be DISPOSED while the user is still using
  /// it — on Home it scrolls with the list (OPH-172), and a sliver past the
  /// cache extent is destroyed, so the text and focus must outlive the widget.
  /// Owners dispose what they pass; Inbox passes nothing and keeps its own.
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  State<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<QuickAddBar> {
  TextEditingController? _ownController;
  FocusNode? _ownFocus;
  int _inFlight = 0;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void dispose() {
    // Only ever dispose what this widget created.
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;

    // Optimistic rapid entry: clear + refocus NOW, save in the background.
    _controller.clear();
    _focus.requestFocus();
    setState(() => _inFlight++);
    try {
      await widget.onAdd(title);
    } on Object catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('task.couldNotAdd'.tr(args: {'title': title})),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _inFlight--);
        // Some platforms drop focus when dialogs/snackbars appear — reclaim it.
        _focus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.add),
          suffixIcon: _inFlight > 0
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'task.addTask'.tr(),
                  onPressed: _submit,
                ),
        ),
      ),
    );
  }
}
