// Shared schema→prose helpers for the reference and the Postman collection.
//
// Both render the same spec and must describe it identically; two copies of
// this logic would be the third and fourth hand-maintained descriptions of
// the API, which is the problem OPH-294 exists to end.

/** Every id in AllisWell is a 26-character ULID (`lib/ids.js`). */
const isUlid = (schema) => schema?.minLength === 26 && schema?.maxLength === 26;

/** Unwrap the `anyOf: [{type:'null'}, ULID]` idiom the routes use for
 *  "a nullable reference". Left alone it renders as the useless word "any". */
export function unwrap(schema) {
  if (!schema) return { schema, nullable: false };
  const branches = schema.anyOf ?? schema.oneOf;
  if (!Array.isArray(branches)) return { schema, nullable: !!schema.nullable };

  const real = branches.filter((b) => b?.type !== 'null');
  const nullable = branches.length !== real.length || !!schema.nullable;
  if (real.length === 1) return { schema: { ...real[0] }, nullable };
  return { schema: { ...schema, anyOf: real }, nullable };
}

/** The one-line type a reader wants to see. */
export function typeOf(input) {
  const { schema, nullable } = unwrap(input);
  if (!schema) return '—';
  if (schema.enum) return schema.enum.map((v) => `\`${v}\``).join(' · ');

  const branches = schema.anyOf ?? schema.oneOf;
  if (Array.isArray(branches)) return branches.map((b) => typeOf(b)).join(' or ');

  const base = Array.isArray(schema.type)
    ? schema.type.filter((t) => t !== 'null').join(' | ')
    : (schema.type ?? 'any');

  if (base === 'array') {
    return `array of ${schema.items ? typeOf(schema.items) : 'any'}`;
  }

  const bits = [isUlid(schema) ? 'ULID' : base];
  if (schema.format) bits.push(`(${schema.format})`);
  if (nullable || (Array.isArray(input?.type) && input.type.includes('null'))) {
    bits.push('or null');
  }
  return bits.join(' ');
}

/** The constraints that actually change what a caller may send. */
export function constraintsOf(input) {
  const { schema } = unwrap(input);
  if (!schema) return '';
  // A ULID's length is already said by its type; repeating "length 26–26"
  // spends a column on nothing.
  if (isUlid(schema)) return '26-character identifier';

  const out = [];
  const { minLength, maxLength, minimum, maximum, minItems, maxItems, pattern } = schema;
  const def = schema.default;

  if (minLength !== undefined || maxLength !== undefined) {
    out.push(`length ${minLength ?? 0}–${maxLength ?? '∞'}`);
  }
  if (minimum !== undefined || maximum !== undefined) {
    out.push(`${minimum ?? '−∞'}–${maximum ?? '∞'}`);
  }
  if (minItems !== undefined || maxItems !== undefined) {
    out.push(`up to ${maxItems ?? '∞'} items`);
  }
  if (pattern) out.push(`pattern \`${pattern}\``);
  if (def !== undefined) out.push(`default \`${JSON.stringify(def)}\``);
  return out.join(', ');
}

const SAMPLE_ULID = '01J9Z4K8QK7B2N0M3XG5T6WQ7A';

/**
 * A plausible value for a field.
 *
 * Named fields get values that look like themselves, because an example made
 * of the word "string" teaches a reader nothing about what the API expects.
 */
function sampleString(name, schema) {
  if (schema.format === 'date-time') return '2026-09-04T14:30:00.000Z';
  if (schema.pattern === '^#[0-9A-Fa-f]{6}$') return '#0A5CFF';
  if (isUlid(schema)) return SAMPLE_ULID;

  const n = (name ?? '').toLowerCase();
  if (n === 'workspaceid') return SAMPLE_ULID;
  if (n.endsWith('id')) return SAMPLE_ULID;
  if (n.endsWith('at')) return '2026-09-04T14:30:00.000Z';
  if (n === 'email') return 'you@example.com';
  if (n === 'title' || n === 'name') return 'Pay the electricity bill';
  if (n === 'timezone') return 'Europe/Istanbul';
  if (n === 'locale') return 'tr';
  if (n === 'slug') return 'pay-the-electricity-bill';
  if (n.includes('markdown')) return '# Heading\n\nbody';
  if (n === 'description') return 'What this is for';
  if (n === 'url') return 'https://example.com';
  return 'string';
}

/**
 * Build an example.
 *
 * `requiredOnly` produces the SHORTEST request that works — which is what a
 * reader copies. A create that accepts twenty optional fields should not
 * demonstrate itself by sending all twenty; that reads as though they were
 * mandatory, and it buries the one field that is.
 */
export function exampleFor(input, { name, depth = 0, requiredOnly = false } = {}) {
  const { schema, nullable } = unwrap(input);
  if (!schema || depth > 4) return null;
  if (schema.enum) return schema.enum[0];

  const branches = schema.anyOf ?? schema.oneOf;
  if (Array.isArray(branches) && branches.length > 0) {
    return exampleFor(branches[0], { name, depth, requiredOnly });
  }

  const type = Array.isArray(schema.type)
    ? schema.type.find((t) => t !== 'null')
    : schema.type;

  switch (type) {
    case 'object': {
      const out = {};
      const required = schema.required ?? [];
      for (const [key, prop] of Object.entries(schema.properties ?? {})) {
        if (requiredOnly && required.length > 0 && !required.includes(key)) continue;
        const value = exampleFor(prop, { name: key, depth: depth + 1, requiredOnly });
        if (value !== null || prop.nullable) out[key] = value;
      }
      return out;
    }
    case 'array': {
      const item = exampleFor(schema.items, { name, depth: depth + 1, requiredOnly });
      return item === null ? [] : [item];
    }
    case 'integer':
      return schema.default ?? schema.minimum ?? 1;
    case 'number':
      return schema.default ?? 1;
    case 'boolean':
      return schema.default ?? false;
    case 'string':
      return sampleString(name, schema);
    default:
      return nullable ? null : null;
  }
}

/**
 * What a status code means on THIS API.
 *
 * Fastify emits "Default Response" for every one of them, which is worse than
 * silence: it fills the column a reader is scanning. The meanings come from
 * the house family the routes actually follow (`routes/quick-links.js` and
 * `routes/ai.js` both document it in a comment).
 */
const STATUS_MEANING = {
  200: 'Success.',
  201: 'Created.',
  204: 'Done. No body.',
  400: 'A field is malformed or missing. The body names a `code`.',
  401: 'No credential, or one that is expired, revoked or unknown.',
  403: 'Authenticated, but not allowed here — wrong workspace, missing role, or an API key on a JWT-only route.',
  404: 'Not visible to you. Someone else’s row answers 404, never 403.',
  409: 'Refused because of a uniqueness or state clash (e.g. an edit conflict).',
  413: 'Too large.',
  422: 'Well-formed, but refused by a business rule.',
  429: 'Rate limited. See `retry-after`.',
  502: 'An upstream service failed.',
  503: 'Not configured on this server.',
};

export function statusMeaning(status, fallback) {
  const known = STATUS_MEANING[Number(status)];
  if (known) return known;
  if (fallback && fallback !== 'Default Response') return fallback;
  return '—';
}
