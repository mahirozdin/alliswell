import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';
import '../../../core/quick_parse.dart';
import '../../../core/recurrence_text.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../theme/typography.dart';
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
///
/// OPH-401 (C-06, R-11, DESIGN §47 Q1–Q5): empty, the bar is a field and its
/// hint — no "+" glyph (the FAB's sign on something that is not a button) and
/// nothing on the right that would do nothing. Text brings ✨ (with AI) and the
/// ↑, a 32 pt filled circle. Focus brings a one-line strip of examples under
/// the field, ending in "More" (the syntax sheet); typing replaces it with the
/// recognized chips.
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

  /// Dismissed recognitions ([AwQuickToken.key]); cleared on submit and
  /// whenever the field becomes empty — a ✕ belongs to the line it was
  /// pressed on, not to the next one typed after clearing by hand (OPH-385).
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
    _focus.addListener(_onFocus);
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
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.removeListener(_onText);
    _focus.removeListener(_onFocus);
    // Only ever dispose what this widget created.
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onText() {
    if (_controller.text == _parsedText) return;
    if (_controller.text.isEmpty) _ignored.clear();
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
    final hasText = _controller.text.trim().isNotEmpty;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final Widget? suffix = _inFlight > 0
        ? const Padding(
            padding: EdgeInsets.all(AwSpace.x3),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : hasText
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onParse != null)
                _PopIn(
                  reduce: reduce,
                  child: IconButton(
                    key: const Key('quick-add-parse'),
                    icon: const Icon(Icons.auto_awesome_outlined),
                    tooltip: 'ai.confirm.parse'.tr(),
                    onPressed: _parse,
                  ),
                ),
              _PopIn(
                reduce: reduce,
                child: _SubmitButton(onPressed: _submit),
              ),
            ],
          )
        : null;

    // What sits under the field: the recognized chips while there is text,
    // the examples strip while the empty field has focus, else nothing.
    final Widget below = chips.isNotEmpty && parse != null
        ? Padding(
            padding: const EdgeInsets.only(top: AwSpace.x2),
            child: _TokenChips(
              parse: parse,
              chips: chips,
              onDismiss: _dismiss,
              onHelp: _openHelp,
            ),
          )
        : !hasText && _focus.hasFocus
        ? Padding(
            padding: const EdgeInsets.only(top: AwSpace.x1),
            child: _HintStrip(
              showProject: widget.parseProject,
              onMore: _openHelp,
            ),
          )
        : const SizedBox(width: double.infinity);

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
              suffixIcon: suffix,
            ),
          ),
          AnimatedSize(
            duration: reduce ? Duration.zero : AwMotion.base,
            curve: AwMotion.enter,
            alignment: Alignment.topCenter,
            child: below,
          ),
        ],
      ),
    );
  }
}

/// ✨ and ↑ arrive scaled in over 150 ms (DESIGN §47 Q2) — at once with
/// reduced motion.
class _PopIn extends StatelessWidget {
  const _PopIn({required this.reduce, required this.child});

  final bool reduce;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: reduce ? 1 : 0.6, end: 1),
    duration: reduce ? Duration.zero : AwMotion.fast,
    curve: AwMotion.enter,
    builder: (context, t, child) => Transform.scale(scale: t, child: child),
    child: child,
  );
}

/// The send button: a 32 pt `primary` circle with ↑ inside a 48 pt target —
/// the one filled control in the bar, so the primary action reads as one.
class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'task.addTask'.tr(),
      child: Semantics(
        button: true,
        label: 'task.addTask'.tr(),
        excludeSemantics: true,
        child: InkResponse(
          key: const Key('quick-add-submit'),
          onTap: onPressed,
          radius: 24,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                key: const Key('quick-add-submit-dot'),
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                ),
                child: Icon(
                  Icons.arrow_upward,
                  size: 20,
                  color: scheme.onPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The examples under a focused, empty bar (DESIGN §47 Q3): one line of
/// what the bar understands, ending in "More" — the syntax sheet. The examples
/// are print, not buttons: there is nothing to do with "#home" but read it.
class _HintStrip extends StatelessWidget {
  const _HintStrip({required this.showProject, required this.onMore});

  /// Off where `+Project` stays text (a project's own Tasks tab).
  final bool showProject;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final examples = [
      for (final example in 'task.quickParse.hintChips'.tr().split(' · '))
        if (showProject || !example.startsWith('+')) example,
    ];
    return Row(
      key: const Key('quick-add-hints'),
      children: [
        Expanded(
          child: Semantics(
            label:
                '${'task.quickParse.hintsLabel'.tr()}: ${examples.join(', ')}',
            excludeSemantics: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final example in examples)
                    Padding(
                      padding: const EdgeInsets.only(right: AwSpace.x2),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AwRadius.s),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AwSpace.x2,
                            vertical: AwSpace.x1,
                          ),
                          child: Text(
                            example,
                            style: context.awText.meta.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        TextButton(
          key: const Key('quick-add-help'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: onMore,
          child: Text('task.quickParse.more'.tr()),
        ),
      ],
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
