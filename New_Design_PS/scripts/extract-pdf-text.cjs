const fs = require("node:fs");
const path = require("node:path");

async function main() {
  const filePath = process.argv[2];
  if (!filePath) {
    throw new Error("Missing PDF file path.");
  }

  const pdfParseEntry = path.join(
    process.cwd(),
    "node_modules",
    "pdf-parse",
    "dist",
    "pdf-parse",
    "cjs",
    "index.cjs",
  );

  const { PDFParse } = require(pdfParseEntry);
  const buffer = fs.readFileSync(filePath);
  const parser = new PDFParse({ data: buffer });

  try {
    const result = await parser.getText();
    process.stdout.write(JSON.stringify({ text: result.text ?? "" }));
  } finally {
    await parser.destroy();
  }
}

main().catch((error) => {
  const message = error && error.stack ? error.stack : String(error);
  process.stderr.write(message);
  process.exit(1);
});
