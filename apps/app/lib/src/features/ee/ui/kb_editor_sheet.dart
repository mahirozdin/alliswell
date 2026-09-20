import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/db/database.dart';
import '../../../widgets/sheets.dart';
import '../kb_providers.dart';

/// Writing an article (EE-196).
///
/// ── THE SOLUTION IS OPTIONAL HERE, AND THAT IS KCS ─────────────────────
///
/// An article opens in `wip`: the problem and the environment are captured,
/// the answer is not there yet. The whole method rests on that first save
/// being cheap enough to happen while the work is still open, so this sheet
/// asks for a title and a symptom and lets the rest wait.
///
/// The transition OUT of `wip` is where the solution becomes required, and
/// that refusal lives on the server (`KB_SOLUTION_REQUIRED`). This sheet does
/// not duplicate it: a second copy of a rule is a second answer the first
/// time somebody changes one of them.
///
/// ── THE STATUS IS NOT IN HERE ──────────────────────────────────────────
///
/// Moving an article through its life and correcting what it says are
/// different acts, and the history has to be able to tell them apart — the
/// server gives them separate doors (`PATCH` vs `/status`) for exactly that
/// reason, and a sheet that saved both at once would write one `updated` row
/// where the ledger expects two facts.
Future<void> showKbEditorSheet(
  BuildContext context,
  WidgetRef ref, {
  KbArticleRecord? existing,
}) {
  return showAwSheet<void>(
    context,
    builder: (_) => _KbEditorSheet(existing: existing),
  );
}

class _KbEditorSheet extends ConsumerStatefulWidget {
  const _KbEditorSheet({this.existing});
  final KbArticleRecord? existing;

  @override
  ConsumerState<_KbEditorSheet> createState() => _KbEditorSheetState();
}

class _KbEditorSheetState extends ConsumerState<_KbEditorSheet> {
  late final TextEditingController _title = TextEditingController(
    text: widget.existing?.title ?? '',
  );
  late final TextEditingController _symptom = TextEditingController(
    text: widget.existing?.symptom ?? '',
  );
  late final TextEditingController _environment = TextEditingController(
    text: widget.existing?.environment ?? '',
  );
  late final TextEditingController _solution = TextEditingController(
    text: widget.existing?.solution ?? '',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _symptom.dispose();
    _environment.dispose();
    _solution.dispose();
    super.dispose();
  }

  String? _nullable(String value) => value.trim().isEmpty ? null : value.trim();

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(eeKbApiProvider);
      final existing = widget.existing;
      if (existing == null) {
        await api.create(
          title: _title.text.trim(),
          symptom: _symptom.text.trim(),
          environment: _nullable(_environment.text),
          solution: _nullable(_solution.text),
        );
      } else {
        final patch = <String, dynamic>{};
        if (_title.text.trim() != existing.title) {
          patch['title'] = _title.text.trim();
        }
        if (_symptom.text.trim() != existing.symptom) {
          patch['symptom'] = _symptom.text.trim();
        }
        if (_nullable(_environment.text) != existing.environment) {
          patch['environment'] = _nullable(_environment.text);
        }
        if (_nullable(_solution.text) != existing.solution) {
          patch['solution'] = _nullable(_solution.text);
        }
        if (patch.isNotEmpty) await api.update(existing.id, patch);
        ref.invalidate(eeKbArticleProvider(existing.id));
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = localizedError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready =
        _title.text.trim().isNotEmpty && _symptom.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'ee.kb.new'.tr() : 'ee.kb.edit'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('kb-field-title'),
              controller: _title,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'ee.kb.fieldTitle'.tr()),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('kb-field-symptom'),
              controller: _symptom,
              onChanged: (_) => setState(() {}),
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'ee.kb.fieldSymptom'.tr(),
                helperText: 'ee.kb.fieldSymptomHelp'.tr(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('kb-field-environment'),
              controller: _environment,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'ee.kb.fieldEnvironment'.tr(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('kb-field-solution'),
              controller: _solution,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: 'ee.kb.fieldSolution'.tr(),
                helperText: 'ee.kb.fieldSolutionHelp'.tr(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('kb-save'),
              onPressed: _busy || !ready ? null : _save,
              child: Text('ee.kb.save'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
