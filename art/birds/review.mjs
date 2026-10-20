// Writes out/review.html: every cutout on the journal-page color, with its name and field marks,
// so the set can be checked before it ships. Click the page to switch to the Candlelight edge color,
// where any leftover white halo shows.
//
// Usage (from the repo root):
//   node art/birds/review.mjs && open art/birds/out/review.html

import { existsSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { SPECIES } from "./species.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, "out");

function card(s) {
  const file = join(HERE, "cutouts", `${s.code}.png`);
  const art = existsSync(file)
    ? `<img src="../cutouts/${s.code}.png" alt="">`
    : `<div class="missing">no cutout yet</div>`;

  return `
    <figure>
      ${art}
      <figcaption><b>${s.name}</b> <code>${s.code}</code><br><small>${s.marks}</small></figcaption>
    </figure>`;
}

const html = `<!doctype html>
<meta charset="utf-8">
<title>Bird art review</title>
<style>
  body { margin: 0; padding: 24px; background: #fdfaf3; color: #2a1f15; font: 14px Georgia, serif; }
  body.dark { background: #8f6d42; }
  h1 { font-weight: normal; }
  main { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 24px; }
  figure { margin: 0; }
  img { width: 100%; height: 240px; object-fit: contain; }
  .missing { height: 240px; display: grid; place-items: center; border: 1px dashed #8b2f1c; color: #8b2f1c; }
  small { color: #6a5741; }
  body.dark small { color: #2a1f15; }
</style>
<body onclick="document.body.classList.toggle('dark')">
  <h1>Bird art review · ${SPECIES.length} birds</h1>
  <p>Click anywhere to switch between the page color and the darkest Candlelight edge.</p>
  <main>${SPECIES.map(card).join("")}
  </main>
</body>
`;

await mkdir(OUT, { recursive: true });
await writeFile(join(OUT, "review.html"), html);
console.log(`wrote ${join(OUT, "review.html")}`);
