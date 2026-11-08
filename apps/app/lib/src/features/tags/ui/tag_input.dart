import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fold.dart';
import '../../../i18n/i18n.dart';
import '../../workspaces/workspaces.dart';
import '../tags.dart';

/// The tag chip-input (round 8, OPH-165 — DESIGN §13 T1…T4). Lives in the
/// task create sheet AND the task detail Tags card — one component, no
/// divergent tag UIs (T4).
///
/// Behavior contract:
/// - Tab / Enter / comma commits the typed text as a chip; the field clears
///   and keeps focus (serial entry, T1).
/// - Existing tags are suggested fold-insensitively while typing; if nothing
///   matches exactly, the first suggestion is an explicit "Create: #x" (T2) —
///   plain Enter takes it, so creation is frictionless but never invisible.
/// - '#' is presentation: chips render `#name`, a typed leading '#' is
///   swallowed on commit (T3).
class TagInputField extends ConsumerStatefulWidget {
  const TagInputField({
    super.key,
    required this.value,
    required this.onChanged,
    this.onManage,
    this.workspaceId,
    this.labelText,
  });

  /// OPH-403 (H-6, DESIGN §49 N5): set on a form, the field is the form's
  /// one G3 field — this label, the hint only once it floats, no leading
  /// "#" icon — so its text starts where the title's and description's do.
  /// Null keeps the compact icon-led field of the detail's Tags card.
  final String? labelText;

  /// Selected tag ids, order preserved.
  final List<String> value;
  final ValueChanged<List<String>> onChanged;

  /// When set, a small "manage tags" affordance renders next to the input.
  final VoidCallback? onManage;

  /// Whose tags: the TASK's workspace when the field edits an existing task
  /// (EE-296 — one opened from Home may live in a unit other than the one
  /// selected), or null for the workspace on screen, where a new task lands.
  final String? workspaceId;

  @override
  ConsumerState<TagInputField> createState() => _TagInputFieldState();
}

class _TagInputFieldState extends ConsumerState<TagInputField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _committing = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Leading '#' is swallowed — names are stored bare (T3).
  String _clean(String raw) {
    var text = raw.trim();
    while (text.startsWith('#')) {
      text = text.substring(1).trimLeft();
    }
    return text.trim();
  }

  Future<void> _commit(String raw, List<Tag> all) async {
    final text = _clean(raw);
    if (text.isEmpty || _committing) {
      _controller.clear();
      setState(() {});
      return;
    }
    _committing = true;
    try {
      final folded = foldSearchText(text);
      Tag? existing;
      for (final tag in all) {
        if (foldSearchText(tag.name) == folded) {
          existing = tag;
          break;
        }
      }
      String id;
      if (existing != null) {
        id = existing.id;
      } else {
        final workspaceId =
            widget.workspaceId ??
            await ref.read(activeWorkspaceIdProvider.future);
        if (workspaceId == null) return;
        id = await ref.read(tagStoreProvider).create(workspaceId, text);
      }
      if (!widget.value.contains(id)) {
        widget.onChanged([...widget.value, id]);
      }
      _controller.clear();
      if (mounted) {
        setState(() {});
        _focus.requestFocus(); // serial entry — type, Enter, type (T1)
      }
    } finally {
      _committing = false;
    }
  }

  void _select(Tag tag) {
    if (!widget.value.contains(tag.id)) {
      widget.onChanged([...widget.value, tag.id]);
    }
    _controller.clear();
    setState(() {});
    _focus.requestFocus();
  }

  void _remove(String id) {
    widget.onChanged([
      for (final v in widget.value)
        if (v != id) v,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final own = widget.workspaceId;
    final tags =
        ref
            .watch(own == null ? tagsProvider : workspaceTagsProvider(own))
            .value ??
        const <Tag>[];
    final byId = {for (final tag in tags) tag.id: tag};
    final selected = [
      for (final id in widget.value)
        if (byId[id] case final Tag tag) tag,
    ];
    final query = _clean(_controller.text);
    final foldedQuery = foldSearchText(query);
    final matches = query.isEmpty
        ? const <Tag>[]
        : [
            for (final tag in tags)
              if (!widget.value.contains(tag.id) &&
                  foldSearchText(tag.name).contains(foldedQuery))
                tag,
          ];
    final exactExists =
        query.isNotEmpty &&
        tags.any((tag) => foldSearchText(tag.name) == foldedQuery);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selected.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in selected)
                InputChip(
                  key: Key('tag-chip-${tag.id}'),
                  avatar: CircleAvatar(backgroundColor: tag.color, radius: 5),
                  label: Text('#${tag.name}'),
                  onDeleted: () => _remove(tag.id),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: Focus(
                onKeyEvent: (node, event) {
                  // Tab commits instead of traversing — but only when there
                  // is text to commit; an empty field lets Tab move on.
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.tab &&
                      _clean(_controller.text).isNotEmpty) {
                    _commit(_controller.text, tags);
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  key: const Key('tag-input'),
                  controller: _controller,
                  focusNode: _focus,
                  decoration: widget.labelText != null
                      ? InputDecoration(
                          labelText: widget.labelText,
                          hintText: 'tag.inputHint'.tr(),
                        )
                      : InputDecoration(
                          hintText: 'tag.inputHint'.tr(),
                          prefixIcon: const Icon(Icons.tag, size: 18),
                          isDense: true,
                        ),
                  onChanged: (value) {
                    // Comma commits mid-typing (mobile keyboards have no Tab).
                    if (value.endsWith(',')) {
                      _commit(value.substring(0, value.length - 1), tags);
                    } else {
                      setState(() {});
                    }
                  },
                  onSubmitted: (value) => _commit(value, tags),
                ),
              ),
            ),
            if (widget.onManage != null)
              IconButton(
                key: const Key('tag-manage'),
                tooltip: 'tag.manage'.tr(),
                icon: const Icon(Icons.tune, size: 20),
                onPressed: widget.onManage,
              ),
          ],
        ),
        if (query.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!exactExists)
                ActionChip(
                  key: const Key('tag-create-suggestion'),
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text('tag.createSuggestion'.tr(args: {'name': query})),
                  onPressed: () => _commit(query, tags),
                ),
              for (final tag in matches.take(6))
                ActionChip(
                  key: Key('tag-suggestion-${tag.id}'),
                  avatar: CircleAvatar(backgroundColor: tag.color, radius: 5),
                  label: Text('#${tag.name}'),
                  onPressed: () => _select(tag),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
