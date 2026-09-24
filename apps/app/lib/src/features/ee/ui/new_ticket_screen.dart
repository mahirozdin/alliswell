import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/error_messages.dart';
import '../../../core/reachability.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../catalogue_search.dart';
import '../data/kb_api.dart';
import '../data/kb_models.dart';
import '../data/new_ticket_api.dart';
import '../kb_providers.dart';
import '../my_tickets_providers.dart';
import '../new_ticket_providers.dart';
import '../providers.dart';
import '../ticket_drafts_providers.dart';
import 'form_field_view.dart';
import 'service_icons.dart';

/// EE-225 — filing a request from the app.
///
/// ── ONE FORM, TWO WAYS OUT ────────────────────────────────────────────
///
/// With a connection the form goes through the door every other surface
/// uses (`POST /tickets`): the service, the unit when several answer it, the
/// service's form in force (EE-214) and, for whoever may, somebody else's
/// name (EE-170). Without one, E19's single exception applies — the SAME form
/// writes a draft (EE-216's engine, no second store) into the person's own
/// space, and says so, including what a draft cannot carry.
///
/// ── NOTHING THE DOOR WOULD REFUSE ────────────────────────────────────
///
/// The list of services is the server's catalogue, which offers exactly what
/// the door accepts (live and routed). The form's conditions and required
/// marks are the server's too; the device only evaluates them as somebody
/// types (`visibleFormFields`), because a form that waited for a round trip
/// to reveal the next question would not be a form.
class EeNewTicketScreen extends ConsumerStatefulWidget {
  const EeNewTicketScreen({super.key});

  @override
  ConsumerState<EeNewTicketScreen> createState() => _EeNewTicketScreenState();
}

class _EeNewTicketScreenState extends ConsumerState<EeNewTicketScreen> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _requesterName = TextEditingController();
  final _requesterEmail = TextEditingController();
  final _answers = <String, Object?>{};
  EeCatalogService? _service;
  String? _unitId;
  bool _onBehalf = false;
  bool _busy = false;
  String? _error;

  // ── EE-226: answers offered while the subject is written ──────────────
  //
  // The subject as last asked about, after the pause in typing.
  String _answersFor = '';
  Timer? _answersPause;

  /// Answers this person READ while writing. How the composition ends says
  /// what they meant: sent with the request, they were read and asked anyway;
  /// left behind without one, they are the deflection the counter is for.
  final _read = <String>{};

  /// A request (or its draft) left this form. Leaving after that is not a
  /// deflection, whatever was read on the way.
  bool _filed = false;

  /// Held from the start: `dispose` may not reach for providers any more.
  late final EeKbApi _kbApi;

  @override
  void initState() {
    super.initState();
    _kbApi = ref.read(eeKbApiProvider);
    for (final controller in [_subject, _body, _requesterName]) {
      controller.addListener(_changed);
    }
    _subject.addListener(_askForAnswers);
  }

  @override
  void dispose() {
    _answersPause?.cancel();
    // Left without a request, after reading an answer: the one event the
    // deflection counter exists for. Sent from here because leaving IS the
    // event — and lost if it cannot be sent, so the number errs low, never
    // high.
    if (!_filed && _read.isNotEmpty) {
      final read = _read.toList();
      // `Future.sync`: even a throw on the way in becomes a failed future
      // here — a counter must never be the reason a screen fails to close.
      unawaited(
        Future.sync(
          () => _kbApi.reportDeflected(read),
        ).catchError((Object _) {}),
      );
    }
    for (final controller in [
      _subject,
      _body,
      _requesterName,
      _requesterEmail,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {});

  /// Asks after a pause rather than per keystroke; capped like the server's
  /// box, where every word becomes a LIKE.
  void _askForAnswers() {
    final text = _subject.text.trim();
    final query = text.length > 120 ? text.substring(0, 120) : text;
    _answersPause?.cancel();
    _answersPause = Timer(const Duration(milliseconds: 400), () {
      if (mounted && query != _answersFor) setState(() => _answersFor = query);
    });
  }

  Future<void> _openAnswer(EeKbSuggestion answer) async {
    final navigator = Navigator.of(context);
    final solved = await showEeKbAnswerSheet(
      context,
      answer,
      onRead: () => _read.add(answer.id),
    );
    if (!mounted) return;
    setState(() {});
    // "This solved it": the person leaves without a request, which is
    // exactly the deflection `dispose` reports.
    if (solved == true) navigator.pop();
  }

  void _pickService(EeCatalogService service) {
    setState(() {
      _service = service;
      // One unit needs no choice; several need the person's.
      _unitId = service.units.length == 1 ? service.units.single.id : null;
      // Answers belong to the form they were given against.
      _answers.clear();
      _error = null;
    });
  }

  /// What is still missing for an online send, in the words on the screen.
  List<String> _missing(bool online) {
    final missing = <String>[];
    if (_subject.text.trim().isEmpty) {
      missing.add('ee.tickets.new.subject'.tr());
    }
    if (!online) return missing;
    final service = _service;
    if (service == null) {
      missing.add('ee.tickets.new.service'.tr());
      return missing;
    }
    if (service.units.length > 1 && _unitId == null) {
      missing.add('ee.tickets.new.unit'.tr());
    }
    for (final field in missingRequiredFields(service.fields, _answers)) {
      missing.add(field.label);
    }
    for (final field in visibleFormFields(service.fields, _answers)) {
      if (field.type == 'number' &&
          _answers[field.key] != null &&
          _answers[field.key] is! num) {
        missing.add(field.label);
      }
    }
    if (_onBehalf && _requesterName.text.trim().isEmpty) {
      missing.add('ee.tickets.new.requesterName'.tr());
    }
    return missing;
  }

  Future<void> _send() async {
    final online = ref.read(serverReachabilityProvider) != false;
    final missing = _missing(online);
    if (missing.isNotEmpty) {
      setState(
        () => _error = 'ee.tickets.new.missing'.tr(
          args: {'fields': missing.join(', ')},
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    try {
      final String done;
      if (online) {
        done = await _file();
      } else {
        final saved = await _draft();
        if (saved == null) {
          setState(() {
            _busy = false;
            _error = 'ee.tickets.new.noDraftHome'.tr();
          });
          return;
        }
        done = saved;
      }
      messenger?.showSnackBar(SnackBar(content: Text(done)));
      navigator.pop();
    } on ApiException catch (failure) {
      // No answer at all: the form turns into its offline self and says so;
      // what was typed stays exactly where it is.
      if (failure.code == 'NETWORK_ERROR') {
        ref.read(serverReachabilityProvider.notifier).unreachable();
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _error = localizedError(failure);
        });
      }
    }
  }

  Future<String> _file() async {
    final service = _service!;
    final visible = {
      for (final field in visibleFormFields(service.fields, _answers))
        field.key,
    };
    final filed = await ref
        .read(eeNewTicketApiProvider)
        .create(
          serviceId: service.id,
          subject: _subject.text.trim(),
          body: _body.text.trim().isEmpty ? null : _body.text.trim(),
          unitId: service.units.length > 1 ? _unitId : null,
          fields: {
            for (final entry in _answers.entries)
              if (visible.contains(entry.key)) entry.key: entry.value,
          },
          requesterName: _onBehalf ? _requesterName.text.trim() : null,
          requesterEmail: _onBehalf && _requesterEmail.text.trim().isNotEmpty
              ? _requesterEmail.text.trim()
              : null,
          openedArticleIds: _read.toList(),
        );
    _filed = true;
    // The requester's list is a REST read; the desk's queue is the replica.
    // Both are told now rather than at their next scheduled look.
    ref.invalidate(eeMyTicketsProvider);
    unawaited(ref.read(syncEngineProvider)?.syncNow());
    return filed.number == null
        ? 'ee.tickets.new.sent'.tr()
        : 'ee.tickets.new.sentNumbered'.tr(args: {'number': '${filed.number}'});
  }

  /// The offline way out: EE-216's store, in the person's own space. Null
  /// when this device knows of no such space to keep it in.
  Future<String?> _draft() async {
    final home = ref.read(draftWorkspaceIdProvider);
    if (home == null) return null;
    await ref
        .read(ticketDraftStoreProvider)
        .write(
          workspaceId: home,
          subject: _subject.text.trim(),
          body: _body.text.trim().isEmpty ? null : _body.text.trim(),
          serviceId: _service?.id,
        );
    // A draft is a request on its way, not a deflection. What was read is not
    // carried: the draft cannot hold it, and a draft that becomes a request
    // leaves the difference where it was either way.
    _filed = true;
    return 'ee.tickets.new.drafted'.tr();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = ref.watch(serverReachabilityProvider) != false;
    final catalog = ref.watch(eeCatalogProvider);
    final mayActForOthers = ref.watch(canProvider('tickets.create_on_behalf'));
    final service = _service;

    return Scaffold(
      appBar: AppBar(title: Text('ee.tickets.new.title'.tr())),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(eeCatalogProvider.future),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AwSpace.x4,
            AwSpace.x4,
            AwSpace.x4,
            AwSpace.x6 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: [
            if (!online) ...[
              _Note(
                key: const Key('new-ticket-offline'),
                icon: Icons.cloud_off_outlined,
                text: 'ee.tickets.new.offline'.tr(),
              ),
              const SizedBox(height: AwSpace.x2),
              _Note(
                key: const Key('new-ticket-draft-note'),
                icon: Icons.inventory_2_outlined,
                text: 'ee.tickets.new.draftCarries'.tr(),
              ),
              const SizedBox(height: AwSpace.x4),
            ],
            // ── The service ───────────────────────────────────────────────
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                key: const Key('new-ticket-service'),
                leading: const Icon(Icons.category_outlined),
                title: Text(service?.name ?? 'ee.tickets.new.pickService'.tr()),
                subtitle: Text(
                  service?.description ?? 'ee.tickets.new.service'.tr(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                enabled: !_busy,
                onTap: () => _openCatalog(catalog),
              ),
            ),
            if (catalog.hasError || (catalog.hasValue && catalog.value == null))
              Padding(
                key: const Key('new-ticket-catalog-unavailable'),
                padding: const EdgeInsets.only(top: AwSpace.x2),
                child: Text(
                  'ee.tickets.new.catalogUnavailable'.tr(),
                  style: _quiet(theme),
                ),
              ),
            if (service != null && service.needsApproval) ...[
              const SizedBox(height: AwSpace.x2),
              _Note(
                key: const Key('new-ticket-approval'),
                icon: Icons.approval_outlined,
                text: 'ee.tickets.new.needsApproval'.tr(),
              ),
            ],
            if (service != null && service.units.length > 1) ...[
              const SizedBox(height: AwSpace.x4),
              Text(
                'ee.tickets.new.unit'.tr(),
                style: theme.textTheme.titleSmall,
              ),
              if (!online)
                Padding(
                  padding: const EdgeInsets.only(top: AwSpace.x1),
                  child: Text(
                    'ee.tickets.new.draftMultiUnit'.tr(),
                    key: const Key('new-ticket-draft-multi-unit'),
                    style: _quiet(theme),
                  ),
                )
              else
                RadioGroup<String>(
                  groupValue: _unitId,
                  onChanged: (value) {
                    if (!_busy) setState(() => _unitId = value);
                  },
                  child: Column(
                    children: [
                      for (final unit in service.units)
                        RadioListTile<String>(
                          key: Key('new-ticket-unit-${unit.id}'),
                          contentPadding: EdgeInsets.zero,
                          value: unit.id,
                          title: Text(unit.name),
                        ),
                    ],
                  ),
                ),
            ],
            // ── What happened ─────────────────────────────────────────────
            const SizedBox(height: AwSpace.x4),
            TextField(
              key: const Key('new-ticket-subject'),
              controller: _subject,
              enabled: !_busy,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'ee.tickets.new.subject'.tr(),
                hintText: 'ee.tickets.new.subjectHint'.tr(),
              ),
            ),
            // ── EE-226: the answer may already be written ───────────────
            if (online)
              _Answers(query: _answersFor, read: _read, onOpen: _openAnswer),
            const SizedBox(height: AwSpace.x2),
            TextField(
              key: const Key('new-ticket-body'),
              controller: _body,
              enabled: !_busy,
              minLines: 3,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'ee.tickets.new.body'.tr(),
                hintText: 'ee.tickets.new.bodyHint'.tr(),
              ),
            ),
            // ── The service's own questions — only with a connection ──────
            if (service != null && online)
              for (final field in visibleFormFields(service.fields, _answers))
                Padding(
                  padding: const EdgeInsets.only(top: AwSpace.x3),
                  // Keyed by service AND field: two services may both ask
                  // "line", and the second must not inherit the first's text.
                  child: EeFormFieldView(
                    key: ValueKey('${service.id}/${field.key}'),
                    field: field,
                    value: _answers[field.key],
                    keyPrefix: 'new-ticket-field',
                    enabled: !_busy,
                    onChanged: (value) => setState(() {
                      if (value == null) {
                        _answers.remove(field.key);
                      } else {
                        _answers[field.key] = value;
                      }
                    }),
                  ),
                ),
            // ── For somebody else (EE-170) ────────────────────────────────
            if (mayActForOthers && online) ...[
              const SizedBox(height: AwSpace.x3),
              SwitchListTile(
                key: const Key('new-ticket-on-behalf'),
                contentPadding: EdgeInsets.zero,
                value: _onBehalf,
                title: Text('ee.tickets.new.onBehalf'.tr()),
                subtitle: Text('ee.tickets.new.onBehalfHelp'.tr()),
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _onBehalf = value),
              ),
              if (_onBehalf) ...[
                TextField(
                  key: const Key('new-ticket-requester-name'),
                  controller: _requesterName,
                  enabled: !_busy,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'ee.tickets.new.requesterName'.tr(),
                  ),
                ),
                TextField(
                  key: const Key('new-ticket-requester-email'),
                  controller: _requesterEmail,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'ee.tickets.new.requesterEmail'.tr(),
                  ),
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: AwSpace.x3),
              AwInlineError(
                message: _error!,
                textKey: const Key('new-ticket-error'),
              ),
            ],
            const SizedBox(height: AwSpace.x4),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                key: const Key('new-ticket-submit'),
                onPressed: _busy ? null : _send,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(online ? Icons.send_outlined : Icons.save_outlined),
                label: Text(
                  (online ? 'ee.tickets.new.send' : 'ee.tickets.new.saveDraft')
                      .tr(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCatalog(AsyncValue<EeCatalog?> catalog) async {
    final picked = await showEeCatalogPicker(context);
    if (picked != null && mounted) _pickService(picked);
  }
}

/// The catalogue as a picker — the new-request form's, and the one a held
/// draft uses to finally name its service (EE-225). One sheet, so the two
/// can never offer different lists.
Future<EeCatalogService?> showEeCatalogPicker(BuildContext context) =>
    showModalBottomSheet<EeCatalogService>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _CatalogSheet(),
    );

/// EE-226 — the answers under the subject, while there is signal.
///
/// Draws NOTHING until there is something to offer: an empty "suggestions"
/// box under every subject would teach people to skip the place where an
/// answer eventually appears. While the next answer is on its way the last
/// one stays, because a list that blinks under every word is harder to read
/// than one that is briefly a word behind.
class _Answers extends ConsumerStatefulWidget {
  const _Answers({
    required this.query,
    required this.read,
    required this.onOpen,
  });

  final String query;
  final Set<String> read;
  final void Function(EeKbSuggestion answer) onOpen;

  @override
  ConsumerState<_Answers> createState() => _AnswersState();
}

class _AnswersState extends ConsumerState<_Answers> {
  List<EeKbSuggestion> _last = const [];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answers = ref.watch(eeKbAnswersForProvider(widget.query));
    // A failed ask offers nothing rather than an error: these are help, not
    // the form, and the reachability banner above already speaks for the
    // network (every request feeds it).
    final shown = answers.hasError
        ? const <EeKbSuggestion>[]
        : answers.value ?? _last;
    _last = shown;
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const Key('new-ticket-answers'),
      padding: const EdgeInsets.only(top: AwSpace.x2),
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AwSpace.x4,
                AwSpace.x3,
                AwSpace.x4,
                AwSpace.x1,
              ),
              child: Text(
                'ee.tickets.new.answers.title'.tr(),
                style: theme.textTheme.titleSmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AwSpace.x4),
              child: Text(
                'ee.tickets.new.answers.hint'.tr(),
                style: _quiet(theme),
              ),
            ),
            for (final answer in shown)
              ListTile(
                key: Key('new-ticket-answer-${answer.id}'),
                leading: Icon(
                  widget.read.contains(answer.id)
                      ? Icons.task_alt_outlined
                      : Icons.lightbulb_outline,
                  semanticLabel: widget.read.contains(answer.id)
                      ? 'ee.tickets.new.answers.read'.tr()
                      : null,
                ),
                title: Text(answer.title),
                subtitle: Text(
                  answer.symptom,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => widget.onOpen(answer),
              ),
            const SizedBox(height: AwSpace.x1),
          ],
        ),
      ),
    );
  }
}

/// One answer, read in full — from the server, which counts the view.
///
/// Resolves `true` when the person says it solved their problem: the form
/// then closes without a request, which is the deflection. [onRead] fires
/// once the text is on screen: an answer that failed to load was not read.
Future<bool?> showEeKbAnswerSheet(
  BuildContext context,
  EeKbSuggestion answer, {
  required VoidCallback onRead,
}) => showModalBottomSheet<bool>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _AnswerSheet(answer: answer, onRead: onRead),
);

final _answerProvider = FutureProvider.autoDispose.family<EeKbArticle, String>(
  (ref, id) => ref.watch(eeKbApiProvider).get(id),
);

class _AnswerSheet extends ConsumerWidget {
  const _AnswerSheet({required this.answer, required this.onRead});

  final EeKbSuggestion answer;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // The provider is auto-disposed with the sheet, so every opening fetches
    // afresh and the text always ARRIVES after this first build — the change
    // this listens for is the moment it was on screen to be read.
    ref.listen(_answerProvider(answer.id), (_, next) {
      if (next.hasValue) onRead();
    });
    final article = ref.watch(_answerProvider(answer.id));
    Widget section(String label, String text) => Padding(
      padding: const EdgeInsets.only(top: AwSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleSmall),
          const SizedBox(height: AwSpace.x1),
          Text(text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('kb-answer-sheet'),
        padding: const EdgeInsets.fromLTRB(
          AwSpace.x4,
          0,
          AwSpace.x4,
          AwSpace.x4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(answer.title, style: theme.textTheme.titleLarge),
            ...article.when(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.all(AwSpace.x6),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (error, _) => [
                const SizedBox(height: AwSpace.x3),
                AwInlineError(message: localizedError(error)),
              ],
              data: (full) => [
                section('ee.kb.symptom'.tr(), full.symptom),
                if ((full.environment ?? '').trim().isNotEmpty)
                  section('ee.kb.environment'.tr(), full.environment!),
                section(
                  'ee.kb.solution'.tr(),
                  (full.solution ?? '').trim().isEmpty
                      ? 'ee.tickets.new.answers.noSolution'.tr()
                      : full.solution!,
                ),
              ],
            ),
            const SizedBox(height: AwSpace.x4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AwSpace.x2,
              runSpacing: AwSpace.x2,
              children: [
                TextButton(
                  key: const Key('kb-answer-back'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('ee.tickets.new.answers.back'.tr()),
                ),
                if (article.hasValue)
                  FilledButton.tonal(
                    key: const Key('kb-answer-solved'),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text('ee.tickets.new.answers.solved'.tr()),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

TextStyle? _quiet(ThemeData theme) => theme.textTheme.bodySmall?.copyWith(
  color: theme.colorScheme.onSurfaceVariant,
);

class _Note extends StatelessWidget {
  const _Note({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AwSpace.x2),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

/// The catalogue, grouped by its shelves and searchable on the device.
///
/// The search folds on the device (`foldSearchText`), EE-212's decision for
/// the app: the catalogue arrives whole over REST, so `yazici` finds
/// `Yazıcı` without asking the server for a third definition of "matches".
class _CatalogSheet extends ConsumerStatefulWidget {
  const _CatalogSheet();

  @override
  ConsumerState<_CatalogSheet> createState() => _CatalogSheetState();
}

class _CatalogSheetState extends ConsumerState<_CatalogSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = ref.watch(eeCatalogProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AwSpace.x4,
            0,
            AwSpace.x4,
            AwSpace.x4,
          ),
          child: catalog.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AwSpace.x6),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => AwInlineError(message: localizedError(error)),
            data: (data) {
              if (data == null || data.services.isEmpty) {
                return AwEmptyState(
                  key: const Key('new-ticket-catalog-empty'),
                  icon: Icons.category_outlined,
                  title: 'ee.tickets.new.pickService'.tr(),
                  message:
                      (data == null
                              ? 'ee.tickets.new.catalogUnavailable'
                              : 'ee.tickets.new.noServices')
                          .tr(),
                );
              }
              final hits = [
                for (final service in data.services)
                  if (catalogueMatches(_query, [
                    service.name,
                    service.description,
                  ]))
                    service,
              ];
              final names = {for (final c in data.categories) c.id: c.name};
              final byShelf = <String?, List<EeCatalogService>>{};
              for (final service in hits) {
                final shelf = names.containsKey(service.categoryId)
                    ? service.categoryId
                    : null;
                (byShelf[shelf] ??= []).add(service);
              }
              final shelves = [
                for (final c in data.categories)
                  if (byShelf.containsKey(c.id)) c.id,
                if (byShelf.containsKey(null)) null,
              ];
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ee.tickets.new.pickService'.tr(),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AwSpace.x2),
                  TextField(
                    key: const Key('new-ticket-service-search'),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'ee.tickets.new.serviceSearch'.tr(),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: AwSpace.x2),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final shelf in shelves) ...[
                          if (shelves.length > 1 || shelf != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AwSpace.x3,
                                bottom: AwSpace.x1,
                              ),
                              child: Text(
                                shelf == null
                                    ? 'ee.tickets.new.otherCategory'.tr()
                                    : names[shelf]!,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          for (final service in byShelf[shelf]!)
                            ListTile(
                              key: Key('catalog-service-${service.id}'),
                              contentPadding: EdgeInsets.zero,
                              // EE-228: the desk's chosen icon, where the
                              // person choosing a service looks for it.
                              leading: Icon(serviceIconData(service.icon)),
                              title: Text(service.name),
                              subtitle: service.description == null
                                  ? null
                                  : Text(
                                      service.description!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              trailing: service.needsApproval
                                  ? Icon(
                                      Icons.approval_outlined,
                                      semanticLabel:
                                          'ee.tickets.new.needsApproval'.tr(),
                                    )
                                  : null,
                              onTap: () => Navigator.of(context).pop(service),
                            ),
                        ],
                        if (hits.isEmpty)
                          Padding(
                            key: const Key('new-ticket-service-none'),
                            padding: const EdgeInsets.all(AwSpace.x4),
                            child: Text(
                              'ee.tickets.new.searchEmpty'.tr(),
                              style: _quiet(theme),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
