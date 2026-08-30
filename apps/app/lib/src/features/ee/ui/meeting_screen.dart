import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_messages.dart';
import '../../../i18n/i18n.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/status_views.dart';
import '../data/meeting_models.dart';
import '../meetings_providers.dart';

/// One meeting: what it decided, and who said what (EE-114/EE-115).
///
/// ── A NAME IS A MAP, NOT A REWRITE ───────────────────────────────────────
///
/// The diarizer answers "A" and "B". Naming B "Ayşe" has to reach every line
/// she said — 1 800 of them in an hour — and it does so because the screen
/// never renders `segment.speaker` directly: it renders
/// `detail.displayName(segment.speaker)`. One function, one lookup, and a
/// rename that arrives everywhere at once without touching the transcript.
/// The vendor's labels stay underneath, which is what makes a wrong name
/// correctable and a re-run comparable.
///
/// ── TIME IS THE LINK BETWEEN TEXT AND AUDIO ──────────────────────────────
///
/// Every segment carries its start, and the row shows it. That is the "ses↔metin
/// konum bağı" the task asks for in the form the data actually supports today:
/// the reader can find the moment in the recording. In-app playback is NOT
/// here, and the reason is written rather than forgotten — the recording is
/// reachable (`GET …/meetings/:id/audio` mints a short-lived link) but a
/// player is a surface of its own (transport, buffering, a position stream
/// driving highlight), and shipping a seek callback nothing calls would be an
/// affordance that lies. EE-115's remaining half is named in TASKS.
///
/// ── COLOUR IS A MARK, MEANING IS A WORD (EE-097's rule) ─────────────────
///
/// State is an icon in a state colour PLUS its own label, and `transcribed` is
/// drawn as WAITING rather than done: the words are safe and the note has not
/// been written, and a screen that called that finished would be telling
/// somebody their meeting is ready when half of it is missing.
class EeMeetingScreen extends ConsumerWidget {
  const EeMeetingScreen({required this.meetingId, super.key});
  final String meetingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(eeMeetingProvider(meetingId));

    return Scaffold(
      appBar: AppBar(title: Text('ee.meeting.title'.tr())),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AwErrorState(
          message: localizedError(error),
          onRetry: () => ref.invalidate(eeMeetingProvider(meetingId)),
        ),
        data: (value) {
          if (value == null) {
            return AwEmptyState(
              icon: Icons.mic_off_outlined,
              title: 'ee.meeting.unavailable'.tr(),
              message: 'ee.meeting.unavailableBody'.tr(),
            );
          }
          return _Body(meetingId: meetingId, detail: value);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.meetingId, required this.detail});
  final String meetingId;
  final EeMeetingDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transcript = detail.transcript;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _StatusCard(summary: detail.summary),
        if (detail.summary.summary != null) ...[
          _SectionTitle('ee.meeting.summary'.tr()),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              detail.summary.summary!,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
        if (detail.decisions.isNotEmpty) ...[
          _SectionTitle('ee.meeting.decisions'.tr()),
          for (final (index, decision) in detail.decisions.indexed)
            _DecisionRow(
              meetingId: meetingId,
              index: index,
              decision: decision,
              detail: detail,
            ),
        ],
        if (detail.ideas.isNotEmpty) ...[
          _SectionTitle('ee.meeting.ideas'.tr()),
          for (final (index, idea) in detail.ideas.indexed)
            ListTile(
              key: Key('meeting-idea-$index'),
              leading: const Icon(Icons.lightbulb_outline),
              title: Text(idea),
            ),
        ],
        if (transcript != null && transcript.segments.isNotEmpty) ...[
          _SectionTitle('ee.meeting.transcript'.tr()),
          _SpeakerRail(
            meetingId: meetingId,
            detail: detail,
            transcript: transcript,
          ),
          for (final (index, segment) in transcript.segments.indexed)
            _SegmentRow(
              index: index,
              segment: segment,
              speakerName: detail.displayName(segment.speaker),
            ),
        ],
      ],
    );
  }
}

/// A decision, and the one button that turns it into work (EE-116).
///
/// The button never disappears. What it CREATES changes with the licence — a
/// service-desk request where the instance has one, a task where it does not —
/// and the server decides that, not this screen: an app holding a stale idea of
/// this instance's entitlements would offer the wrong thing on exactly the day
/// it matters. So the label says "create a record" until there IS one, and then
/// says which kind it turned out to be.
class _DecisionRow extends ConsumerStatefulWidget {
  const _DecisionRow({
    required this.meetingId,
    required this.index,
    required this.decision,
    required this.detail,
  });
  final String meetingId;
  final int index;
  final EeMeetingDecision decision;
  final EeMeetingDetail detail;

  @override
  ConsumerState<_DecisionRow> createState() => _DecisionRowState();
}

class _DecisionRowState extends ConsumerState<_DecisionRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final decision = widget.decision;
    final record = decision.record;

    return ListTile(
      key: Key('meeting-decision-${widget.index}'),
      leading: const Icon(Icons.check_circle_outline),
      title: Text(decision.text),
      subtitle: decision.owner == null
          ? null
          // The owner is a speaker LABEL, so it goes through the same lookup
          // the transcript does — naming a speaker renames them here too,
          // which is the whole point of one map.
          : Text(widget.detail.displayName(decision.owner!)),
      trailing: record != null
          // Already work. A word, not another button: pressing it again would
          // be answered with the same record, and offering that is offering a
          // no-op dressed as an action.
          ? Text(
              key: Key('meeting-decision-record-${widget.index}'),
              record.isTicket
                  ? 'ee.meeting.isTicket'.tr()
                  : 'ee.meeting.isTask'.tr(),
              style: Theme.of(context).textTheme.labelSmall,
            )
          : IconButton(
              key: Key('meeting-decision-create-${widget.index}'),
              tooltip: 'ee.meeting.createRecord'.tr(),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_task),
              onPressed: _busy ? null : _create,
            ),
    );
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final record = await createDecisionRecord(
        ref,
        widget.meetingId,
        widget.index,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            record.isTicket
                ? 'ee.meeting.ticketCreated'.tr()
                : 'ee.meeting.taskCreated'.tr(),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(localizedError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// The pipeline's state, said in a word as well as drawn in a colour.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.summary});
  final EeMeetingSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.awTokens;

    final (icon, colour) = switch (summary.status) {
      EeMeetingStatus.ready => (Icons.check_circle_outline, tokens.success),
      EeMeetingStatus.failed => (Icons.error_outline, theme.colorScheme.error),
      // `transcribed` is WAITING, not done — the note is still missing.
      EeMeetingStatus.transcribed => (Icons.hourglass_bottom, tokens.warning),
      _ => (Icons.autorenew, theme.disabledColor),
    };

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: ListTile(
        leading: Icon(
          icon,
          key: const Key('meeting-status-mark'),
          color: colour,
        ),
        title: Text(summary.title ?? 'ee.meeting.untitled'.tr()),
        subtitle: Text(
          [
            // The WORD, in body colour.
            'ee.meeting.status.${summary.status.name}'.tr(),
            if (summary.durationMs != null) _clock(summary.durationMs!),
          ].join(' · '),
          style: theme.textTheme.bodySmall,
        ),
        isThreeLine: summary.failureMessage != null,
        trailing: summary.status.isWorking
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
      ),
    );
  }
}

/// Who spoke, and the chance to say who they are.
///
/// The rail sits ABOVE the transcript rather than behind a menu, because the
/// question "who is B?" is the first one a reader has and the answer improves
/// every line below it.
class _SpeakerRail extends ConsumerWidget {
  const _SpeakerRail({
    required this.meetingId,
    required this.detail,
    required this.transcript,
  });
  final String meetingId;
  final EeMeetingDetail detail;
  final EeTranscript transcript;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final label in transcript.speakers)
            ActionChip(
              key: Key('meeting-speaker-$label'),
              avatar: const Icon(Icons.person_outline, size: 18),
              label: Text(detail.displayName(label)),
              onPressed: () => _rename(context, ref, label),
            ),
        ],
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    String label,
  ) async {
    final controller = TextEditingController(
      text: detail.speakerNames[label] ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ee.meeting.nameSpeaker'.tr(args: {'label': label})),
        content: TextField(
          key: const Key('meeting-speaker-field'),
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'ee.meeting.speakerName'.tr(),
            helperText: 'ee.meeting.speakerNameHelp'.tr(),
            helperMaxLines: 2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            key: const Key('meeting-speaker-save'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('common.save'.tr()),
          ),
        ],
      ),
    );
    final name = controller.text.trim();
    controller.dispose();
    if (saved != true) return;

    // The WHOLE map, not one entry: this screen shows every speaker, so it is
    // stating the complete answer. An empty name drops that speaker's name,
    // which the server treats as "forget it".
    await nameMeetingSpeakers(ref, meetingId, {
      ...detail.speakerNames,
      label: name,
    });
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.index,
    required this.segment,
    required this.speakerName,
  });
  final int index;
  final EeTranscriptSegment segment;
  final String speakerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // Keyed by INDEX, not by speaker: 1 800 rows repeat four names between
      // them, and a finder that matched "the row where B speaks" would match
      // 450 of them. E11 lost three CI runs to exactly that shape of finder.
      key: Key('meeting-segment-$index'),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                speakerName,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              // The position in the recording. Monospace-ish alignment is not
              // worth a font here; what matters is that it is findable.
              Text(
                _clock(segment.startMs),
                key: Key('meeting-time-$index'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(segment.text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// `m:ss`, or `h:mm:ss` past an hour. Not localized: a clock reading is digits
/// and a colon in every language this product speaks.
String _clock(int ms) {
  final total = Duration(milliseconds: ms);
  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60);
  final seconds = total.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  return '$minutes:$seconds';
}
