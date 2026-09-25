import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../core/date_format.dart';
import '../../../core/error_messages.dart';
import '../../../core/persisted_prefs.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/db/database.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../../files/providers.dart';
import '../data/kb_models.dart';
import '../data/ticket_links_models.dart';
import '../data/ticket_write_api.dart';
import '../kb_providers.dart';
import '../providers.dart';
import '../services_providers.dart';
import '../ticket_links_providers.dart';
import '../tickets_providers.dart';
import '../ticket_write_providers.dart';
import 'history_tab.dart';
import 'ticket_archive_screen.dart';
import 'sla_chip.dart';
import 'ticket_actions.dart';
import 'ticket_composer.dart';
import 'ticket_worklog_section.dart';

/// One request: what was asked, what happened, and what was said (EE-084).
///
/// ── Why this one IS a tab, when the task's history is a screen ─────────────
///
/// EE-069 made a task's history a separate SCREEN, and said why: the task
/// detail is a CORE screen, and giving it a tab bar for an EE feature would
/// reshape core for an overlay reason (ADR-0001 §5). That objection does not
/// exist here — this screen belongs to the overlay — so item 10's actual words
/// ("History sekmesinde izlenir") are honoured rather than approximated. The
/// widget rendering it is EE-026's, unchanged.
///
/// ── The internal note ─────────────────────────────────────────────────────
///
/// An agent who mistakes an internal note for a reply to the customer has said
/// the wrong thing to the wrong person, and no amount of "they should have
/// read carefully" fixes that afterwards. So the distinction is carried three
/// ways at once — a tinted card, a lock icon, and the word — because any one of
/// them alone fails somebody: colour fails a colour-blind reader, the icon
/// fails at a glance on a dirty screen, and the word fails nobody but is the
/// easiest to skim past.
/// Opens one request (EE-251). By its address when a router is there to ask —
/// the queue, an asset's history and a notification then reach the SAME
/// place a pasted link does — and by a plain push when the screen is hosted
/// without one.
void awOpenTicket(BuildContext context, String ticketId) {
  if (GoRouter.maybeOf(context) != null) {
    context.push('/tickets/$ticketId');
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EeTicketDetailScreen(ticketId: ticketId),
    ),
  );
}

class EeTicketDetailScreen extends ConsumerWidget {
  const EeTicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref.watch(ticketProvider(ticketId));
    // EE-252: this device holds no copy — which for the person who ASKED is
    // the normal case (the unit's replica is not theirs, ADR-0011 §3).
    // EE-266: and for the desk it is three other cases — archived, live in
    // another unit, or not theirs at all — which the server tells apart.
    if (ticket.hasValue && ticket.value == null) {
      return EeTicketOffDeviceScreen(ticketId: ticketId);
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('ee.tickets.detailTitle'.tr()),
          bottom: TabBar(
            tabs: [
              Tab(text: 'ee.tickets.tabThread'.tr()),
              Tab(text: 'ee.tickets.tabHistory'.tr()),
            ],
          ),
        ),
        body: ticket.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AwErrorState(message: '$error'),
          data: (row) {
            // Not an error: the archive sweep drops terminal tickets from the
            // replica (EE-091), so a link somebody kept can legitimately point
            // at a row this device no longer holds.
            if (row == null) {
              return AwEmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'ee.tickets.goneTitle'.tr(),
                message: 'ee.tickets.goneBody'.tr(),
              );
            }
            return TabBarView(
              children: [
                _Thread(ticket: row),
                EeHistoryTab(entityType: 'ee_ticket', entityId: ticketId),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Thread extends ConsumerWidget {
  const _Thread({required this.ticket});

  final TicketRecord ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dateFormat = ref.watch(dateFormatProvider);
    final comments = ref.watch(ticketCommentsProvider(ticket.id));
    // EE-254: who could not be checked, in the server's words — read with
    // the actions, since the replica has no column for it. And ASKED ONLY
    // WHERE IT CAN BE TRUE: a request a mail filed for somebody outside, or a
    // reply nobody on the team wrote (an unverified mail is always authorless).
    // Everywhere else the detail still opens without asking the server
    // anything — EE-224's measured rule.
    final mayBeUnverified =
        (ticket.source == 'email' && ticket.requesterId == null) ||
        (comments.value ?? const <TicketCommentRecord>[]).any(
          (c) => c.authorId == null && !c.internal,
        );
    // EE-258: who asked is the replica's (v33). A request this device pulled
    // before it kept them has neither until the server sends it again — and
    // NO question is added for that: where the detail already asks (above),
    // the answer carries who asked and fills the gap; elsewhere the row waits,
    // because the device cannot tell an old row from a request nobody put a
    // name on, and asking on every open for an answer that does not exist is
    // the cost EE-224 refused.
    // EE-278: the answers the request was filed with live on the server
    // (EE-213 keeps them out of the replica), and come with the same read.
    // Asked only where there can be some — the service has a form, which the
    // catalogue says — so a request with no form still opens without a
    // question, as EE-224 measured it should.
    final serviceId = ticket.serviceId;
    final hasForm =
        serviceId != null &&
        (ref.watch(
              eeServicesProvider.select(
                (services) => services.value?.any(
                  (s) => s.id == serviceId && s.formFields.isNotEmpty,
                ),
              ),
            ) ??
            false);
    final checked = mayBeUnverified || hasForm
        ? ref.watch(eeTicketActionsProvider(ticket.id)).value
        : null;

    return ListView(
      padding: const EdgeInsets.all(AwSpace.x4),
      children: [
        // EE-167: the number above the subject rather than inside it. On the
        // detail screen there is room for a line, and the thing somebody reads
        // out on the phone should not be competing with a sentence for it.
        if (ticket.number != null)
          Text(
            '#${ticket.number}',
            key: const Key('ticket-number'),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        Text(ticket.subject, style: theme.textTheme.titleLarge),
        const SizedBox(height: AwSpace.x2),
        Wrap(
          spacing: AwSpace.x2,
          runSpacing: AwSpace.x2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // EE-224: on a live request the two chips are the doors — what
            // they offer is the server's list for this person. A finished
            // request takes no further writes at all, so it keeps plain chips
            // rather than buttons that could only be refused.
            if (ticket.terminalAt == null) ...[
              EeTicketStatusAction(ticket: ticket),
              EeTicketPriorityAction(ticket: ticket),
            ] else ...[
              _Chip(label: 'ee.tickets.status.${ticket.status}'.tr()),
              _Chip(label: 'ee.tickets.priority.${ticket.priority}'.tr()),
            ],
            if (ticket.terminalAt != null)
              _Chip(
                label: 'ee.tickets.closedOn'.tr(
                  args: {
                    'date': awFormatDate(
                      ticket.terminalAt!,
                      format: dateFormat,
                    ),
                  },
                ),
              ),
          ],
        ),
        if (ticket.terminalAt == null) const EeTicketActionsOffline(),
        // EE-254 (D17.2): the request came as mail claiming a colleague's
        // address that could not be proven. Said before anything else is
        // read, because it changes who "the person who asked" is.
        if (checked?.senderUnverified == true)
          _Unverified(
            key: const Key('ticket-sender-unverified'),
            text: 'ee.tickets.senderUnverified'.tr(),
          ),
        // EE-258 (AW-E07): who asked, and where the answer goes — read before
        // who is on it, because it is the first thing somebody asks.
        _Requester(ticket: ticket, fromServer: checked),
        // EE-224: the third door, beside the other two. Who is on it is read
        // before anything else below: an agent asks "is somebody already
        // here" before reading forty replies.
        EeTicketAssigneeSection(ticket: ticket),
        // EE-097: the countdown, under the chips and above the request itself.
        // An agent deciding what to pick up next reads it before the body.
        AwSlaCountdown(ticket: ticket),
        if (ticket.body != null && ticket.body!.isNotEmpty) ...[
          const SizedBox(height: AwSpace.x4),
          Text(ticket.body!, style: theme.textTheme.bodyMedium),
        ],
        // EE-278: what the form asked, and what they answered — right under
        // the request's own words, because it is part of what was asked.
        if (checked != null && checked.answers.isNotEmpty)
          EeTicketAnswersView(answers: checked.answers, dateFormat: dateFormat),
        // EE-189/EE-190: what this request has to do with anything else, and
        // what came out of it. Below the request and ABOVE the conversation,
        // because an agent picking this up asks "is this the known one, and
        // has somebody already started" before reading forty replies.
        _Relations(ticketId: ticket.id),
        _Knowledge(ticket: ticket),
        _Attachments(ticket: ticket),
        // EE-208: the hours, below the files and above the conversation.
        // An agent scrolling to reply passes it, which is when they remember
        // they have not written down this morning.
        EeTicketWorklogSection(ticketId: ticket.id),
        const SizedBox(height: AwSpace.x6),
        Text('ee.tickets.thread'.tr(), style: theme.textTheme.titleSmall),
        const SizedBox(height: AwSpace.x2),
        comments.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AwErrorState(message: '$error'),
          data: (rows) => rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: AwSpace.x2),
                  child: Text(
                    'ee.tickets.threadEmpty'.tr(),
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : Column(
                  children: [
                    for (final comment in rows)
                      _CommentCard(
                        comment: comment,
                        dateFormat: dateFormat,
                        unverified:
                            checked?.unverifiedCommentIds.contains(
                              comment.id,
                            ) ??
                            false,
                      ),
                  ],
                ),
        ),
        // EE-223: the answer, under the conversation it answers. Hidden — not
        // disabled — without `tickets.comment` (EE-052's cache): a box that
        // 403s on send is a dead button with extra steps. Whoever reaches
        // this screen reads the request from the device's copy, which only a
        // member of its desk syncs, so offering the internal note is right.
        if (ref.watch(canProvider('tickets.comment')))
          // The server closes a finished thread (TICKET_TERMINAL) and says so
          // with the terminal stamp it sends down; the box follows that stamp
          // rather than a list of statuses of its own.
          ticket.terminalAt == null
              ? EeTicketComposer(ticketId: ticket.id)
              : Padding(
                  key: const Key('ticket-composer-closed'),
                  padding: const EdgeInsets.only(top: AwSpace.x3),
                  child: Text(
                    'ee.tickets.composer.closed'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
      ],
    );
  }
}

/// EE-189 + EE-190 — the problem, the work, and the way back.
///
/// Three things a request carries that its own row cannot: the problem that
/// explains it (with the WORKAROUND, the one sentence an agent can act on
/// while the fix is built), the work it caused, and — when it has come up
/// again — the way to open a new one instead of reopening this.
class _Relations extends ConsumerWidget {
  const _Relations({required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final relations = ref.watch(eeTicketRelationsProvider(ticketId));

    return relations.when(
      // Quiet on both: this section is an ADDITION to a screen that already
      // works. A spinner or a red box here would make a slow network look
      // like a broken request.
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) {
        final canConvert = ref.watch(canProvider('tickets.convert'));
        final canCreate = ref.watch(canProvider('tickets.create'));
        final titles =
            ref.watch(eeLinkedTaskTitlesProvider(data.taskIds)).value ??
            const {};

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data.waitingReason != null) ...[
              const SizedBox(height: AwSpace.x4),
              _Chip(
                label:
                    '${'ee.tickets.waitingReason'.tr()}: '
                    '${'ee.sla.reason.${data.waitingReason}'.tr()}',
              ),
            ],
            for (final problem in data.problems) ...[
              const SizedBox(height: AwSpace.x4),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(AwSpace.x3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(problem.title, style: theme.textTheme.titleSmall),
                      if (problem.hasUsableWorkaround) ...[
                        const SizedBox(height: AwSpace.x2),
                        // The reason this card exists. Full text, never
                        // truncated: a workaround cut in half is a wrong one.
                        Text(
                          problem.workaround!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            if (data.assets.isNotEmpty) ...[
              const SizedBox(height: AwSpace.x6),
              Text(
                'ee.tickets.affectedAssets'.tr(),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: AwSpace.x2),
              // Shown only when there is one. An empty "affected equipment"
              // heading on every request would teach agents to scroll past
              // this section, and the section is the whole point on the day a
              // machine is involved.
              for (final asset in data.assets)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.precision_manufacturing_outlined),
                  // Tag first: it is painted on the machine, and it is what a
                  // technician reads out on the phone.
                  title: Text('${asset.tag} · ${asset.name}'),
                  subtitle: Text(
                    [
                      'ee.assets.status.${asset.status}'.tr(),
                      if (asset.location != null) asset.location!,
                    ].join(' · '),
                  ),
                ),
            ],
            const SizedBox(height: AwSpace.x6),
            Text(
              'ee.tickets.linkedTasks'.tr(),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AwSpace.x2),
            if (data.taskIds.isEmpty)
              Text(
                'ee.tickets.linkedTasksEmpty'.tr(),
                style: theme.textTheme.bodySmall,
              )
            else
              // A LIST, which is the whole of GAP §3.11: the data model always
              // allowed several (`ee_ticket_task_links` is unique on the task,
              // not on the ticket) and the screen showed one.
              for (final id in data.taskIds)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.check_circle_outline),
                  // A task the device has not pulled yet is still a task: the
                  // id is shown rather than the row hidden, because a missing
                  // line reads as "no work was done".
                  title: Text(titles[id] ?? id),
                ),
            Wrap(
              spacing: AwSpace.x2,
              children: [
                if (canConvert)
                  TextButton.icon(
                    onPressed: () async {
                      await ref
                          .read(eeTicketLinksApiProvider)
                          .convertToTask(ticketId);
                      ref.invalidate(eeTicketRelationsProvider(ticketId));
                    },
                    icon: const Icon(Icons.add),
                    label: Text('ee.tickets.openAnotherTask'.tr()),
                  ),
                if (canCreate)
                  TextButton.icon(
                    onPressed: () => _askAgain(context, ref),
                    icon: const Icon(Icons.replay),
                    label: Text('ee.tickets.relatedAction'.tr()),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// EE-190 — and the dialog says what it is about to do.
  ///
  /// "This has come up again" is a button an agent presses expecting a reopen,
  /// because that is what every other tool does. So the sentence explaining
  /// that a NEW request is opened is in the dialog rather than in a doc
  /// nobody reads — the surprise is cheaper here than afterwards.
  Future<void> _askAgain(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ee.tickets.relatedAction'.tr()),
        content: Text('ee.tickets.relatedHint'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('common.ok'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(eeTicketLinksApiProvider).openRelated(ticketId);
    ref.invalidate(eeTicketRelationsProvider(ticketId));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('ee.tickets.relatedOpened'.tr())));
  }
}

/// EE-196 — what the desk already knows about this, and a way to write down
/// what it just learned.
///
/// ── THE MATCHES ARE ASSISTANCE, NOT DEFLECTION ─────────────────────────
///
/// An article shown BEFORE somebody opens a request prevents one; an article
/// shown AFTER helps answer it. The task says so in a sentence and the
/// difference is the whole measurement, so this surface increments NOTHING —
/// a deflection counter fed from here would report saves that never happened
/// and make the desk look better the more requests it received. The counting
/// half belongs to the portal (EE-197), where somebody really is about to ask.
///
/// ── AND ONLY PUBLISHED ONES ARE OFFERED ────────────────────────────────
///
/// A suggestion list is exactly where an unreviewed draft would get pasted
/// into a reply without anybody reading the status chip, which is the thing
/// `kb.publish` exists to prevent. The provider filters; the chip is a second
/// line of defence rather than the first.
class _Knowledge extends ConsumerWidget {
  const _Knowledge({required this.ticket});

  final TicketRecord ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canWrite = ref.watch(canProvider('kb.write'));
    // Matched on the SUBJECT rather than on the whole thread: the subject is
    // what somebody wrote while describing the problem, and a body full of
    // "thanks, that worked" would drag the match towards whatever article
    // happens to share a word with a pleasantry.
    final matches =
        ref.watch(eeKbSuggestionsProvider(ticket.subject)).value ??
        const <KbArticleRecord>[];
    final produced =
        ref.watch(eeKbOfTicketProvider(ticket.id)).value ??
        const <EeKbArticle>[];

    if (matches.isEmpty && produced.isEmpty && !canWrite) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AwSpace.x3),
        Text('ee.kb.onTicket'.tr(), style: theme.textTheme.titleSmall),
        for (final article in matches)
          ListTile(
            key: Key('kb-match-${article.id}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.lightbulb_outline),
            title: Text(article.title),
            subtitle: Text(
              article.symptom,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => context.push('/kb/${article.id}'),
          ),
        for (final article in produced)
          ListTile(
            key: Key('kb-produced-${article.id}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(article.title),
            subtitle: Text('ee.kb.status.${article.status}'.tr()),
            onTap: () => context.push('/kb/${article.id}'),
          ),
        if (canWrite && produced.isEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('kb-harvest'),
              onPressed: () async {
                try {
                  final article = await ref
                      .read(eeKbApiProvider)
                      .fromTicket(ticket.id);
                  ref.invalidate(eeKbOfTicketProvider(ticket.id));
                  if (!context.mounted) return;
                  context.push('/kb/${article.id}');
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(localizedError(error))),
                  );
                }
              },
              icon: const Icon(Icons.post_add_outlined),
              label: Text('ee.kb.harvest'.tr()),
            ),
          ),
      ],
    );
  }
}

/// EE-198 — the files on a request, and which of them a stranger sent.
///
/// ── THE REQUEST HAD NO ATTACHMENT LIST UNTIL NOW ───────────────────────
///
/// EE-168 gave a request files on the SERVER and never drew them; measured,
/// this round. So the warning the contract asks for had nowhere to live, and
/// the list is built here with it rather than before it — a badge on a list
/// nobody can see would satisfy the sentence and not the person.
///
/// ── THE WARNING IS ABOUT ORIGIN, AND SAYS SO ───────────────────────────
///
/// There is no virus scanner in this product. So the badge does not say
/// "unsafe", which would be a claim nobody measured; it says the file came
/// from outside, which is the fact we actually hold. What the reader does
/// with that is their judgement, and it is the judgement they would want to
/// make before double-clicking something a stranger sent.
///
/// The ids come from the server and the files from the replica, so a desk
/// whose server has not been updated sees its files with no badges rather
/// than an error — and nothing is ever marked external by accident, only by
/// appearing on that list.
class _Attachments extends ConsumerWidget {
  const _Attachments({required this.ticket});

  final TicketRecord ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final files =
        ref
            .watch(
              targetFilesProvider((targetType: 'ticket', targetId: ticket.id)),
            )
            .value ??
        const <FileAttachment>[];
    if (files.isEmpty) return const SizedBox.shrink();
    final external =
        ref.watch(eeTicketExternalFilesProvider(ticket.id)).value ??
        EeExternalFiles.none;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AwSpace.x3),
        Text('ee.tickets.attachments'.tr(), style: theme.textTheme.titleSmall),
        for (final file in files)
          ListTile(
            key: Key('ticket-file-${file.id}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              external.isExternal(file.id)
                  ? Icons.report_gmailerrorred_outlined
                  : Icons.attach_file,
            ),
            title: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: external.isExternal(file.id)
                ? Text(
                    key: Key('ticket-file-external-${file.id}'),
                    _externalLabel(external, file.id),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : null,
            onTap: () => _open(context, ref, file.id),
          ),
      ],
    );
  }

  /// EE-260: where the file came from, always; "not scanned" only when that
  /// is true of THIS file. A file a scanner passed still says it came from
  /// outside and still asks for care — a signature list that does not know a
  /// file is not a verdict that the file is safe.
  String _externalLabel(EeExternalFiles external, String fileId) =>
      external.isUnscanned(fileId)
      ? 'ee.tickets.attachmentExternal'.tr()
      : 'ee.tickets.attachmentExternalScanned'.tr();

  /// Downloading is core's presigned GET, unchanged. The overlay adds the
  /// sentence beside it and takes nothing away: a file a stranger sent is
  /// still the evidence the desk asked for.
  Future<void> _open(BuildContext context, WidgetRef ref, String fileId) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final url = await ref.read(fileUrlProvider(fileId).future);
    if (url == null) {
      messenger?.showSnackBar(
        SnackBar(content: Text('ee.tickets.attachmentUnavailable'.tr())),
      );
      return;
    }
    await launchUrlString(url);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AwSpace.x3,
      vertical: AwSpace.x1,
    ),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AwRadius.pill),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelMedium),
  );
}

/// EE-254: "we could not check who wrote this", with the icon and the words
/// both — never colour alone.
/// EE-278 — the answers a request was filed with (EE-213's service form).
///
/// The server's words, read with the detail: the label is the question as it
/// was asked on the day, so renaming a field later does not rewrite what a
/// request in March said. EE-242 fixed the endpoint that returns them and
/// wrote that the app "will read" them; no screen did, until the demo's
/// purchase opened with its amount nowhere on it.
class EeTicketAnswersView extends StatelessWidget {
  const EeTicketAnswersView({
    required this.answers,
    required this.dateFormat,
    super.key,
  });

  final List<EeTicketAnswer> answers;
  final String dateFormat;

  String _shown(EeTicketAnswer answer) => switch (answer.type) {
    'checkbox' => (answer.value == 'true' ? 'common.yes' : 'common.no').tr(),
    'date' => switch (DateTime.tryParse(answer.value)) {
      final day? => awFormatDate(day, format: dateFormat),
      null => answer.value,
    },
    _ => answer.value,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('ticket-answers'),
      padding: const EdgeInsets.only(top: AwSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ee.tickets.answers.title'.tr(),
            style: theme.textTheme.titleSmall,
          ),
          for (final answer in answers)
            Padding(
              padding: const EdgeInsets.only(top: AwSpace.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    answer.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(_shown(answer), style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// EE-258 (AW-E07) — who asked, and where the answer goes.
///
/// From the replica, so a desk with no signal can still say who a request is
/// from: v33 keeps the name and address of somebody without an account, and
/// an account's name comes from the rosters this device syncs. Where the
/// detail has the server's answer anyway ([fromServer]), it fills in for a
/// request pulled before the replica kept them. Nobody asked a request a
/// monitor or a rule opened, so it draws nothing.
class _Requester extends ConsumerWidget {
  const _Requester({required this.ticket, this.fromServer});

  final TicketRecord ticket;
  final EeTicketActions? fromServer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final requesterId = ticket.requesterId;
    final accountName = requesterId == null
        ? null
        : ref.watch(
            eeMemberNamesProvider.select((names) => names.value?[requesterId]),
          );
    final name =
        accountName ??
        ticket.requesterName ??
        fromServer?.requesterDisplayName ??
        (requesterId != null ? 'ee.tickets.askedBy.teamMember'.tr() : null);
    final email = ticket.requesterEmail ?? fromServer?.requesterEmail;
    if (name == null && email == null) return const SizedBox.shrink();
    final origin = switch (ticket.source) {
      'email' => 'ee.tickets.askedBy.viaEmail'.tr(),
      'public' => 'ee.tickets.askedBy.viaPortal'.tr(),
      'internal' when requesterId == null => 'ee.tickets.askedBy.onBehalf'.tr(),
      _ => null,
    };
    return Padding(
      key: const Key('ticket-requester'),
      padding: const EdgeInsets.only(top: AwSpace.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.person_outline,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AwSpace.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ee.tickets.askedBy.title'.tr(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (name != null)
                  Text(
                    name,
                    key: const Key('ticket-requester-name'),
                    style: theme.textTheme.bodyLarge,
                  ),
                if (email != null)
                  // The address IS the way back, so it is a button: a tap
                  // opens the mail app with it filled in. A full-size target,
                  // and the words say where it goes.
                  Semantics(
                    link: true,
                    label: 'ee.tickets.askedBy.writeTo'.tr(
                      args: {'address': email},
                    ),
                    excludeSemantics: true,
                    child: TextButton.icon(
                      key: const Key('ticket-requester-email'),
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => ref.read(eeMailLauncherProvider)(email),
                      icon: const Icon(Icons.mail_outline, size: 18),
                      label: Text(email),
                    ),
                  ),
                if (origin != null)
                  Text(
                    origin,
                    key: const Key('ticket-requester-origin'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Unverified extends StatelessWidget {
  const _Unverified({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AwSpace.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.gpp_maybe_outlined,
            size: 18,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: AwSpace.x2),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({
    required this.comment,
    required this.dateFormat,
    this.unverified = false,
  });

  final TicketCommentRecord comment;
  final String dateFormat;

  /// EE-254: arrived as mail claiming a colleague's address it could not prove.
  final bool unverified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key('ticket-comment-${comment.id}'),
      // The tint is the first of the three signals; the icon and the word
      // below are the other two. One of them is enough for anybody, and
      // together they are enough for everybody. `surfaceContainerHighest` is
      // the theme's own "this is set apart" surface — a hand-mixed amber would
      // be a colour the contrast gate has never measured.
      color: comment.internal
          ? theme.colorScheme.surfaceContainerHighest
          : null,
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (comment.internal)
              Row(
                children: [
                  const Icon(Icons.lock_outline, size: 16),
                  const SizedBox(width: AwSpace.x1),
                  // Wraps rather than running off the card on a phone — the
                  // English label is 45 characters (found by EE-266's archive
                  // twin of this card).
                  Expanded(
                    child: Text(
                      'ee.tickets.internalNote'.tr(),
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            if (comment.internal) const SizedBox(height: AwSpace.x2),
            if (unverified) ...[
              _Unverified(
                key: Key('ticket-comment-unverified-${comment.id}'),
                text: 'ee.tickets.senderUnverifiedShort'.tr(),
              ),
              const SizedBox(height: AwSpace.x2),
            ],
            Text(comment.body, style: theme.textTheme.bodyMedium),
            if (comment.createdAt != null) ...[
              const SizedBox(height: AwSpace.x1),
              Text(
                awFormatDateTime(comment.createdAt!, format: dateFormat),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
