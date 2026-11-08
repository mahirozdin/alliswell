/**
 * seed-demo-files.mjs — the bytes behind the demo workspace's files (OPH-414).
 *
 * Until OPH-414 every seeded file was `n` kB of spaces with a one-line header,
 * so `floor-plan.png` could not be previewed, `brand-guidelines.pdf` opened as
 * a broken document and a Files screenshot showed seven generic icons. These
 * builders write small but REAL files — a PNG the app can thumbnail, PDFs a
 * viewer opens, an SVG that draws — with no dependency and no network: a PNG
 * is zlib + CRC-32, a PDF is a text format with a byte-offset table.
 *
 * Everything is deterministic (no clock, no Math.random), so two runs upload
 * byte-identical files.
 */
import { deflateSync } from "node:zlib";

// ── PNG ────────────────────────────────────────────────────────────────────

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

/** CRC-32 as PNG defines it (ISO 3309). */
export function crc32(buf) {
  let c = 0xffffffff;
  for (const byte of buf) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "latin1"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

/** A width×height RGB canvas with the three drawing calls the demo needs. */
export function canvas(width, height, [r, g, b] = [255, 255, 255]) {
  const px = Buffer.alloc(width * height * 3);
  for (let i = 0; i < px.length; i += 3) {
    px[i] = r;
    px[i + 1] = g;
    px[i + 2] = b;
  }
  const set = (x, y, [cr, cg, cb]) => {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    const i = (y * width + x) * 3;
    px[i] = cr;
    px[i + 1] = cg;
    px[i + 2] = cb;
  };
  return {
    width,
    height,
    px,
    rect(x, y, w, h, color) {
      for (let yy = y; yy < y + h; yy += 1)
        for (let xx = x; xx < x + w; xx += 1) set(xx, yy, color);
    },
    /** Every pixel in the box, coloured by `fn(x, y)` — textures. */
    shade(x, y, w, h, fn) {
      for (let yy = y; yy < y + h; yy += 1)
        for (let xx = x; xx < x + w; xx += 1) set(xx, yy, fn(xx, yy));
    },
    toPng() {
      const raw = Buffer.alloc((width * 3 + 1) * height);
      for (let y = 0; y < height; y += 1) {
        raw[y * (width * 3 + 1)] = 0; // filter: none
        px.copy(
          raw,
          y * (width * 3 + 1) + 1,
          y * width * 3,
          (y + 1) * width * 3,
        );
      }
      const ihdr = Buffer.alloc(13);
      ihdr.writeUInt32BE(width, 0);
      ihdr.writeUInt32BE(height, 4);
      ihdr[8] = 8; // bit depth
      ihdr[9] = 2; // colour type: truecolour
      return Buffer.concat([
        Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
        chunk("IHDR", ihdr),
        chunk("IDAT", deflateSync(raw, { level: 9 })),
        chunk("IEND", Buffer.alloc(0)),
      ]);
    },
  };
}

/** A small deterministic hash → 0..1, so textures need no Math.random. */
const noise = (x, y, seed = 0) => {
  let h = (x * 374761393 + y * 668265263 + seed * 2147483647) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
};

/** The renovation's kitchen + hallway, drawn as a plan (Renovation measurements note). */
function floorPlanPng() {
  const c = canvas(960, 640, [250, 250, 247]);
  // Grid paper.
  for (let x = 0; x < 960; x += 32) c.rect(x, 0, 1, 640, [228, 232, 238]);
  for (let y = 0; y < 640; y += 32) c.rect(0, y, 960, 1, [228, 232, 238]);
  const wall = [51, 65, 85];
  // Kitchen 3.20 × 4.10 m, hallway 1.10 m wide (1 m = 128 px).
  const k = { x: 96, y: 96, w: 410, h: Math.round(410 * (3.2 / 4.1)) };
  c.rect(k.x, k.y, k.w, 8, wall);
  c.rect(k.x, k.y + k.h, k.w, 8, wall);
  c.rect(k.x, k.y, 8, k.h + 8, wall);
  c.rect(k.x + k.w, k.y, 8, 120, wall);
  c.rect(k.x + k.w, k.y + 220, 8, k.h - 212, wall);
  // Hallway to the right.
  c.rect(k.x + k.w, k.y + 112, 340, 8, wall);
  c.rect(k.x + k.w, k.y + 112 + 141, 340, 8, wall);
  c.rect(k.x + k.w + 340, k.y + 112, 8, 149, wall);
  // Counter run 2.60 m along the top wall, and the new island.
  c.rect(k.x + 16, k.y + 16, 333, 64, [12, 125, 108]);
  c.rect(k.x + 120, k.y + 180, 180, 72, [142, 68, 236]);
  // Door swing marks.
  c.rect(k.x + k.w - 4, k.y + 120, 16, 100, [250, 250, 247]);
  // Dimension ticks along the bottom.
  for (let x = k.x; x <= k.x + k.w; x += 32)
    c.rect(x, k.y + k.h + 40, 2, 12, [100, 116, 139]);
  c.rect(k.x, k.y + k.h + 46, k.w, 2, [100, 116, 139]);
  return c.toPng();
}

/** Four worktop samples on a mat: the photo the "counter-top quote" task waits on. */
function counterSamplesPng() {
  const c = canvas(960, 640, [236, 233, 228]);
  const samples = [
    { base: [232, 230, 226], fleck: [120, 116, 110], density: 0.08 }, // quartz white
    { base: [54, 57, 63], fleck: [190, 190, 196], density: 0.05 }, // basalt
    { base: [176, 132, 92], fleck: [120, 82, 50], density: 0.25 }, // oak
    { base: [148, 152, 150], fleck: [92, 96, 94], density: 0.18 }, // concrete
  ];
  samples.forEach((s, i) => {
    const x = 64 + (i % 2) * 432;
    const y = 48 + Math.floor(i / 2) * 288;
    c.rect(x + 10, y + 12, 400, 256, [200, 196, 190]); // shadow
    c.shade(x, y, 400, 256, (xx, yy) => {
      const grain =
        i === 2 ? Math.sin((yy + noise(0, yy, 3) * 6) / 5) * 0.5 + 0.5 : 0;
      const n = noise(xx, yy, i + 1);
      const mix = n < s.density ? 1 : grain * s.density * 2;
      return s.base.map((v, k) => Math.round(v + (s.fleck[k] - v) * mix));
    });
  });
  return c.toPng();
}

// ── PDF ────────────────────────────────────────────────────────────────────

/** PDF strings are WinAnsi here; keep the demo text to ASCII and escape the three specials. */
const pdfText = (s) => s.replace(/[\\()]/g, (m) => `\\${m}`);

/**
 * A minimal, valid PDF 1.4: one Helvetica font, A4 pages, each page a list of
 * `{ text, x, y, size, bold, gray }` lines and `{ rect: [x, y, w, h], gray }` fills.
 */
export function pdf(pages, { title = "Document" } = {}) {
  const objects = [];
  const add = (body) => objects.push(body); // the new length = its 1-based object number
  const catalog = add(null);
  const pagesObj = add(null);
  const font = add(
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
  );
  const bold = add(
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
  );
  const info = add(
    `<< /Title (${pdfText(title)}) /Producer (AllisWell demo seed) >>`,
  );
  const kids = [];
  for (const items of pages) {
    const ops = [];
    for (const it of items) {
      if (it.rect) {
        ops.push(`${it.gray ?? 0.9} g ${it.rect.join(" ")} re f`);
      } else {
        ops.push(
          `BT /${it.bold ? "F2" : "F1"} ${it.size ?? 11} Tf ${it.gray ?? 0} g ${it.x} ${it.y} Td (${pdfText(it.text)}) Tj ET`,
        );
      }
    }
    const stream = ops.join("\n");
    const content = add(
      `<< /Length ${Buffer.byteLength(stream, "latin1")} >>\nstream\n${stream}\nendstream`,
    );
    kids.push(
      add(
        `<< /Type /Page /Parent ${pagesObj} 0 R /MediaBox [0 0 595 842] ` +
          `/Resources << /Font << /F1 ${font} 0 R /F2 ${bold} 0 R >> >> /Contents ${content} 0 R >>`,
      ),
    );
  }
  objects[catalog - 1] = `<< /Type /Catalog /Pages ${pagesObj} 0 R >>`;
  objects[pagesObj - 1] =
    `<< /Type /Pages /Kids [${kids.map((k) => `${k} 0 R`).join(" ")}] /Count ${kids.length} >>`;

  let out = "%PDF-1.4\n";
  const offsets = [];
  objects.forEach((body, i) => {
    offsets.push(Buffer.byteLength(out, "latin1"));
    out += `${i + 1} 0 obj\n${body}\nendobj\n`;
  });
  const xref = Buffer.byteLength(out, "latin1");
  out += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const off of offsets)
    out += `${String(off).padStart(10, "0")} 00000 n \n`;
  out += `trailer\n<< /Size ${objects.length + 1} /Root ${catalog} 0 R /Info ${info} 0 R >>\n`;
  out += `startxref\n${xref}\n%%EOF\n`;
  return Buffer.from(out, "latin1");
}

const heading = (text, y = 770) => [
  { rect: [0, 792, 595, 50], gray: 0.15 },
  { text, x: 56, y: y + 36, size: 18, bold: true, gray: 1 },
];

function invoicePdf(month, number, amount) {
  const lines = [
    { rect: [0, 780, 595, 62], gray: 0.93 },
    { text: "INVOICE", x: 56, y: 800, size: 22, bold: true },
    { text: `No. ${number}`, x: 420, y: 806, size: 11 },
    { text: "Alex Rivera Studio", x: 56, y: 740, size: 11, bold: true },
    {
      text: "Billed to: Acme Corp, accounting@acme.example",
      x: 56,
      y: 722,
      size: 11,
    },
    {
      text: `Period: ${month} 2025  -  Terms: Net-30`,
      x: 56,
      y: 704,
      size: 11,
    },
    { rect: [56, 664, 483, 1], gray: 0.6 },
    { text: "Description", x: 56, y: 672, size: 10, bold: true },
    { text: "Hours", x: 380, y: 672, size: 10, bold: true },
    { text: "Amount", x: 470, y: 672, size: 10, bold: true },
    { text: "Retainer - product design", x: 56, y: 644, size: 11 },
    { text: "32", x: 380, y: 644, size: 11 },
    { text: `EUR ${amount}`, x: 470, y: 644, size: 11 },
    { text: "Timesheet export attached", x: 56, y: 624, size: 10 },
    { rect: [56, 596, 483, 1], gray: 0.6 },
    { text: "Total due", x: 380, y: 576, size: 12, bold: true },
    { text: `EUR ${amount}`, x: 470, y: 576, size: 12, bold: true },
  ];
  return pdf([lines], { title: `Acme invoice ${month}` });
}

function kitchenQuotePdf() {
  return pdf(
    [
      [
        ...heading("Kitchen quote"),
        {
          text: "Counter run 2.60 m, island 1.40 x 0.75 m",
          x: 56,
          y: 740,
          size: 12,
        },
        {
          text: "Quartz, 20 mm, polished edge ......... EUR 2,180",
          x: 56,
          y: 710,
          size: 11,
        },
        {
          text: "Sink cut-out and hob cut-out ......... EUR 160",
          x: 56,
          y: 692,
          size: 11,
        },
        {
          text: "Delivery and fitting .................. EUR 340",
          x: 56,
          y: 674,
          size: 11,
        },
        { rect: [56, 652, 483, 1], gray: 0.6 },
        {
          text: "Total ................................. EUR 2,680",
          x: 56,
          y: 632,
          size: 12,
          bold: true,
        },
        {
          text: "Valid for 30 days. Install slot: four weeks from deposit.",
          x: 56,
          y: 600,
          size: 10,
        },
      ],
    ],
    { title: "Kitchen quote" },
  );
}

function brandGuidelinesPdf() {
  const swatch = (x, gray, label) => [
    { rect: [x, 600, 110, 80], gray },
    { text: label, x, y: 584, size: 10 },
  ];
  return pdf(
    [
      [
        ...heading("Brand guidelines"),
        { text: "Design System - v1.0", x: 56, y: 730, size: 14, bold: true },
        {
          text: "Tokens first: primitive, semantic, component.",
          x: 56,
          y: 708,
          size: 11,
        },
        ...swatch(56, 0.2, "Ink"),
        ...swatch(186, 0.55, "Slate"),
        ...swatch(316, 0.85, "Mist"),
        ...swatch(446, 0.97, "Paper"),
        {
          text: "Contrast: 4.5:1 for text, 3:1 for large text and icons.",
          x: 56,
          y: 540,
          size: 11,
        },
      ],
      [
        ...heading("Logo"),
        {
          text: "Keep a clear space of one stroke width around the mark.",
          x: 56,
          y: 740,
          size: 11,
        },
        { rect: [56, 560, 160, 160], gray: 0.2 },
        { rect: [86, 590, 100, 100], gray: 0.97 },
        {
          text: "Never stretch, recolour or add a shadow.",
          x: 56,
          y: 530,
          size: 11,
        },
      ],
    ],
    { title: "Brand guidelines" },
  );
}

// ── SVG ────────────────────────────────────────────────────────────────────

function logoSvg() {
  return Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
  <rect width="256" height="256" rx="56" fill="#2563EB"/>
  <circle cx="128" cy="128" r="72" fill="none" stroke="#FFFFFF" stroke-width="20"/>
  <path d="M96 130l22 22 44-48" fill="none" stroke="#FFFFFF" stroke-width="20" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
`,
    "utf8",
  );
}

// ── The catalogue ──────────────────────────────────────────────────────────

const BUILDERS = {
  "brand-guidelines.pdf": {
    mime: "application/pdf",
    build: brandGuidelinesPdf,
  },
  "logo-master.svg": { mime: "image/svg+xml", build: logoSvg },
  "floor-plan.png": { mime: "image/png", build: floorPlanPng },
  "kitchen-quote.pdf": { mime: "application/pdf", build: kitchenQuotePdf },
  "acme-invoice-09.pdf": {
    mime: "application/pdf",
    build: () => invoicePdf("September", "2025-09", "3,840"),
  },
  "acme-invoice-08.pdf": {
    mime: "application/pdf",
    build: () => invoicePdf("August", "2025-08", "3,840"),
  },
  "counter-samples.png": { mime: "image/png", build: counterSamplesPng },
};

/** The names a demo file can have, in upload order. */
export const DEMO_FILE_NAMES = Object.freeze(Object.keys(BUILDERS));

/** `{ mime, bytes }` for one demo file name; throws on a name it does not know. */
export function demoFile(name) {
  const entry = BUILDERS[name];
  if (!entry) throw new Error(`no demo file called ${name}`);
  return { mime: entry.mime, bytes: entry.build() };
}

/**
 * What a seed before OPH-414 uploaded under each name: `kb × 1024` bytes of
 * spaces. A live file with one of these names AND exactly that size is an old
 * stand-in, never a real file, so a re-run replaces it instead of keeping a
 * thumbnail that cannot render. (`counter-samples.jpg` became a PNG — a JPEG
 * encoder is not worth writing for one photo.)
 */
export const LEGACY_PLACEHOLDER_BYTES = Object.freeze({
  "brand-guidelines.pdf": 2400 * 1024,
  "logo-master.svg": 46 * 1024,
  "floor-plan.png": 840 * 1024,
  "kitchen-quote.pdf": 320 * 1024,
  "acme-invoice-09.pdf": 118 * 1024,
  "acme-invoice-08.pdf": 116 * 1024,
  "counter-samples.jpg": 1650 * 1024,
});

/** True for a live file row that an older seed's space-filled stand-in left behind. */
export function isLegacyPlaceholder(file) {
  return LEGACY_PLACEHOLDER_BYTES[file?.name] === Number(file?.sizeBytes);
}
