// Builds the manuscript .docx from paper.md
const fs = require("fs");
const path = require("path");
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType, Table, TableRow,
  TableCell, WidthType, ShadingType, BorderStyle, ImageRun, Footer, PageNumber,
  LevelFormat, ExternalHyperlink,
} = require("docx");

const IN = process.argv[2] || "paper.md", OUT = process.argv[3] || "out.docx";
const src = fs.readFileSync(path.join(__dirname, IN), "utf8").split("\n");
const FONT = "Times New Roman";
const BODY = 22; // 11 pt
const CONTENT_W = 9026; // A4 width minus 1" margins (DXA)

function runs(text, opts = {}) {
  // supports *italic* only
  const out = [];
  const parts = text.split(/(\*[^*]+\*)/);
  for (const p of parts) {
    if (!p) continue;
    if (p.startsWith("*") && p.endsWith("*")) out.push(new TextRun({ text: p.slice(1, -1), italics: true, font: FONT, size: opts.size || BODY, bold: opts.bold }));
    else out.push(new TextRun({ text: p, font: FONT, size: opts.size || BODY, bold: opts.bold, italics: opts.italics }));
  }
  return out;
}

function para(text, extra = {}) {
  return new Paragraph({
    children: runs(text, extra.run || {}),
    alignment: extra.align || AlignmentType.JUSTIFIED,
    spacing: { after: 120, line: 276, ...(extra.spacing || {}) },
    indent: extra.indent,
    keepNext: extra.keepNext,
  });
}

function caption(text) {
  const m = text.match(/^(Table \d+\.|Figure \d+\.)\s*(.*)$/);
  const children = m
    ? [new TextRun({ text: m[1] + " ", bold: true, font: FONT, size: 20 }), ...runs(m[2], { size: 20 })]
    : runs(text, { size: 20 });
  return children;
}

function table(captionText, rows) {
  const cells = rows.map((r) => r.replace(/^\||\|$/g, "").split("|").map((c) => c.trim()));
  const ncol = cells[0].length;
  // column widths: weight by max text length, bounded
  const lens = Array.from({ length: ncol }, (_, i) => Math.max(...cells.map((r) => Math.min((r[i] || "").length, 60))) + 6);
  const sum = lens.reduce((a, b) => a + b, 0);
  let widths = lens.map((l) => Math.max(1300, Math.floor((l / sum) * CONTENT_W)));
  const tot = widths.reduce((a, b) => a + b, 0);
  widths = widths.map((w) => Math.floor(w * CONTENT_W / tot));
  widths[widths.length - 1] += CONTENT_W - widths.reduce((a, b) => a + b, 0);
  const border = { style: BorderStyle.SINGLE, size: 4, color: "999999" };
  const borders = { top: border, bottom: border, left: border, right: border };
  const trows = cells.map((r, ri) => new TableRow({
    tableHeader: ri === 0,
    cantSplit: true,
    children: r.map((c, ci) => new TableCell({
      width: { size: widths[ci], type: WidthType.DXA },
      borders,
      shading: ri === 0 ? { fill: "E8EEF5", type: ShadingType.CLEAR, color: "auto" } : undefined,
      margins: { top: 60, bottom: 60, left: 100, right: 100 },
      children: [new Paragraph({ children: runs(c, { size: 19, bold: ri === 0 }), spacing: { after: 0, line: 252 } })],
    })),
  }));
  return [
    new Paragraph({ children: caption(captionText), spacing: { before: 200, after: 80 }, keepNext: true }),
    new Table({ width: { size: CONTENT_W, type: WidthType.DXA }, columnWidths: widths, rows: trows }),
    new Paragraph({ children: [], spacing: { after: 120 } }),
  ];
}

function figure(file, captionText) {
  const buf = fs.readFileSync(path.join(__dirname, file));
  const w = buf.readUInt32BE(16), h = buf.readUInt32BE(20);
  const maxW = 600; // px at 96 dpi ≈ 6.25 in
  const width = maxW, height = Math.round((h / w) * maxW);
  return [
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 200, after: 80 }, keepNext: true,
      children: [new ImageRun({ type: "png", data: buf, transformation: { width, height },
        altText: { title: captionText.slice(0, 40), description: captionText, name: path.basename(file) } })] }),
    new Paragraph({ children: caption(captionText), alignment: AlignmentType.JUSTIFIED, spacing: { after: 200 } }),
  ];
}

const children = [];
let i = 0;
while (i < src.length) {
  const line = src[i];
  if (!line.trim()) { i++; continue; }
  if (line.startsWith("TITLE: ")) {
    children.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 240 },
      children: [new TextRun({ text: line.slice(7), bold: true, font: FONT, size: 32 })] }));
  } else if (line.startsWith("AUTHORS: ")) {
    children.push(para(line.slice(9), { align: AlignmentType.CENTER, run: { bold: true } }));
  } else if (line.startsWith("AFFIL: ")) {
    const last = !(src[i + 1] || "").startsWith("AFFIL: ");
    children.push(para(line.slice(7), { align: AlignmentType.CENTER, spacing: { after: last ? 360 : 40 }, run: { size: 20 } }));
  } else if (line.startsWith("ABSTRACT: ")) {
    children.push(new Paragraph({ children: [new TextRun({ text: "Abstract", bold: true, font: FONT, size: 24 })], spacing: { after: 100 } }));
    children.push(para(line.slice(10), { indent: { left: 360, right: 360 } }));
  } else if (line.startsWith("KEYWORDS: ")) {
    children.push(new Paragraph({ alignment: AlignmentType.JUSTIFIED, indent: { left: 360, right: 360 }, spacing: { after: 360 },
      children: [new TextRun({ text: "Keywords: ", bold: true, font: FONT, size: BODY }), ...runs(line.slice(10))] }));
  } else if (line.startsWith("# ")) {
    children.push(new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun({ text: line.slice(2), font: FONT })], keepNext: true }));
  } else if (line.startsWith("## ")) {
    children.push(new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun({ text: line.slice(3), font: FONT })], keepNext: true }));
  } else if (line.startsWith("TABLE: ")) {
    const cap = line.slice(7); const rows = []; i++;
    while (i < src.length && src[i].startsWith("|")) { rows.push(src[i]); i++; }
    children.push(...table(cap, rows)); continue;
  } else if (line.startsWith("FIGURE: ")) {
    const [file, cap] = line.slice(8).split(" | ");
    children.push(...figure(file.trim(), cap.trim()));
  } else if (line.startsWith("- ")) {
    children.push(new Paragraph({ numbering: { reference: "bullets", level: 0 }, alignment: AlignmentType.JUSTIFIED,
      spacing: { after: 80, line: 276 }, children: runs(line.slice(2)) }));
  } else if (line.startsWith("REF: ")) {
    const t = line.slice(5);
    const m = t.match(/^(.*?)(https?:\/\/\S+)$/);
    const kids = m ? [...runs(m[1]), new ExternalHyperlink({ link: m[2], children: [new TextRun({ text: m[2], font: FONT, size: BODY, color: "1F4E9A" })] })] : runs(t);
    children.push(new Paragraph({ children: kids, indent: { left: 720, hanging: 720 }, spacing: { after: 100, line: 264 } }));
  } else if (/^(Data and code availability|Use of generative AI|Conflicts of interest|Funding)\./.test(line)) {
    const k = line.indexOf(".") + 1;
    children.push(new Paragraph({ alignment: AlignmentType.JUSTIFIED, spacing: { after: 120, line: 276 },
      children: [new TextRun({ text: line.slice(0, k) + " ", bold: true, font: FONT, size: BODY }), ...runs(line.slice(k).trim())] }));
  } else {
    children.push(para(line));
  }
  i++;
}

const doc = new Document({
  creator: "Imran Basha Shaik, Prathyusha Pochampally",
  title: "Autonomous ETL Pipelines for Salesforce M&A Consolidation",
  styles: {
    default: { document: { run: { font: FONT, size: BODY } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 26, bold: true, font: FONT, color: "000000" }, paragraph: { spacing: { before: 320, after: 140 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 23, bold: true, italics: true, font: FONT, color: "000000" }, paragraph: { spacing: { before: 220, after: 100 }, outlineLevel: 1 } },
    ],
  },
  numbering: { config: [{ reference: "bullets", levels: [{ level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT,
    style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] }] },
  sections: [{
    properties: { page: { size: { width: 11906, height: 16838 }, margin: { top: 1440, bottom: 1440, left: 1440, right: 1440 } } },
    footers: { default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER,
      children: [new TextRun({ children: [PageNumber.CURRENT], font: FONT, size: 18 })] })] }) },
    children,
  }],
});

Packer.toBuffer(doc).then((b) => {
  fs.writeFileSync(path.join(__dirname, OUT), b);
  console.log("written", b.length);
});
