import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { describe, it, expect, beforeEach } from 'vitest';
import { buildTestApp, registerUser } from '../helpers/authed.js';
import { fullDance, callTool } from '../helpers/mcpdance.js';

/**
 * OPH-218 (extended by OPH-226) — the red-team corpus against the MCP tools:
 * hostile content seeded as real workspace data must come back as DATA, never
 * trigger an action, and never mutate a table it wasn't asked to. The corpus
 * is shared with the app side (apps/app/test/fixtures/ai_redteam.json).
 */

const corpusPath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../../app/test/fixtures/ai_redteam.json',
);
const corpus = JSON.parse(readFileSync(corpusPath, 'utf8'));

let app;
let tables;
let owner;
let access;

beforeEach(async () => {
  ({ app, tables } = await buildTestApp());
  owner = await registerUser(app, { email: 'mcp-injection@example.com' });
  const { tokens } = await fullDance(app, { email: 'mcp-injection@example.com' });
  access = tokens.access_token;
});

function tableSnapshot() {
  return {
    tasks: tables.tasks.length,
    completed: tables.tasks.filter((t) => t.status === 'completed').length,
    deleted: tables.tasks.filter((t) => t.deleted_at).length,
    notes: tables.notes.length,
  };
}

describe('MCP tools resist injection', () => {
  const titleCases = corpus.cases.filter((c) => c.surface === 'title');
  const noteCases = corpus.cases.filter((c) => c.surface === 'note');

  it('hostile task titles round-trip as data — search returns them, nothing acts', async () => {
    for (const testCase of titleCases) {
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
        headers: owner.headers,
        payload: { title: testCase.text },
      });
    }
    const before = tableSnapshot();

    // A search whose results are full of imperative text must still be inert.
    const result = await callTool(app, access, 'search', { query: 'instructions' });
    expect(result.isError).toBeFalsy();
    // Output is schema-shaped: each result is a lean object, never an action.
    for (const hit of result.structuredContent.results) {
      expect(Object.keys(hit).sort()).toEqual(expect.arrayContaining(['id', 'title', 'type']));
      expect(hit).not.toHaveProperty('action');
      expect(hit).not.toHaveProperty('tool');
    }
    // list_tasks over the same content, same story.
    const list = await callTool(app, access, 'list_tasks', { limit: 50 });
    expect(list.isError).toBeFalsy();

    // Not one table changed as a side effect of reading hostile data.
    expect(tableSnapshot()).toEqual(before);
  });

  it('hostile note bodies are data to get_note, and get_note leaks no other workspace', async () => {
    for (const testCase of noteCases) {
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${owner.workspace.id}/notes`,
        headers: owner.headers,
        payload: { title: 'Not', contentMarkdown: testCase.text },
      });
    }
    const before = tableSnapshot();
    const search = await callTool(app, access, 'search', { query: 'SYSTEM', types: ['note'] });
    // Whatever comes back is note data — no field named like a command.
    for (const hit of search.structuredContent.results) {
      expect(hit.type).toBe('note');
      expect(hit).not.toHaveProperty('action');
    }
    expect(tableSnapshot()).toEqual(before);
  });

  it('a create_task carrying injection text creates a NORMAL task, no more', async () => {
    const before = tableSnapshot();
    const hostile = corpus.cases.find((c) => c.id === 'tool-json-mimicry');
    const result = await callTool(app, access, 'create_task', { title: hostile.text });
    expect(result.structuredContent.created).toBe(true);
    // Exactly one task added; the JSON-RPC-looking title is just a string.
    expect(tables.tasks.length).toBe(before.tasks + 1);
    expect(tables.tasks.at(-1).title).toBe(hostile.text);
    expect(before.deleted).toBe(tableSnapshot().deleted);
  });
});
