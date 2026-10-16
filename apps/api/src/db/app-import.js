import { newId } from '../lib/ids.js';
import { slugify } from '../lib/slug.js';
import { externalKey, fold, parseImport } from '../lib/importers/index.js';
import { isValidTimeZone } from '../lib/importers/dates.js';
import { importError } from '../lib/importers/errors.js';
import { createProject } from './projects.js';
import { createTag } from './tags.js';
import { addChecklistItem, createTask } from './tasks.js';
import { createTaskSeries } from './task-series.js';
import { createNote } from './notes.js';
import { transactionWithRetry } from './tx.js';

/**
 * Moving in from Todoist or TickTick (OPH-371, ADR-0052).
 *
 * `runAppImport` is the preview AND the import (DESIGN §37 I1): the same
 * parse, the same plan, the same counts; `dryRun` only decides whether the
 * plan is written. Writes go through the domain layer one item at a time
 * (import-export.js rule 1), so an imported task is an ordinary task — same
 * asserts, same sync revision, same reminder reconcile — and every device
 * converges through /sync/pull with no import-aware client code.
 *
 * Idempotency: every item has a row in `import_ledger`, inserted FIRST in the
 * item's own transaction. A key already there is skipped — even when the user
 * has deleted the task since: a re-import never resurrects anything. Two
 * identical requests at once meet on the unique index and one of them skips.
 *
 * Batching: at most `maxItems` new items per call; the response says how many
 * remain and the caller calls again, so a big file never meets a proxy
 * timeout and a retry after a failure is safe.
 *
 * Imported tasks never arm urgent alarms (isUrgent false, no acknowledgement):
 * moving 500 tasks in must not ring 500 times.
 */

const LEDGER = 'import_ledger';
const EXAMPLES_PER_WARNING = 5;
const LIST_CAP = 200;
const CHUNK = 1000;

const PRIORITY_MAPPING = {
  todoist: [
    { from: 'p1', to: 'high' },
    { from: 'p2', to: 'medium' },
    { from: 'p3', to: 'low' },
    { from: 'p4', to: 'none' },
  ],
  ticktick: [
    { from: 'high', to: 'high' },
    { from: 'medium', to: 'medium' },
    { from: 'low', to: 'low' },
    { from: 'none', to: 'none' },
  ],
};

function isLedgerClash(err) {
  return err?.code === 'ER_DUP_ENTRY' && String(err.message).includes('uq_import_ledger_key');
}

async function ledgerRows(app, { workspaceId, source, keys }) {
  const rows = [];
  for (let i = 0; i < keys.length; i += CHUNK) {
    const chunk = keys.slice(i, i + CHUNK);
    rows.push(
      ...(await app
        .db(LEDGER)
        .where({ workspace_id: workspaceId, source })
        .whereIn('external_key', chunk)
        .select()),
    );
  }
  return new Map(rows.map((r) => [r.external_key, r]));
}

function groupWarnings(warnings) {
  const byCode = new Map();
  for (const w of warnings) {
    const group = byCode.get(w.code) ?? { code: w.code, count: 0, examples: [] };
    group.count += 1;
    if (group.examples.length < EXAMPLES_PER_WARNING) {
      group.examples.push({
        file: w.file ?? null,
        row: w.row ?? null,
        title: w.title ?? null,
        value: w.value == null ? null : String(w.value).slice(0, 200),
      });
    }
    byCode.set(w.code, group);
  }
  return [...byCode.values()];
}

/** The user's own timezone — what an import falls back to (LESSONS calendar). */
async function profileTimezone(app, userId) {
  const user = await app.db('users').where({ id: userId }).first('timezone');
  return user?.timezone ?? 'Europe/Istanbul';
}

/**
 * @param {object} app
 * @param {{workspaceId:string, userId:string, source:'todoist'|'ticktick',
 *   files:{name:string, content:string}[], options?:object, dryRun?:boolean,
 *   now?: Date, log?: object}} input
 */
export async function runAppImport(
  app,
  { workspaceId, userId, source, files, options = {}, dryRun = false, now = new Date(), log },
) {
  const tz = options.timezone ?? (await profileTimezone(app, userId));
  if (!isValidTimeZone(tz)) {
    throw importError(422, 'IMPORT_INVALID_TIMEZONE', `Unknown timezone: ${tz}`);
  }
  const ctx = {
    tz,
    now,
    defaultTaskTime: options.defaultTaskTime ?? '23:59',
    locale: options.locale ?? 'en',
  };
  const includeCompleted = options.includeCompleted ?? false;
  const maxItems = options.maxItems ?? 250;

  const parsed = parseImport(source, files, ctx);
  if (parsed.items.length === 0) {
    throw importError(422, 'IMPORT_EMPTY', 'There is nothing to import in this file');
  }

  // ── Read phase: one batched query each ──
  for (const item of parsed.items) item.externalKey = externalKey(item.key);
  const ledger = await ledgerRows(app, {
    workspaceId,
    source,
    keys: parsed.items.map((i) => i.externalKey),
  });

  const already = parsed.items.filter((i) => ledger.has(i.externalKey));
  const fresh = parsed.items.filter((i) => !ledger.has(i.externalKey));
  const completedFresh = fresh.filter((i) => i.completed);
  const eligible = fresh.filter((i) => includeCompleted || !i.completed);

  const liveProjects = await app
    .db('projects')
    .where({ workspace_id: workspaceId })
    .whereNull('deleted_at')
    .select();
  const projectByName = new Map();
  for (const p of liveProjects) {
    if (!projectByName.has(fold(p.name))) projectByName.set(fold(p.name), p);
  }
  const allTags = await app.db('tags').where({ workspace_id: workspaceId }).select();
  const tagBySlug = new Map(allTags.map((t) => [t.slug, t]));

  const projectsByKey = new Map(parsed.projects.map((p) => [p.key, p]));
  const neededProjectKeys = [...new Set(eligible.map((i) => i.projectKey).filter(Boolean))];
  const projectPlan = neededProjectKeys.map((key) => {
    const { name } = projectsByKey.get(key);
    const existing = projectByName.get(fold(name));
    const tasks = eligible.filter((i) => i.projectKey === key).length;
    return { key, name, existing: existing ?? null, tasks };
  });

  const tagNames = new Map(); // slug → display name (first spelling wins)
  for (const item of eligible) {
    for (const name of item.tagNames ?? []) {
      const clean = name.trim().slice(0, 64);
      if (!clean) continue;
      const slug = slugify(clean, 'tag');
      if (!tagNames.has(slug)) tagNames.set(slug, clean);
    }
  }
  const tagPlan = [...tagNames.entries()].map(([slug, name]) => {
    const row = tagBySlug.get(slug);
    return { slug, name, existing: row && row.deleted_at == null ? row : null, held: Boolean(row) };
  });

  const google = await app
    .db('calendar_accounts')
    .where({ workspace_id: workspaceId, provider: 'google', status: 'active' })
    .whereNull('deleted_at')
    .first('id');

  // A series template has no checklist: its lines go into the description,
  // counted and said aloud (DESIGN §37 I2).
  for (const item of eligible) {
    if (item.kind === 'task' && item.recurrence && item.checklist.length > 0) {
      parsed.warnings.push({
        code: 'IMPORT_RECURRING_CHECKLIST_MOVED',
        file: item.file,
        row: item.row,
        title: item.title,
        value: String(item.checklist.length),
      });
    }
  }

  const tasksCount = eligible.filter((i) => i.kind === 'task' && !i.recurrence).length;
  const seriesCount = eligible.filter((i) => i.kind === 'task' && i.recurrence).length;
  const summary = {
    source,
    dryRun,
    timezone: tz,
    total: eligible.length,
    projects: {
      new: projectPlan.filter((p) => !p.existing).length,
      existing: projectPlan.filter((p) => p.existing).length,
    },
    tags: {
      new: tagPlan.filter((t) => !t.existing).length,
      existing: tagPlan.filter((t) => t.existing).length,
    },
    tasks: tasksCount,
    series: seriesCount,
    checklistItems: eligible
      .filter((i) => i.kind === 'task' && !i.recurrence)
      .reduce((n, i) => n + i.checklist.length, 0),
    notes: eligible.filter((i) => i.kind === 'note').length,
    completed: {
      included: includeCompleted ? completedFresh.length : 0,
      skipped: includeCompleted ? 0 : completedFresh.length,
    },
    alreadyImported: already.length,
    googleMirror: {
      connected: Boolean(google),
      // Every task mirrors (lib/mirror.js: not a setting); undated ones land
      // on the day they are created — the preview says so instead of hiding it.
      tasks: google ? tasksCount : 0,
      undated: google
        ? eligible.filter((i) => i.kind === 'task' && !i.recurrence && !i.dueAt).length
        : 0,
    },
    projectList: projectPlan
      .slice(0, LIST_CAP)
      .map((p) => ({ name: p.name, existing: Boolean(p.existing), tasks: p.tasks })),
    tagList: tagPlan
      .slice(0, LIST_CAP)
      .map((t) => ({ name: t.name, existing: Boolean(t.existing) })),
    mapping: {
      priority: PRIORITY_MAPPING[source],
      sectionsAs: 'tags',
      subItemsAs: 'checklist',
    },
    warnings: groupWarnings(parsed.warnings),
    created: { projects: 0, tags: 0, tasks: 0, checklistItems: 0, notes: 0, series: 0 },
    errors: [],
    remaining: eligible.length,
  };

  if (dryRun) return summary;

  // ── Write phase ──
  const created = summary.created;

  // Projects: reuse a live one with the same (folded) name; otherwise create
  // it with its ledger row, ledger FIRST so a parallel request reuses ours.
  const projectIdByKey = new Map();
  for (const plan of projectPlan) {
    if (plan.existing) {
      projectIdByKey.set(plan.key, plan.existing.id);
      continue;
    }
    const key = externalKey(plan.key);
    try {
      const id = await transactionWithRetry(app.db, async (trx) => {
        const ledgerId = newId();
        await trx(LEDGER).insert({
          id: ledgerId,
          workspace_id: workspaceId,
          source,
          external_key: key,
          entity_type: 'project',
          created_by: userId,
        });
        const projectId = await createProject(app, {
          workspaceId,
          userId,
          body: { name: plan.name },
          toRowPatch: (b) => ({ name: b.name }),
          trx,
        });
        await trx(LEDGER).where({ id: ledgerId }).update({ entity_id: projectId });
        return projectId;
      });
      projectIdByKey.set(plan.key, id);
      created.projects += 1;
    } catch (err) {
      if (!isLedgerClash(err)) throw err;
      // Somebody created it first — or an earlier import did and the user has
      // since renamed or deleted it. Reuse it when it is alive; otherwise its
      // items go to no project rather than resurrecting a deleted one.
      const row = await app
        .db(LEDGER)
        .where({ workspace_id: workspaceId, source, external_key: key })
        .first();
      const live = row?.entity_id
        ? await app.db('projects').where({ id: row.entity_id }).whereNull('deleted_at').first('id')
        : null;
      projectIdByKey.set(plan.key, live?.id ?? null);
    }
  }

  // Tags: reuse by slug; a slug held only by a deleted tag gets a suffix.
  const tagIdBySlug = new Map();
  for (const plan of tagPlan) {
    if (plan.existing) {
      tagIdBySlug.set(plan.slug, plan.existing.id);
      continue;
    }
    const slug = plan.held
      ? `${plan.slug.slice(0, 40)}-${newId().slice(-6).toLowerCase()}`
      : undefined;
    try {
      const id = await createTag(app, { workspaceId, body: { name: plan.name }, slug });
      tagIdBySlug.set(plan.slug, id);
      created.tags += 1;
    } catch (err) {
      if (err?.code !== 'TAG_SLUG_TAKEN') throw err;
      const row = await app
        .db('tags')
        .where({ workspace_id: workspaceId, slug: plan.slug })
        .whereNull('deleted_at')
        .first();
      if (row) tagIdBySlug.set(plan.slug, row.id);
    }
  }
  const tagIdsOf = (item) => [
    ...new Set(
      (item.tagNames ?? [])
        .map((n) => n.trim().slice(0, 64))
        .filter(Boolean)
        .map((n) => tagIdBySlug.get(slugify(n, 'tag')))
        .filter(Boolean),
    ),
  ];

  const batch = eligible.slice(0, maxItems);
  let processed = 0;
  for (const item of batch) {
    const projectId = item.projectKey ? (projectIdByKey.get(item.projectKey) ?? null) : null;
    const tagIds = tagIdsOf(item);
    try {
      const counts = await transactionWithRetry(app.db, async (trx) => {
        const ledgerId = newId();
        const delta = { tasks: 0, checklistItems: 0, notes: 0, series: 0 };
        await trx(LEDGER).insert({
          id: ledgerId,
          workspace_id: workspaceId,
          source,
          external_key: item.externalKey,
          entity_type: item.kind === 'note' ? 'note' : item.recurrence ? 'task_series' : 'task',
          created_by: userId,
        });
        let entityId;
        if (item.kind === 'note') {
          entityId = await createNote(app, {
            workspaceId,
            userId,
            origin: 'import',
            body: {
              title: item.title,
              contentFormat: 'markdown',
              contentMarkdown: item.markdown ?? '',
              ...(projectId ? { projectId } : {}),
            },
            tagIds,
            trx,
          });
          delta.notes = 1;
        } else if (item.recurrence) {
          let description = item.description;
          if (item.checklist.length > 0) {
            const lines = item.checklist.map((c) => `- [${c.isDone ? 'x' : ' '}] ${c.title}`);
            description = [description, lines.join('\n')].filter(Boolean).join('\n\n');
          }
          const { stored } = await createTaskSeries(app, {
            workspaceId,
            userId,
            rule: item.recurrence.rule,
            template: {
              title: item.title,
              ...(description ? { description: description.slice(0, 60000) } : {}),
              ...(projectId ? { projectId } : {}),
              priority: item.priority,
              tagIds,
              isUrgent: false,
              requiresAcknowledgement: false,
              ...(item.estimatedMinutes ? { estimatedMinutes: item.estimatedMinutes } : {}),
              ...(item.remindMinutesBefore != null
                ? { remindMinutesBefore: Math.min(item.remindMinutesBefore, 43200) }
                : {}),
            },
            timezone: item.timezone ?? tz,
            anchorAt: item.anchorAt,
            trx,
            now,
          });
          entityId = stored.id;
          delta.series = 1;
        } else {
          entityId = await createTask(app, {
            workspaceId,
            userId,
            body: {
              title: item.title,
              ...(item.description ? { description: item.description } : {}),
              ...(projectId ? { projectId } : {}),
              status: item.completed ? 'completed' : 'open',
              priority: item.priority,
              isUrgent: false,
              requiresAcknowledgement: false,
              timezone: item.timezone ?? tz,
              ...(item.dueAt ? { dueAt: item.dueAt } : {}),
              ...(item.scheduledStartAt
                ? { scheduledStartAt: item.scheduledStartAt, scheduledEndAt: item.scheduledEndAt }
                : {}),
              ...(item.remindAt ? { remindAt: item.remindAt } : {}),
              ...(item.estimatedMinutes ? { estimatedMinutes: item.estimatedMinutes } : {}),
              tagIds,
            },
            completedAt: item.completedAt,
            trx,
          });
          delta.tasks = 1;
          if (item.checklist.length > 0) {
            const task = await trx('tasks').where({ id: entityId }).first();
            for (const [index, entry] of item.checklist.entries()) {
              await addChecklistItem(app, {
                task,
                title: entry.title,
                sortOrder: index,
                isDone: entry.isDone,
                trx,
              });
              delta.checklistItems += 1;
            }
          }
        }
        await trx(LEDGER).where({ id: ledgerId }).update({ entity_id: entityId });
        return delta;
      });
      for (const [k, v] of Object.entries(counts)) created[k] += v;
    } catch (err) {
      if (isLedgerClash(err)) {
        summary.alreadyImported += 1;
      } else if (err?.statusCode >= 400 && err.statusCode < 500 && err.code) {
        summary.errors.push({
          file: item.file,
          row: item.row,
          code: err.code,
          message: err.message,
        });
      } else {
        log?.error({ err: err?.message, file: item.file, row: item.row }, 'app import item failed');
        summary.errors.push({
          file: item.file,
          row: item.row,
          code: 'IMPORT_ITEM_FAILED',
          message: 'Could not import this item',
        });
      }
    }
    processed += 1;
  }
  summary.remaining = eligible.length - processed;
  return summary;
}
