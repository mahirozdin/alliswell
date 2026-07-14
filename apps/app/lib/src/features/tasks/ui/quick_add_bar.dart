import 'package:flutter/material.dart';

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
  });

  final String hintText;
  final Future<void> Function(String title) onAdd;
  final bool autofocus;

  @override
  State<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<QuickAddBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  int _inFlight = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
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
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not add "$title": $e')));
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
                  icon: const Icon(Icons.send),
                  tooltip: 'Add task',
                  onPressed: _submit,
                ),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}
