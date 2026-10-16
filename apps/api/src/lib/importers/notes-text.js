/**
 * The short blocks an importer writes INTO a task's description (OPH-371).
 *
 * These are the user's own words about their own data, so they follow the
 * language the wizard ran in (`options.locale`), not the server's. Two
 * languages, like the app (ADR-0009); anything else falls back to English.
 */

const TEXT = {
  en: {
    importedFrom: (source) => `Imported from ${source}`,
    repeatKept: (v) => `Repeat "${v}" could not be converted; set it again with Repeat.`,
    dateKept: (v) => `Date "${v}" could not be read; set the date again.`,
    deadline: (v) => `Deadline: ${v}`,
    reminderKept: (v) => `Reminder "${v}" was not converted.`,
    comments: 'Comments',
    subItems: 'Sub-items',
    checklist: 'Checklist',
    attachment: 'Attachment',
    labels: 'Labels',
    date: 'Date',
  },
  tr: {
    importedFrom: (source) => `${source} içinden aktarıldı`,
    repeatKept: (v) => `"${v}" tekrarı dönüştürülemedi; Tekrarla ile yeniden kurun.`,
    dateKept: (v) => `"${v}" tarihi okunamadı; tarihi yeniden seçin.`,
    deadline: (v) => `Son tarih: ${v}`,
    reminderKept: (v) => `"${v}" hatırlatıcısı dönüştürülmedi.`,
    comments: 'Yorumlar',
    subItems: 'Alt maddeler',
    checklist: 'Kontrol listesi',
    attachment: 'Ek',
    labels: 'Etiketler',
    date: 'Tarih',
  },
};

export function importText(locale) {
  return TEXT[locale] ?? TEXT.en;
}

export const SOURCE_LABELS = { todoist: 'Todoist', ticktick: 'TickTick' };

export const MAX_DESCRIPTION = 65000;

/**
 * Joins the description parts: the source's own text first, then the blocks
 * the importer added. Empty parts vanish; the result is capped below the
 * TEXT column's 65,535 bytes.
 */
export function composeDescription({ base, sections = [], kept = [], source, locale }) {
  const t = importText(locale);
  const parts = [];
  if (base && base.trim() !== '') parts.push(base.trim());
  for (const { title, lines } of sections) {
    if (lines.length === 0) continue;
    parts.push(`**${title}**\n${lines.map((l) => `- ${l}`).join('\n')}`);
  }
  if (kept.length > 0) {
    parts.push(
      `${t.importedFrom(SOURCE_LABELS[source])}:\n${kept.map((l) => `- ${l}`).join('\n')}`,
    );
  }
  const text = parts.join('\n\n');
  if (text === '') return null;
  return truncateBytes(text, MAX_DESCRIPTION);
}

/**
 * Cuts text to at most `maxBytes` of UTF-8 — the TEXT column counts bytes, and
 * a Turkish description is up to twice as long in bytes as in characters.
 */
export function truncateBytes(text, maxBytes) {
  if (Buffer.byteLength(text, 'utf8') <= maxBytes) return text;
  let out = '';
  let bytes = 0;
  for (const ch of text) {
    const size = Buffer.byteLength(ch, 'utf8');
    if (bytes + size > maxBytes - 3) break;
    out += ch;
    bytes += size;
  }
  return `${out}…`;
}
