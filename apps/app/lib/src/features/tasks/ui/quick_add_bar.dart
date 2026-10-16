import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';
import '../../../core/quick_parse.dart';
import '../../../core/recurrence_text.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../projects/providers.dart';
import '../data/quick_add_apply.dart';
import 'quick_add_help_sheet.dart';
import 'quick_add_text_controller.dart';
import 'task_visuals.dart';

/// Rapid-entry task bar (feedback round 2): submit clears the field
/// immediately and KEEPS focus, so type → Enter → type → Enter chains work
/// without touching the mouse. Saving happens in the background; failures
/// surface as a snackbar carrying the lost title.
///
/// OPH-373 (DESIGN §39): the bar reads what you type, offline, in Turkish and
/// English (`core/quick_parse.dart`). Recognized words are highlighted and
/// listed as chips under the field; a chip's ✕ keeps its words as plain
/// title text. The ? opens the syntax sheet.
class QuickAddBar extends ConsumerStatefulWidget {
  const QuickAddBar({
    super.key,
    required this.hintText,
    required this.onAdd,
    this.autofocus = false,
    this.controller,
    this.focusNode,
    this.onParse,
    this.parseProject = true,
  });

  final String hintText;

  /// Receives the raw text and the parse the user saw (after dismissals).
  final Future<void> Function(QuickAddSubmission submission) onAdd;
  final bool autofocus;

  /// OPH-222: when provided (AI configured), a "✨ parse" affordance sends the
  /// typed text through the extraction endpoint into the same confirm card —
  /// no new UX invented. Absent → the bar is exactly as it was. It gets the
  /// RAW text: the offline parse is not applied on that path.
  final Future<void> Function(String text)? onParse;

  /// Off where the project is fixed (the project's own Tasks tab): `+Name`
  /// then stays text.
  final bool parseProject;

  /// Hand these in when the bar can be DISPOSED while the user is still using
  /// it — on Home it scrolls with the list (OPH-172), and a sliver past the
  /// cache extent is destroyed, so the text and focus must outlive the widget.
  /// Owners dispose what they pass; Inbox passes nothing and keeps its own.
  /// A [QuickAddTextController] also gets the recognized words highlighted.
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  TextEditingController? _ownController;
  FocusNode? _ownFocus;
  int _inFlight = 0;

  /// Dismissed recognitions ([AwQuickToken.key]); cleared on submit.
  final Set<String> _ignored = {};
  AwQuickParse? _parsed;
  String? _parsedText;
  bool _disposed = false;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= QuickAddTextController());
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onText);
    if (widget.parseProject) {
      // Keeps the project list alive and re-reads `+Name` when it changes.
      ref.listenManual(projectsControllerProvider, (_, _) => _reparse());
    }
    _reparse(notify: false);
  }

  @override
  void didUpdateWidget(QuickAddBar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _ownController)?.removeListener(_onText);
      _controller.addListener(_onText);
      _reparse(notify: false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.removeListener(_onText);
    // Only ever dispose what this widget created.
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onText() {
    if (_controller.text == _parsedText) return;
    _reparse();
  }

  AwQuickParse _parseNow(String text) => awParseQuickAdd(
    text,
    quickParseOptions(
      ref.read,
      parseProject: widget.parseProject,
      ignored: {..._ignored},
    ),
  );

  void _reparse({bool notify = true}) {
    if (_disposed) return;
    final text = _controller.text;
    final parse = _parseNow(text);
    _parsedText = text;
    final controller = _controller;
    if (controller is QuickAddTextController) {
      controller.recognized = [
        for (final t in parse.tokens) TextRange(start: t.start, end: t.end),
      ];
    }
    if (notify && mounted) {
      setState(() => _parsed = parse);
    } else {
      _parsed = parse;
    }
  }

  void _dismiss(AwQuickChip chip) {
    _ignored.addAll(chip.keys);
    _reparse();
  }

  Future<void> _submit() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;
    final parse = _parseNow(raw);

    // Optimistic rapid entry: clear + refocus NOW, save in the background.
    _ignored.clear();
    _controller.clear();
    _focus.requestFocus();
    setState(() => _inFlight++);
    try {
      await widget.onAdd(QuickAddSubmission(raw: raw, parse: parse));
    } on Object catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('task.couldNotAdd'.tr(args: {'title': raw}))),
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

  Future<void> _parse() async {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.onParse == null) return;

    // Round 14: the ✨ tap answers INSTANTLY — same optimistic rhythm as
    // _submit. The field clears, the spinner shows for the brief local
    // create, and the task row (with its AI badge) is the real feedback.
    _ignored.clear();
    _controller.clear();
    _focus.requestFocus();
    setState(() => _inFlight++);
    try {
      await widget.onParse!(text);
    } on Object catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('task.couldNotAdd'.tr(args: {'title': text}))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _inFlight--);
        _focus.requestFocus();
      }
    }
  }

  void _openHelp() {
    showModalBottomSheet<void>(
      context: context,
      // Above the glass bottom bar (LESSONS flutter-app, HomeShell extendBody).
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const QuickAddHelpSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parse = _parsed;
    final chips = parse?.chips ?? const <AwQuickChip>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
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
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // §39 Q3: in the bar while it is empty; once you
                        // type, it moves to the end of the chips row so
                        // three icons never squeeze the text on a phone.
                        if (_controller.text.isEmpty)
                          IconButton(
                            key: const Key('quick-add-help'),
                            icon: const Icon(Icons.help_outline),
                            tooltip: 'task.quickParse.helpTooltip'.tr(),
                            onPressed: _openHelp,
                          ),
                        if (widget.onParse != null)
                          IconButton(
                            key: const Key('quick-add-parse'),
                            icon: const Icon(Icons.auto_awesome_outlined),
                            tooltip: 'ai.confirm.parse'.tr(),
                            onPressed: _parse,
                          ),
                        IconButton(
                          icon: const Icon(Icons.arrow_upward),
                          tooltip: 'task.addTask'.tr(),
                          onPressed: _submit,
                        ),
                      ],
                    ),
            ),
          ),
          AnimatedSize(
            duration: AwMotion.base,
            curve: AwMotion.enter,
            alignment: Alignment.topCenter,
            child: chips.isEmpty || parse == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: AwSpace.x2),
                    child: _TokenChips(
                      parse: parse,
                      chips: chips,
                      onDismiss: _dismiss,
                      onHelp: _openHelp,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The recognized pieces, one chip each (DESIGN §39 Q2) — the tag field's
/// chip style (`tag_input.dart`), an icon per kind.
class _TokenChips extends ConsumerWidget {
  const _TokenChips({
    required this.parse,
    required this.chips,
    required this.onDismiss,
    required this.onHelp,
  });

  final AwQuickParse parse;
  final List<AwQuickChip> chips;
  final void Function(AwQuickChip chip) onDismiss;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = ref.watch(dateFormatProvider);
    final scheme = Theme.of(context).colorScheme;
    String short(DateTime d, {bool withTime = false}) =>
        awFormatShort(d, format: format, withTime: withTime);
    var tagIndex = 0;
    final hasDueChip = chips.any((c) => c.kind == AwQuickTokenKind.due);
    final rule = parse.repeat == null
        ? ''
        : awRepeatSentence(
            parse.repeat!,
            dateFormat: format,
          ).split(' · ').first;
    final children = <Widget>[];
    for (final chip in chips) {
      final (IconData icon, String label, Color? tint) = switch (chip.kind) {
        AwQuickTokenKind.due => (
          Icons.event,
          'task.quickParse.due'.tr(
            args: {'date': short(parse.dueAt!, withTime: parse.dueHasTime)},
          ),
          null,
        ),
        AwQuickTokenKind.when => (
          Icons.wb_sunny_outlined,
          'task.quickParse.when'.tr(args: {'date': short(parse.whenDay!)}),
          null,
        ),
        AwQuickTokenKind.repeat => (
          Icons.repeat,
          // The rule without its end clause (typed rules never end); the
          // first date only when no deadline chip already shows it.
          hasDueChip
              ? rule
              : 'task.quickParse.repeat'.tr(
                  args: {
                    'rule': rule,
                    'date': short(parse.dueAt!, withTime: parse.dueHasTime),
                  },
                ),
          null,
        ),
        AwQuickTokenKind.tag => (
          Icons.sell_outlined,
          chip.tokens.first.text.replaceFirst(RegExp(r'[,;.!?:)\]]+$'), ''),
          null,
        ),
        AwQuickTokenKind.project => (
          Icons.folder_outlined,
          parse.project!.name,
          null,
        ),
        AwQuickTokenKind.priority => (
          Icons.flag_outlined,
          'task.quickParse.priority'.tr(
            args: {'label': 'task.priority.${parse.priority}'.tr()},
          ),
          taskPriorityColorOf(context, parse.priority!),
        ),
        AwQuickTokenKind.time => (Icons.schedule, '', null),
      };
      children.add(
        InputChip(
          key: chip.kind == AwQuickTokenKind.tag
              ? Key('quick-add-token-tag-${tagIndex++}')
              : Key('quick-add-token-${chip.kind.name}'),
          avatar: Icon(icon, size: 18, color: tint ?? scheme.onSurfaceVariant),
          label: Text(label),
          onDeleted: () => onDismiss(chip),
          deleteButtonTooltipMessage: 'task.quickParse.keepAsText'.tr(),
          materialTapTargetSize: MaterialTapTargetSize.padded,
        ),
      );
    }
    children.add(
      IconButton(
        key: const Key('quick-add-help-inline'),
        icon: Icon(Icons.help_outline, color: scheme.onSurfaceVariant),
        tooltip: 'task.quickParse.helpTooltip'.tr(),
        onPressed: onHelp,
      ),
    );
    return Wrap(
      spacing: AwSpace.x2,
      runSpacing: AwSpace.x1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}
