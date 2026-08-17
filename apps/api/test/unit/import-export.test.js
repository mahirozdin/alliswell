import { describe, it, expect, beforeEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';

/**
 * OPH-266 — bulk import/export, issue #3's acceptance test.
 *
 * The assertions that matter: an imported note is indistinguishable from a
 * typed one (domain layer, sync revision, searchable), partial success is
 * reported instead of hidden, an export round-trips through import, and a key
 * from OPH-264 can drive the whole thing.
 */

let app;
let tables;
let owner;

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'bulk@example.com' });
});

const url = (path) => `/api/v1/workspaces/${owner.workspace.id}/${path}`;

async function post(path, payload, headers = owner.headers) {
  return app.inject({ method: 'POST', url: url(path), headers, payload });
}

describe('import: notes', () => {
  it('creates real notes: markdown-canonical, searchable, synced', async () => {
    const res = await post('import/notes', {
      notes: [
        { title: 'Işık faturası', contentMarkdown: '# Ödendi\n\nAğustos ayı' },
        { title: 'İkinci not', contentMarkdown: 'gövde', isPinned: true },
      ],
    });
    expect(res.statusCode).toBe(200);
    expect(res.json().created).toHaveLength(2);
    expect(res.json().errors).toEqual([]);

    const [first] = res.json().created;
    const row = tables.notes.find((n) => n.id === first);
    expect(row.content_format).toBe('markdown');
    // The OPH-261 repair holds for imports too: the search column is derived,
    // so an imported note can actually be found.
    expect(row.plain_text).toContain('Ağustos ayı');
    expect(
      tables.sync_revisions.some((r) => r.entity_id === first && r.entity_type === 'note'),
    ).toBe(true);

    // Found by the same `?q=` a typed note answers to — the proof that
    // "imported" is not a second class of row.
    const found = await app.inject({
      method: 'GET',
      url: `${url('notes')}?q=${encodeURIComponent('Ağustos')}`,
      headers: owner.headers,
    });
    expect(found.json().items.map((n) => n.id)).toContain(first);
  });

  it('reports the item that failed and imports the rest', async () => {
    const res = await post('import/notes', {
      notes: [
        { title: 'Sağlam' },
        { title: 'Ölü projeye', projectId: '01PROJECTGONE0000000000000' },
        { title: 'Sonraki de geçmeli' },
      ],
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    // 2 of 3 landed — and the failure names its index AND its reason, so the
    // caller can fix that one line and retry it alone.
    expect(body.created).toHaveLength(2);
    expect(body.errors).toEqual([
      { index: 1, code: 'NOTE_INVALID_PROJECT', message: expect.any(String) },
    ]);
    expect(tables.notes.filter((n) => n.title === 'Ölü projeye')).toHaveLength(0);
    expect(tables.notes.map((n) => n.title)).toContain('Sonraki de geçmeli');
  });

  it('attaches tags, and a bad tag is the note’s own error', async () => {
    const tag = await app
      .inject({
        method: 'POST',
        url: url('tags'),
        headers: owner.headers,
        payload: { name: 'arşiv' },
      })
      .then((r) => r.json());

    const res = await post('import/notes', {
      notes: [
        { title: 'Etiketli', tagIds: [tag.id] },
        { title: 'Yanlış etiket', tagIds: ['01TAGDOESNOTEXIST000000000'] },
      ],
    });
    const body = res.json();
    expect(tables.note_tags.filter((t) => t.note_id === body.created[0])).toHaveLength(1);
    expect(body.errors[0].index).toBe(1);
    expect(body.errors[0].code).toBe('NOTE_TAG_NOT_FOUND');
  });

  it('refuses a batch bigger than the cap, whole', async () => {
    const res = await post('import/notes', {
      notes: Array.from({ length: 501 }, (_, i) => ({ title: `Not ${i}` })),
    });
    expect(res.statusCode).toBe(400);
    expect(tables.notes).toHaveLength(0);
  });
});

describe('import: tasks', () => {
  it('goes through createTask — alarms and all', async () => {
    const dueAt = new Date(Date.now() + 3600000).toISOString();
    const res = await post('import/tasks', {
      tasks: [
        { title: 'Acil iş', dueAt, isUrgent: true, priority: 'high' },
        { title: 'Sıradan iş' },
      ],
    });
    expect(res.statusCode).toBe(200);
    const [urgent] = res.json().created;

    const row = tables.tasks.find((t) => t.id === urgent);
    expect(row.priority).toBe('high');
    // Urgent + a due time means a real alarm, because the import calls the
    // same domain function every other surface does.
    expect(Boolean(row.requires_acknowledgement)).toBe(true);
    expect(tables.reminders.filter((r) => r.task_id === urgent)).toHaveLength(1);
  });

  it('an unknown project fails only its own row', async () => {
    const res = await post('import/tasks', {
      tasks: [{ title: 'İyi' }, { title: 'Kötü', projectId: '01PROJECTGONE0000000000000' }],
    });
    expect(res.json().created).toHaveLength(1);
    expect(res.json().errors[0].code).toBe('TASK_INVALID_PROJECT');
  });
});

describe('export: notes', () => {
  it('exports the whole note — both canonical fields, links and tags', async () => {
    const project = await app
      .inject({
        method: 'POST',
        url: url('projects'),
        headers: owner.headers,
        payload: { name: 'Ev' },
      })
      .then((r) => r.json());
    const task = await app
      .inject({
        method: 'POST',
        url: url('tasks'),
        headers: owner.headers,
        payload: { title: 'Bağlı görev' },
      })
      .then((r) => r.json());
    const note = await app
      .inject({
        method: 'POST',
        url: url('notes'),
        headers: owner.headers,
        payload: {
          title: 'Tam not',
          contentFormat: 'markdown',
          contentMarkdown: '# Başlık\n\ngövde',
          projectId: project.id,
        },
      })
      .then((r) => r.json());
    await app.inject({
      method: 'POST',
      url: `/api/v1/notes/${note.id}/links`,
      headers: owner.headers,
      payload: { entityType: 'task', entityId: task.id },
    });

    const res = await app.inject({
      method: 'GET',
      url: url('export/notes'),
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(200);
    const exported = res.json().notes.find((n) => n.id === note.id);
    expect(exported.contentFormat).toBe('markdown');
    expect(exported.contentMarkdown).toContain('gövde');
    expect(exported.projectId).toBe(project.id);
    expect(exported.links).toEqual([{ entityType: 'task', entityId: task.id }]);
    expect(res.json().nextCursor).toBeNull();
  });

  it('paginates, and archived notes are part of "everything"', async () => {
    for (let i = 0; i < 3; i += 1) {
      await app.inject({
        method: 'POST',
        url: url('notes'),
        headers: owner.headers,
        payload: { title: `Not ${i}` },
      });
    }
    const archived = await app
      .inject({
        method: 'POST',
        url: url('notes'),
        headers: owner.headers,
        payload: { title: 'Arşivlenmiş' },
      })
      .then((r) => r.json());
    await app.inject({
      method: 'PATCH',
      url: `/api/v1/notes/${archived.id}`,
      headers: owner.headers,
      payload: { isArchived: true },
    });

    const all = await app.inject({
      method: 'GET',
      url: url('export/notes'),
      headers: owner.headers,
    });
    expect(all.json().notes.map((n) => n.title)).toContain('Arşivlenmiş');

    const page = await app.inject({
      method: 'GET',
      url: `${url('export/notes')}?limit=2`,
      headers: owner.headers,
    });
    expect(page.json().notes).toHaveLength(2);
    const next = page.json().nextCursor;
    expect(next).not.toBeNull();
    const rest = await app.inject({
      method: 'GET',
      url: `${url('export/notes')}?limit=2&cursor=${next}`,
      headers: owner.headers,
    });
    const seen = [...page.json().notes, ...rest.json().notes].map((n) => n.id);
    expect(new Set(seen).size).toBe(seen.length); // no row served twice
  });

  it('another workspace’s member gets nothing but a 403', async () => {
    const outsider = await registerUser(app, { email: 'bulk-outsider@example.com' });
    const res = await app.inject({
      method: 'GET',
      url: url('export/notes'),
      headers: outsider.headers,
    });
    expect(res.statusCode).toBe(403);
  });
});

describe('the round trip (issue #3’s acceptance test)', () => {
  it('export → import reproduces the notes in a fresh shape', async () => {
    await post('import/notes', {
      notes: [
        { title: 'Bir', contentMarkdown: 'birinci gövde' },
        { title: 'İki', contentMarkdown: 'ikinci gövde', isPinned: true },
      ],
    });

    const exported = await app
      .inject({ method: 'GET', url: url('export/notes'), headers: owner.headers })
      .then((r) => r.json());

    // Feed the export straight back in — the shape a script would keep.
    const reimport = await post('import/notes', {
      notes: exported.notes.map((n) => ({
        title: n.title,
        contentMarkdown: n.contentMarkdown ?? '',
        isPinned: n.isPinned,
      })),
    });
    expect(reimport.json().errors).toEqual([]);
    expect(reimport.json().created).toHaveLength(2);

    const after = await app
      .inject({ method: 'GET', url: url('export/notes'), headers: owner.headers })
      .then((r) => r.json());
    expect(after.notes).toHaveLength(4);
    expect(after.notes.filter((n) => n.title === 'Bir')).toHaveLength(2);
    expect(after.notes.filter((n) => n.isPinned)).toHaveLength(2);
  });

  it('an API key drives the whole thing — that is what keys are for', async () => {
    const key = await app
      .inject({
        method: 'POST',
        url: url('api-keys'),
        headers: owner.headers,
        payload: { name: 'Taşıma script’i' },
      })
      .then((r) => r.json());
    const keyHeaders = { authorization: `Bearer ${key.key}` };

    const imported = await post(
      'import/tasks',
      { tasks: [{ title: 'Script’in taşıdığı iş' }] },
      keyHeaders,
    );
    expect(imported.statusCode).toBe(200);
    expect(imported.json().created).toHaveLength(1);

    const exported = await app.inject({
      method: 'GET',
      url: url('export/notes'),
      headers: keyHeaders,
    });
    expect(exported.statusCode).toBe(200);
  });
});
