import { describe, it, expect } from 'vitest';
import {
  validateProposal,
  providerSchema,
  normalizeProposal,
  PROPOSAL_PRIORITIES,
} from '../../src/lib/ai/schema.js';
import { TASK_PRIORITIES } from '../../src/routes/tasks.js';

/** OPH-219 — the single-source proposal schema and its provider variants. */

const GOOD_TASK = {
  title: 'Faturayı öde',
  description: 'Elektrik faturası',
  projectName: 'Ev işleri',
  dueAt: '2026-07-31T15:00:00+03:00',
  dueAtSource: 'yarın 15:00',
  reminderAt: '2026-07-31T14:00:00+03:00',
  priority: 'high',
  urgent: false,
  tags: ['fatura'],
  checklist: ['IBAN kontrol'],
  confidence: 0.92,
  ambiguities: [],
};

const proposal = (overrides = {}) => ({
  intent: 'create_tasks',
  tasks: [GOOD_TASK],
  ...overrides,
});

describe('validateProposal', () => {
  it('accepts a full proposal and a minimal one', () => {
    expect(validateProposal(proposal())).toBe(true);
    expect(validateProposal({ intent: 'none', tasks: [], answer: 'Bugün 3 görev var' })).toBe(true);
    expect(
      validateProposal({ intent: 'create_tasks', tasks: [{ title: 'x', confidence: 1 }] }),
    ).toBe(true);
  });

  it('rejects the shapes that would lie to the confirm card', () => {
    // Empty title
    expect(validateProposal(proposal({ tasks: [{ ...GOOD_TASK, title: '' }] }))).toBe(false);
    // Confidence out of range
    expect(validateProposal(proposal({ tasks: [{ ...GOOD_TASK, confidence: 1.2 }] }))).toBe(false);
    // dueAt WITHOUT its source phrase — unconfirmable resolution
    const noSource = { ...GOOD_TASK };
    delete noSource.dueAtSource;
    expect(validateProposal(proposal({ tasks: [noSource] }))).toBe(false);
    // Offsetless timestamp is ambiguous
    expect(
      validateProposal(proposal({ tasks: [{ ...GOOD_TASK, dueAt: '2026-07-31T15:00:00' }] })),
    ).toBe(false);
    // Unknown extra property
    expect(
      validateProposal(proposal({ tasks: [{ ...GOOD_TASK, projectId: 'X'.repeat(26) }] })),
    ).toBe(false);
    // Unknown ambiguity value
    expect(validateProposal(proposal({ tasks: [{ ...GOOD_TASK, ambiguities: ['weird'] }] }))).toBe(
      false,
    );
    // Unknown intent
    expect(validateProposal({ intent: 'delete_everything', tasks: [] })).toBe(false);
  });

  it('keeps the priority enum in parity with routes/tasks.js', () => {
    expect(PROPOSAL_PRIORITIES).toEqual(TASK_PRIORITIES);
  });
});

describe('providerSchema', () => {
  it('openai strict: everything required, optionals nullable, bounds stripped', () => {
    const schema = providerSchema('openai');
    const item = schema.properties.tasks.items;
    expect(item.required).toEqual(Object.keys(item.properties));
    expect(item.properties.description.type).toEqual(['string', 'null']);
    expect(item.properties.title.minLength).toBeUndefined();
    expect(item.properties.dueAt.pattern).toBeUndefined();
    expect(item.dependencies).toBeUndefined();
    expect(item.additionalProperties).toBe(false);
    // Optional enum fields take null as a member.
    expect(item.properties.priority.enum).toContain(null);
    // Root: answer becomes nullable too.
    expect(schema.properties.answer.type).toEqual(['string', 'null']);
  });

  it('gemini: no additionalProperties, no patterns/bounds, structure intact', () => {
    const schema = providerSchema('gemini');
    const item = schema.properties.tasks.items;
    expect(item.additionalProperties).toBeUndefined();
    expect(item.properties.dueAt.pattern).toBeUndefined();
    expect(item.properties.title.maxLength).toBeUndefined();
    expect(item.required).toEqual(['title', 'confidence']);
  });

  it('anthropic: canonical minus dependencies/pattern; ollama: canonical as-is', () => {
    const anthropic = providerSchema('anthropic');
    expect(anthropic.properties.tasks.items.dependencies).toBeUndefined();
    expect(anthropic.properties.tasks.items.properties.dueAt.pattern).toBeUndefined();
    expect(anthropic.properties.tasks.items.properties.title.minLength).toBe(1);

    const ollama = providerSchema('ollama');
    expect(ollama.properties.tasks.items.dependencies).toEqual({ dueAt: ['dueAtSource'] });
    expect(ollama.properties.tasks.items.properties.dueAt.pattern).toBeDefined();
  });

  it('never mutates the canonical schema', () => {
    providerSchema('openai');
    providerSchema('gemini');
    expect(validateProposal(proposal())).toBe(true); // canonical still enforces
    const noSource = { ...GOOD_TASK };
    delete noSource.dueAtSource;
    expect(validateProposal(proposal({ tasks: [noSource] }))).toBe(false);
  });
});

describe('normalizeProposal', () => {
  it('drops strict-variant nulls so canonical validation sees canonical data', () => {
    const strictShaped = {
      intent: 'create_tasks',
      answer: null,
      tasks: [
        {
          title: 'x',
          description: null,
          projectName: null,
          dueAt: null,
          dueAtSource: null,
          reminderAt: null,
          priority: null,
          urgent: null,
          tags: null,
          checklist: null,
          confidence: 0.5,
          ambiguities: null,
        },
      ],
    };
    const normalized = normalizeProposal(strictShaped);
    expect(normalized).toEqual({
      intent: 'create_tasks',
      tasks: [{ title: 'x', confidence: 0.5 }],
    });
    expect(validateProposal(normalized)).toBe(true);
  });
});
