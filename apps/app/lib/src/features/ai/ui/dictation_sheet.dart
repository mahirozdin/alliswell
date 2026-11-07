import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_format.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/sheets.dart';
import '../../tasks/data/quick_add_apply.dart';
import '../../tasks/ui/quick_add_bar.dart';
import '../../tasks/ui/quick_add_text_controller.dart';
import '../data/ai_models.dart';
import '../data/stt.dart';

/// Dictation without an AI provider (OPH-402, U-07, U-14; DESIGN §48).
///
/// With AI on and no provider connected, the chat cannot answer, so the
/// microphone stops leading there. It dictates on the device instead and puts
/// the words into a quick-add field — the Inbox bar's own field, parse and
/// capture rule (ADR-0057 §3): dateless → Inbox, dated → an open task. Nothing
/// is saved before the user taps ↑ on the editable text (the AI9 spirit).

/// Whether the microphone dictates instead of opening the chat: AI is on for
/// the server and no provider is connected. An unknown status (still loading)
/// keeps today's path — the bubble re-reads the status itself.
bool aiDictationMode(AiStatus? status) =>
    status != null && status.enabled && !status.configured;

enum DictationPhase {
  /// The engine is starting — on a first use, the OS permission prompt is up.
  permission,
  listening,

  /// The words are in the quick-add field (or the mic is unavailable here).
  editing,

  /// Cancelled (the sheet's Cancel, or the FAB's cancel action).
  cancelled,
}

class DictationState {
  const DictationState({
    this.phase = DictationPhase.permission,
    this.partial = '',
    this.text = '',
    this.unavailable = false,
  });
  final DictationPhase phase;
  final String partial;
  final String text;

  /// No recognizer or no permission: the sheet is a plain quick add.
  final bool unavailable;

  DictationState copyWith({
    DictationPhase? phase,
    String? partial,
    String? text,
    bool? unavailable,
  }) => DictationState(
    phase: phase ?? this.phase,
    partial: partial ?? this.partial,
    text: text ?? this.text,
    unavailable: unavailable ?? this.unavailable,
  );
}

final dictationControllerProvider =
    NotifierProvider<DictationController, DictationState>(
      DictationController.new,
    );

/// One dictation session over the STT seam. The sheet starts it and its
/// Cancel ends it; the FAB routes AI2's cancel action here too.
class DictationController extends Notifier<DictationState> {
  SttController? _stt;

  /// Bumped by every start/cancel, so a callback from an older session is
  /// ignored.
  int _session = 0;

  @override
  DictationState build() {
    ref.onDispose(() => _stt?.cancel());
    return const DictationState();
  }

  Future<void> start() async {
    final session = ++_session;
    final stt = ref.read(sttProvider);
    if (stt == null) {
      state = const DictationState(
        phase: DictationPhase.editing,
        unavailable: true,
      );
      return;
    }
    _stt = stt;
    state = const DictationState();
    final init = await stt.initialize();
    if (!ref.mounted || session != _session) return;
    if (!init.available) {
      _stt = null;
      state = const DictationState(
        phase: DictationPhase.editing,
        unavailable: true,
      );
      return;
    }
    state = state.copyWith(phase: DictationPhase.listening);
    await stt.start(
      localeId: AwI18n.instance.locale.languageCode == 'tr' ? 'tr_TR' : 'en_US',
      onResult: (text, isFinal) {
        if (session != _session || state.phase != DictationPhase.listening) {
          return;
        }
        if (isFinal) {
          _finish(text);
        } else {
          state = state.copyWith(partial: text);
        }
      },
    );
  }

  /// "Bitir": the final result normally arrives through `onResult`; a stop
  /// that yields none keeps the live partial, so nothing said is lost.
  Future<void> finish() async {
    await _stt?.stop();
    if (!ref.mounted) return;
    if (state.phase == DictationPhase.listening) _finish(state.partial);
  }

  Future<void> cancel() async {
    if (!ref.mounted) return;
    _session++;
    final stt = _stt;
    _stt = null;
    state = state.copyWith(phase: DictationPhase.cancelled);
    await stt?.cancel();
  }

  void _finish(String text) {
    _stt = null;
    state = state.copyWith(
      phase: DictationPhase.editing,
      text: text.trim(),
      partial: '',
    );
  }
}

/// Opens the dictation sheet on the root navigator (above the shell's bar).
Future<void> showDictationSheet(BuildContext context) => showAwSheet<void>(
  context,
  showDragHandle: true,
  builder: (_) => const DictationSheet(),
);

class DictationSheet extends ConsumerStatefulWidget {
  const DictationSheet({super.key});
  @override
  ConsumerState<DictationSheet> createState() => _DictationSheetState();
}

class _DictationSheetState extends ConsumerState<DictationSheet> {
  final _text = QuickAddTextController();
  final _focus = FocusNode();
  bool _closing = false;
  late final DictationController _controller = ref.read(
    dictationControllerProvider.notifier,
  );
  DictationPhase _phase = DictationPhase.permission;

  @override
  void initState() {
    super.initState();
    _controller; // bound while `ref` is usable
    // After the first frame: a provider may not change during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.start();
    });
  }

  @override
  void dispose() {
    // Swiped down mid-sentence: the recognizer must not keep listening.
    // Not during the unmount itself: a provider may not change then.
    if (!_closing && _phase != DictationPhase.editing) {
      final controller = _controller;
      Future.microtask(controller.cancel);
    }
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  Future<void> _add(QuickAddSubmission submission) async {
    final messenger = ScaffoldMessenger.of(context);
    final id = await createCapture(ref.read, submission);
    if (id == null) throw StateError('No workspace available');
    final parse = submission.parse;
    final due = parse.dueAt;
    final message = due == null
        ? 'capture.addedInbox'.tr(args: {'title': parse.title})
        : 'capture.added'.tr(
            args: {
              'title': parse.title,
              'due': awFormatShort(due, format: ref.read(dateFormatProvider)),
            },
          );
    if (mounted) _close();
    messenger.showSnackBar(
      SnackBar(key: Key('dictation-added-$id'), content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(dictationControllerProvider, (previous, next) {
      if (next.phase == DictationPhase.cancelled) {
        _closing = true;
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (next.phase == DictationPhase.editing &&
          previous?.phase != DictationPhase.editing) {
        _text.value = TextEditingValue(
          text: next.text,
          selection: TextSelection.collapsed(offset: next.text.length),
        );
        _focus.requestFocus();
      }
    });
    final state = ref.watch(dictationControllerProvider);
    _phase = state.phase;
    return Padding(
      key: const Key('dictation-sheet'),
      padding: EdgeInsets.only(
        left: AwSpace.x4,
        right: AwSpace.x4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AwSpace.x4,
      ),
      child: AnimatedSize(
        duration: AwMotion.fast,
        alignment: Alignment.topCenter,
        child: switch (state.phase) {
          DictationPhase.permission => _status(
            context,
            text: 'ai.voice.waitingPermission'.tr(),
          ),
          DictationPhase.listening => _listening(context, state),
          DictationPhase.editing ||
          DictationPhase.cancelled => _editing(context, state),
        },
      ),
    );
  }

  Widget _cancelButton() => TextButton.icon(
    key: const Key('dictation-cancel'),
    onPressed: _controller.cancel,
    icon: const Icon(Icons.close),
    label: Text('ai.voice.cancel'.tr()),
  );

  /// A-66: while the OS asks for the microphone, the sheet says so — it used
  /// to read "Listening…" behind a prompt nobody had answered (U-14).
  Widget _status(BuildContext context, {required String text}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Row(
            children: [
              Icon(Icons.mic_none_outlined, color: scheme.onSurfaceVariant),
              const SizedBox(width: AwSpace.x2),
              Expanded(
                child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
              ),
            ],
          ),
        ),
        const SizedBox(height: AwSpace.x3),
        Align(alignment: Alignment.centerLeft, child: _cancelButton()),
      ],
    );
  }

  Widget _listening(BuildContext context, DictationState state) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          header: true,
          child: Row(
            children: [
              Icon(Icons.mic, color: scheme.primary),
              const SizedBox(width: AwSpace.x2),
              Expanded(
                child: Text(
                  'ai.voice.dictateTitle'.tr(),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AwSpace.x3),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 30),
          child: Text(
            state.partial,
            key: const Key('dictation-partial'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(height: AwSpace.x3),
        Row(
          children: [
            _cancelButton(),
            const Spacer(),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filled(
                  key: const Key('dictation-done'),
                  icon: const Icon(Icons.stop),
                  tooltip: 'ai.voice.done'.tr(),
                  onPressed: _controller.finish,
                ),
                ExcludeSemantics(
                  child: Text(
                    'ai.voice.done'.tr(),
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _editing(BuildContext context, DictationState state) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.unavailable) ...[
          Text(
            'ai.voice.denied'.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AwSpace.x2),
        ],
        QuickAddBar(
          key: const Key('dictation-field'),
          hintText: 'ai.bubble.hintUnconfigured'.tr(),
          controller: _text,
          focusNode: _focus,
          autofocus: true,
          onAdd: _add,
        ),
      ],
    );
  }
}
