import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/color_swatch_dot.dart';
import '../../projects/data/project.dart';
import '../../projects/ui/project_edit_sheet.dart' show kProjectPalette;
import '../data/quick_link.dart';
import '../emoji_input.dart';
import '../providers.dart';

/// The user's recent emoji — device-local, comma-joined.
final quickEmojiRecentsProvider = NotifierProvider<PersistedChoice, String>(
  () => PersistedChoice('alliswell_quick_emoji_recents', fallback: ''),
);

/// Emoji picker (OPH-202, DESIGN §23 Q7): recents, a curated grid, and a free
/// field for everything else — the system keyboard's emoji page is the real
/// picker, so the field is the path that matters on phones AND on desktop.
Future<void> showQuickEmojiSheet(
  BuildContext context,
  WidgetRef ref,
  QuickAccessRow row,
) {
  return showModalBottomSheet<void>(
    context: context,
    // OPH-212: the ROOT navigator. Pushed into a shell branch, a sheet
    // renders UNDER the shell's own glass bar and FAB — they are painted by
    // the Scaffold that owns the branch, above its body.
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (sheetContext) => _EmojiSheet(row: row),
  );
}

class _EmojiSheet extends ConsumerStatefulWidget {
  const _EmojiSheet({required this.row});

  final QuickAccessRow row;

  @override
  ConsumerState<_EmojiSheet> createState() => _EmojiSheetState();
}

class _EmojiSheetState extends ConsumerState<_EmojiSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply(String? emoji) async {
    await ref.read(quickAccessStoreProvider).setEmoji(widget.row.id, emoji);
    if (emoji != null) {
      final recents = pushEmojiRecent(
        parseEmojiRecents(ref.read(quickEmojiRecentsProvider)),
        emoji,
      );
      await ref
          .read(quickEmojiRecentsProvider.notifier)
          .set(encodeEmojiRecents(recents));
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  void _submitTyped() {
    final emoji = normalizeEmojiInput(_controller.text);
    if (emoji == null) {
      setState(() => _error = 'quick.invalidEmoji'.tr());
      return;
    }
    _apply(emoji);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recents = parseEmojiRecents(ref.watch(quickEmojiRecentsProvider));
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AwSpace.x4,
          0,
          AwSpace.x4,
          AwSpace.x4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('quick.emoji'.tr(), style: theme.textTheme.titleMedium),
            if (recents.isNotEmpty) ...[
              const SizedBox(height: AwSpace.x3),
              Text(
                'quick.emojiRecents'.tr(),
                style: theme.textTheme.labelMedium,
              ),
              _EmojiWrap(emojis: recents, onPick: _apply),
            ],
            const SizedBox(height: AwSpace.x3),
            _EmojiWrap(emojis: kQuickEmojiGrid, onPick: _apply),
            const SizedBox(height: AwSpace.x3),
            TextField(
              key: const Key('quick-emoji-field'),
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'quick.emojiCustom'.tr(),
                errorText: _error,
                suffixIcon: IconButton(
                  key: const Key('quick-emoji-submit'),
                  icon: const Icon(Icons.check),
                  onPressed: _submitTyped,
                ),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submitTyped(),
            ),
            const SizedBox(height: AwSpace.x2),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: const Key('quick-emoji-clear'),
                onPressed: () => _apply(null),
                icon: const Icon(Icons.backspace_outlined),
                // Removing the emoji returns the row to its kind icon — the
                // identity slot is never empty (DESIGN §23 Q3).
                label: Text('common.remove'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiWrap extends StatelessWidget {
  const _EmojiWrap({required this.emojis, required this.onPick});

  final List<String> emojis;
  final void Function(String emoji) onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AwSpace.x2,
      runSpacing: AwSpace.x2,
      children: [
        for (final emoji in emojis)
          InkWell(
            key: Key('quick-emoji-$emoji'),
            onTap: () => onPick(emoji),
            customBorder: const CircleBorder(),
            child: SizedBox(
              // ≥44 px, like every other tap target (DESIGN G4).
              width: 44,
              height: 44,
              child: Center(
                child: Text(
                  emoji,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Colour picker: the project palette, reused verbatim, plus "no colour".
///
/// Deliberately NOT the unbounded grid the project sheet also offers — DESIGN
/// §23 Q8a bounds the shortcut dot to ten known colours so the ring keeps its
/// contrast promise; the wider set is in the parking lot with that reason.
Future<void> showQuickColorSheet(
  BuildContext context,
  WidgetRef ref,
  QuickAccessRow row,
) {
  return showModalBottomSheet<void>(
    context: context,
    // OPH-212: the ROOT navigator. Pushed into a shell branch, a sheet
    // renders UNDER the shell's own glass bar and FAB — they are painted by
    // the Scaffold that owns the branch, above its body.
    useRootNavigator: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (sheetContext) => Consumer(
      builder: (context, sheetRef, _) {
        final theme = Theme.of(context);
        Future<void> pick(String? color) async {
          await sheetRef.read(quickAccessStoreProvider).setColor(row.id, color);
          if (context.mounted) Navigator.of(context).maybePop();
        }

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AwSpace.x4,
              0,
              AwSpace.x4,
              AwSpace.x6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('quick.color'.tr(), style: theme.textTheme.titleMedium),
                const SizedBox(height: AwSpace.x3),
                Wrap(
                  spacing: AwSpace.x2,
                  runSpacing: AwSpace.x2,
                  children: [
                    for (final hex in kProjectPalette)
                      AwColorSwatchDot(
                        key: Key('quick-color-$hex'),
                        color: colorFromRgbHex(hex),
                        selected: row.link.colorRgb == hex,
                        onTap: () => pick(hex),
                      ),
                  ],
                ),
                const SizedBox(height: AwSpace.x2),
                TextButton.icon(
                  key: const Key('quick-color-clear'),
                  onPressed: () => pick(null),
                  icon: const Icon(Icons.format_color_reset_outlined),
                  label: Text('quick.noColor'.tr()),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
