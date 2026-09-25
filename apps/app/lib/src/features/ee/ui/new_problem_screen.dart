import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error_messages.dart';
import '../../../core/reachability.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/problems_models.dart';
import '../problems_providers.dart';
import 'problem_detail_screen.dart';

/// Raising a problem record from the phone (EE-270 box 2, EE-280).
///
/// What `POST /problems` takes: a title, the SYMPTOM people see (required —
/// it is how anybody recognises the fault next time) and, when somebody has
/// one already, the workaround. From a request it is "the known-error
/// record": the request's subject is the first draft of the title, and the
/// server files the record in the request's desk and links the two in one
/// step. The root cause and the status are the problem owner's later work,
/// on the server's own doors.
///
/// Online only, like every write to a record the device holds read-only:
/// with no signal the button is grey and the sentence under it says why.
class EeNewProblemScreen extends ConsumerStatefulWidget {
  const EeNewProblemScreen({super.key, this.source});

  /// The request this is raised from, or null.
  final EeProblemSource? source;

  @override
  ConsumerState<EeNewProblemScreen> createState() => _EeNewProblemScreenState();
}

class _EeNewProblemScreenState extends ConsumerState<EeNewProblemScreen> {
  late final TextEditingController _title;
  final _symptom = TextEditingController();
  final _workaround = TextEditingController();
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.source?.subject ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _symptom.dispose();
    _workaround.dispose();
    super.dispose();
  }

  bool get _complete =>
      _title.text.trim().isNotEmpty && _symptom.text.trim().isNotEmpty;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(eeProblemActionsProvider)
          .create(
            title: _title.text.trim(),
            symptom: _symptom.text.trim(),
            workaround: _workaround.text.trim(),
            source: widget.source,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ee.problems.create.done'.tr())));
      if (GoRouter.maybeOf(context) != null) {
        context.pushReplacement('/problems/${created.id}');
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => EeProblemDetailScreen(problemId: created.id),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offline = ref.watch(
      serverReachabilityProvider.select((up) => up == false),
    );
    final source = widget.source;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          source == null
              ? 'ee.problems.create.title'.tr()
              : 'ee.problems.create.knownErrorTitle'.tr(),
        ),
      ),
      body: ListView(
        padding: awListPadding(context, top: AwSpace.x4),
        children: [
          if (source != null) ...[
            Row(
              key: const Key('problem-new-source'),
              children: [
                const Icon(Icons.support_agent, size: 20),
                const SizedBox(width: AwSpace.x2),
                Expanded(
                  child: Text(
                    'ee.problems.create.fromTicket'.tr(
                      args: {
                        'ticket': [
                          if (source.number != null) '#${source.number}',
                          source.subject,
                        ].join(' · '),
                      },
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AwSpace.x4),
          ],
          TextField(
            key: const Key('problem-new-title'),
            controller: _title,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: 'ee.problems.create.name'.tr(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AwSpace.x2),
          TextField(
            key: const Key('problem-new-symptom'),
            controller: _symptom,
            minLines: 2,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: 'ee.problems.symptom'.tr(),
              helperText: 'ee.problems.create.symptomHelp'.tr(),
              helperMaxLines: 2,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AwSpace.x3),
          TextField(
            key: const Key('problem-new-workaround'),
            controller: _workaround,
            minLines: 2,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: 'ee.problems.create.workaround'.tr(),
              helperText: 'ee.problems.create.workaroundHelp'.tr(),
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: AwSpace.x4),
          if (_error != null) ...[
            AwInlineError(
              textKey: const Key('problem-new-error'),
              message: localizedError(_error!),
            ),
            const SizedBox(height: AwSpace.x3),
          ],
          FilledButton(
            key: const Key('problem-new-save'),
            onPressed: _complete && !_saving && !offline ? _save : null,
            child: Text('ee.problems.create.save'.tr()),
          ),
          if (offline)
            Padding(
              key: const Key('problem-new-offline'),
              padding: const EdgeInsets.only(top: AwSpace.x2),
              child: Text(
                'ee.problems.create.offline'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
