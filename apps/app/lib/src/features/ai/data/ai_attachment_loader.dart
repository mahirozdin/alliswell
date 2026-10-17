import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../sync/providers.dart';
import '../../files/providers.dart';
import '../../notes/providers.dart';
import '../../tasks/providers.dart';
import 'ai_attachments.dart';

/// Fetches the bytes behind a presigned GET. Plain Dio on purpose: the API
/// client's Authorization header would break the signature (LESSONS
/// files-storage). A seam so widget tests can hand back canned bytes.
typedef AiFileBytesFetcher = Future<List<int>> Function(String url);

final aiFileBytesFetcherProvider = Provider<AiFileBytesFetcher>(
  (ref) => (url) async {
    final response = await Dio()
        .get<List<int>>(url, options: Options(responseType: ResponseType.bytes))
        .timeout(const Duration(seconds: 20));
    return response.data ?? const <int>[];
  },
);

final aiAttachmentLoaderProvider = Provider<AiAttachmentLoader>(
  AiAttachmentLoader.new,
);

/// The impure half of "@" attachments (OPH-377, ADR-0058): reads a picked
/// note, task or project from the replica, or a text file's bytes through the
/// existing presigned-GET path, and returns DECODED TEXT. The presigned URL
/// never leaves [load] — it is not stored, returned or logged.
class AiAttachmentLoader {
  AiAttachmentLoader(this._ref);

  final Ref _ref;

  Future<AiAttachment> load(AiAttachmentRef ref) async {
    try {
      return switch (ref.kind) {
        AiAttachmentKind.note => await _note(ref),
        AiAttachmentKind.task => await _task(ref),
        AiAttachmentKind.project => await _project(ref),
        AiAttachmentKind.file => await _file(ref),
      };
    } on Object {
      // Offline, a timeout, a store refusal: one honest answer.
      return AiAttachment.refused(ref, AiAttachmentRefusal.unavailable);
    }
  }

  Future<AiAttachment> _note(AiAttachmentRef ref) async {
    final note = await _ref.read(noteStoreProvider).detailOnce(ref.id);
    if (note == null) {
      return AiAttachment.refused(ref, AiAttachmentRefusal.unavailable);
    }
    var body = note.contentMarkdown ?? '';
    if (body.trim().isEmpty) {
      // A pre-markdown note (ADR-0033) still has its plain text.
      final db = _ref.read(databaseProvider);
      final row = await (db.select(
        db.notes,
      )..where((n) => n.id.equals(ref.id))).getSingleOrNull();
      body = row?.plainText ?? '';
    }
    return AiAttachment.ready(ref, aiNoteText(note.title, body));
  }

  Future<AiAttachment> _task(AiAttachmentRef ref) async {
    final task = await _ref.read(taskStoreProvider).detailOnce(ref.id);
    if (task == null) {
      return AiAttachment.refused(ref, AiAttachmentRefusal.unavailable);
    }
    String? projectName;
    if (task.projectId != null) {
      final db = _ref.read(databaseProvider);
      final project = await (db.select(
        db.projects,
      )..where((p) => p.id.equals(task.projectId!))).getSingleOrNull();
      projectName = project?.name;
    }
    final when = task.startAt;
    return AiAttachment.ready(
      ref,
      aiTaskText(
        title: task.title,
        status: task.status,
        priority: task.priority,
        dueLabel: task.dueAt == null ? null : aiDueLabel(task.dueAt!),
        whenLabel: when == null ? null : aiDueLabel(when).substring(0, 10),
        minutes: task.estimatedMinutes,
        projectName: projectName,
        description: task.description,
        checklist: [for (final c in task.checklist) (c.title, c.isDone)],
      ),
    );
  }

  Future<AiAttachment> _project(AiAttachmentRef ref) async {
    final db = _ref.read(databaseProvider);
    final project = await (db.select(
      db.projects,
    )..where((p) => p.id.equals(ref.id))).getSingleOrNull();
    if (project == null) {
      return AiAttachment.refused(ref, AiAttachmentRefusal.unavailable);
    }
    final tasks =
        await (db.select(db.tasks)
              ..where(
                (t) =>
                    t.projectId.equals(ref.id) &
                    t.status.isIn(kPlanningStatuses),
              )
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.dueAt,
                  mode: OrderingMode.asc,
                  nulls: NullsOrder.last,
                ),
                (t) => OrderingTerm.asc(t.title),
              ]))
            .get();
    return AiAttachment.ready(
      ref,
      aiProjectText(
        name: project.name,
        description: project.description,
        openTasks: [
          for (final t in tasks)
            (t.title, t.dueAt == null ? null : aiDueLabel(t.dueAt!)),
        ],
      ),
    );
  }

  Future<AiAttachment> _file(AiAttachmentRef ref) async {
    final file = await _ref.read(fileStoreProvider).byId(ref.id);
    if (file == null) {
      return AiAttachment.refused(ref, AiAttachmentRefusal.unavailable);
    }
    if (!aiFileIsTextLike(file.name, file.mime)) {
      return AiAttachment.refused(ref, AiAttachmentRefusal.notText);
    }
    if (file.sizeBytes > kAiAttachFileMaxBytes) {
      return AiAttachment.refused(ref, AiAttachmentRefusal.tooLarge);
    }
    final url = await _ref.read(fileUrlCacheProvider).urlFor(file.id);
    if (url == null) {
      return AiAttachment.refused(ref, AiAttachmentRefusal.unavailable);
    }
    final bytes = await _ref.read(aiFileBytesFetcherProvider)(url);
    if (bytes.length > kAiAttachFileMaxBytes) {
      return AiAttachment.refused(ref, AiAttachmentRefusal.tooLarge);
    }
    if (aiLooksBinary(bytes)) {
      return AiAttachment.refused(ref, AiAttachmentRefusal.notText);
    }
    final text = aiDecodeText(bytes);
    if (text.trim().isEmpty) {
      return AiAttachment.refused(ref, AiAttachmentRefusal.empty);
    }
    return AiAttachment.ready(ref, aiFileText(file.name, text));
  }
}
