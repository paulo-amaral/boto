// Builds Resources/Lucide/icons.json from an extracted lucide-static package (npm pack lucide-static; tar -xzf).
// Usage: node Scripts/update-lucide.mjs <path to the extracted package directory>
// Each icon becomes { s: the SVG body, t: its search tags }. The app wraps the body in an <svg> element at run time.
import { readFileSync, writeFileSync, copyFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const source = process.argv[2];
if (!source) { console.error("usage: node Scripts/update-lucide.mjs <package directory>"); process.exit(1); }

const read = (file) => JSON.parse(readFileSync(join(source, file), "utf8"));
const { version, license } = read("package.json");
if (license !== "ISC") { console.error(`expected the ISC licence, found ${license}`); process.exit(1); }

const nodes = read("icon-nodes.json");
const tags = read("tags.json");
const escape = (value) => String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");
const body = (elements) => elements
  .map(([tag, attributes]) => `<${tag} ${Object.entries(attributes).map(([k, v]) => `${k}="${escape(v)}"`).join(" ")}/>`)
  .join("");

const icons = {};
for (const name of Object.keys(nodes).sort()) icons[name] = { s: body(nodes[name]), t: tags[name] ?? [] };

const target = join(dirname(fileURLToPath(import.meta.url)), "..", "Resources", "Lucide");
mkdirSync(target, { recursive: true });
writeFileSync(join(target, "icons.json"), JSON.stringify({ version, icons }));
copyFileSync(join(source, "LICENSE"), join(target, "LICENSE"));
console.log(`wrote ${Object.keys(icons).length} icons from lucide-static ${version}`);
