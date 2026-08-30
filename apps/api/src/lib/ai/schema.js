import Ajv from 'ajv';

/**
 * THE task-proposal schema (OPH-219, AI.md §4) — the single source both the
 * extraction endpoint and the MCP `create_task` tool (OPH-218) speak.
 *
 * No `ajv-formats`: `dueAt`/`reminderAt` use an explicit ISO-8601-with-offset
 * pattern instead of `format: 'date-time'` (one fewer dependency, and the
 * provider variants strip patterns anyway — Ajv always has the last word
 * server-side).
 *
 * `providerSchema()` shapes the canonical schema into what each provider's
 * constrained-output mode actually accepts; `normalizeProposal()` undoes the
 * strict-mode nullability so the canonical validator sees canonical data.
 */

// Offset REQUIRED: 'Z' or ±HH:MM — a naive local timestamp is ambiguous.
export const ISO8601_OFFSET =
  '^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}(:\\d{2}(\\.\\d{1,3})?)?(Z|[+-]\\d{2}:\\d{2})$';

// Kept in parity with routes/tasks.js TASK_PRIORITIES — asserted by test, not
// imported (a lib → routes import would be an upside-down dependency).
export const PROPOSAL_PRIORITIES = ['none', 'low', 'medium', 'high', 'urgent'];

export const PROPOSAL_AMBIGUITIES = [
  'date_unclear',
  'project_unknown',
  'title_guessed',
  'time_assumed',
  'other',
];

const TASK_ITEM = {
  type: 'object',
  additionalProperties: false,
  required: ['title', 'confidence'],
  properties: {
    title: { type: 'string', minLength: 1, maxLength: 500 },
    description: { type: 'string', maxLength: 4000 },
    // The name the user SAID — never an id. Resolution is ours (fold tiers).
    projectName: { type: 'string', minLength: 1, maxLength: 120 },
    dueAt: { type: 'string', pattern: ISO8601_OFFSET },
    // The raw phrase ("yarın 15:00") — the confirm card shows it beside the
    // resolved value, so a model mistake is visible, not silent.
    dueAtSource: { type: 'string', minLength: 1, maxLength: 120 },
    reminderAt: { type: 'string', pattern: ISO8601_OFFSET },
    priority: { enum: PROPOSAL_PRIORITIES },
    urgent: { type: 'boolean' },
    tags: { type: 'array', maxItems: 10, items: { type: 'string', minLength: 1, maxLength: 60 } },
    checklist: {
      type: 'array',
      maxItems: 30,
      items: { type: 'string', minLength: 1, maxLength: 200 },
    },
    confidence: { type: 'number', minimum: 0, maximum: 1 },
    ambiguities: { type: 'array', maxItems: 8, items: { enum: PROPOSAL_AMBIGUITIES } },
  },
  // A resolved date without its source phrase cannot be honestly confirmed.
  dependencies: { dueAt: ['dueAtSource'] },
};

export const TASK_PROPOSAL_SCHEMA = {
  $id: 'alliswell-ai-task-proposal',
  type: 'object',
  additionalProperties: false,
  required: ['intent', 'tasks'],
  properties: {
    intent: { enum: ['create_tasks', 'answer', 'none'] },
    // OPH-224's single-round-trip intent gate rides this field.
    answer: { type: 'string', maxLength: 4000 },
    tasks: { type: 'array', maxItems: 20, items: TASK_ITEM },
  },
};

export const TASK_ITEM_SCHEMA = TASK_ITEM;

const ajv = new Ajv({ allErrors: true, strict: false });
export const validateProposal = ajv.compile(TASK_PROPOSAL_SCHEMA);

/** Compact, model-readable validator output for the repair round. */
export function describeValidationErrors(errors = []) {
  return errors
    .slice(0, 12)
    .map((e) => `${e.instancePath || '(root)'} ${e.message}`)
    .join('; ');
}

const STRIP_ALWAYS = ['dependencies'];
const BOUND_KEYWORDS = ['minLength', 'maxLength', 'pattern', 'minimum', 'maximum', 'maxItems'];

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function walkSchemas(node, visit) {
  if (!node || typeof node !== 'object') return;
  visit(node);
  if (node.properties) Object.values(node.properties).forEach((child) => walkSchemas(child, visit));
  if (node.items) walkSchemas(node.items, visit);
}

/**
 * A canonical schema, shaped for one provider's constrained-output mode.
 * Whatever a provider ignores or rejects, Ajv enforces afterwards — the
 * canonical schema stays authoritative.
 *
 * `source` defaults to the task proposal because that is what every caller
 * wanted until now. It is a parameter rather than a constant because the
 * DIALECT rules below are about the provider, not about the payload: an
 * extension asking a model for a different constrained shape needs the same
 * four adaptations, and the alternative is a second copy of them that drifts
 * the first time a vendor changes its mind about `additionalProperties`.
 */
export function providerSchema(provider, source = TASK_PROPOSAL_SCHEMA) {
  const schema = clone(source);
  delete schema.$id;

  if (provider === 'openai' || provider === 'openrouter') {
    // OpenAI strict mode: every property required; original-optional fields
    // become nullable unions; bound keywords are unsupported.
    walkSchemas(schema, (node) => {
      for (const key of [...STRIP_ALWAYS, ...BOUND_KEYWORDS]) delete node[key];
      if (node.type === 'object' && node.properties) {
        const all = Object.keys(node.properties);
        const originallyRequired = new Set(node.required ?? []);
        node.required = all;
        for (const key of all) {
          if (originallyRequired.has(key)) continue;
          const child = node.properties[key];
          if (child.enum) {
            child.enum = [...child.enum, null];
          } else if (child.type) {
            child.type = Array.isArray(child.type) ? [...child.type, 'null'] : [child.type, 'null'];
          }
        }
        node.additionalProperties = false;
      }
    });
    return schema;
  }

  if (provider === 'gemini') {
    // Gemini's OpenAPI subset: no additionalProperties, no pattern/bounds.
    walkSchemas(schema, (node) => {
      for (const key of [...STRIP_ALWAYS, ...BOUND_KEYWORDS]) delete node[key];
      delete node.additionalProperties;
    });
    return schema;
  }

  if (provider === 'anthropic') {
    // Structured outputs tolerate but don't enforce bounds; dependencies and
    // patterns confuse some paths — canonical minus those.
    walkSchemas(schema, (node) => {
      delete node.dependencies;
      delete node.pattern;
    });
    return schema;
  }

  // Ollama grammar-constrains on a full JSON Schema; unknown keywords ignored.
  return schema;
}

/** Drops the strict-variant nulls so canonical validation sees canonical data. */
export function normalizeProposal(json) {
  if (json === null || json === undefined) return json;
  if (Array.isArray(json)) return json.map(normalizeProposal);
  if (typeof json !== 'object') return json;
  const out = {};
  for (const [key, value] of Object.entries(json)) {
    if (value === null) continue;
    out[key] = normalizeProposal(value);
  }
  return out;
}
