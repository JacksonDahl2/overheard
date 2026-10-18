// Generates a base illustration + one variation per species for each model.
//
// Usage:
//   GEMINI_API_KEY=... OPENAI_API_KEY=... node art/model-comparison/run.mjs [--only <model-id>] [--species <code>]
//
// Writes PNGs and manifest.json to art/model-comparison/out/.

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { SPECIES, basePrompt, variationPrompt } from "./prompts.mjs";

const OUT = join(dirname(fileURLToPath(import.meta.url)), "out");

const MODELS = [
  { id: "gemini-3.1-flash-image", provider: "gemini" },
  { id: "gemini-3-pro-image", provider: "gemini" },
  { id: "gpt-image-2.5-flare", provider: "openai" },
  { id: "gpt-image-2.5-sunburst", provider: "openai" },
];

// --- Gemini ---------------------------------------------------------------

async function gemini(model, prompt, inputPng) {
  const parts = [{ text: prompt }];
  if (inputPng) {
    const mime = inputPng[0] === 0xff && inputPng[1] === 0xd8 ? "image/jpeg" : "image/png";
    parts.push({ inline_data: { mime_type: mime, data: inputPng.toString("base64") } });
  }

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: { "content-type": "application/json", "x-goog-api-key": process.env.GEMINI_API_KEY },
      body: JSON.stringify({
        contents: [{ parts }],
        generationConfig: { responseModalities: ["IMAGE"], imageConfig: { aspectRatio: "1:1" } },
      }),
    },
  );
  const json = await res.json();
  if (!res.ok) throw new Error(`${res.status} ${JSON.stringify(json.error ?? json)}`);

  const img = json.candidates?.[0]?.content?.parts?.find((p) => p.inlineData ?? p.inline_data);
  if (!img) throw new Error(`no image in response: ${JSON.stringify(json).slice(0, 300)}`);
  const data = img.inlineData ?? img.inline_data;
  // Gemini usually returns JPEG regardless of what we ask for.
  return { png: Buffer.from(data.data, "base64"), mime: data.mimeType ?? data.mime_type, usage: json.usageMetadata };
}

// --- OpenAI ---------------------------------------------------------------

async function openai(model, prompt, inputPng) {
  const headers = { authorization: `Bearer ${process.env.OPENAI_API_KEY}` };
  const params = { model, prompt, size: "1024x1024", quality: "high", background: "transparent", output_format: "png" };

  let res;
  if (inputPng) {
    const form = new FormData();
    for (const [k, v] of Object.entries(params)) form.append(k, v);
    form.append("image[]", new Blob([inputPng], { type: "image/png" }), "base.png");
    res = await fetch("https://api.openai.com/v1/images/edits", { method: "POST", headers, body: form });
  } else {
    res = await fetch("https://api.openai.com/v1/images/generations", {
      method: "POST",
      headers: { ...headers, "content-type": "application/json" },
      body: JSON.stringify(params),
    });
  }
  const json = await res.json();
  if (!res.ok) throw new Error(`${res.status} ${JSON.stringify(json.error ?? json)}`);
  return { png: Buffer.from(json.data[0].b64_json, "base64"), usage: json.usage };
}

// --- Runner ---------------------------------------------------------------

const PROVIDERS = { gemini, openai };

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? undefined : process.argv[i + 1];
}

async function main() {
  const models = MODELS.filter((m) => !arg("only") || m.id === arg("only"));
  const species = SPECIES.filter((s) => !arg("species") || s.code === arg("species"));

  for (const m of models) {
    const key = m.provider === "gemini" ? "GEMINI_API_KEY" : "OPENAI_API_KEY";
    if (!process.env[key]) throw new Error(`${key} is required for ${m.id}`);
  }

  await mkdir(OUT, { recursive: true });
  const manifestPath = join(OUT, "manifest.json");
  const manifest = await readFile(manifestPath, "utf8").then(JSON.parse, () => ({ results: [] }));

  // Run models in parallel; species within a model run sequentially to stay under rate limits.
  await Promise.all(
    models.map(async (m) => {
      for (const s of species) {
        for (const kind of ["base", "variation"]) {
          const file = `${m.id}/${s.code}-${kind}.png`;
          const prompt = kind === "base" ? basePrompt(s) : variationPrompt(s);
          const input = kind === "variation" ? await readFile(join(OUT, `${m.id}/${s.code}-base.png`)).catch(() => null) : null;
          if (kind === "variation" && !input) continue;

          const started = Date.now();
          const entry = { model: m.id, provider: m.provider, species: s.code, name: s.name, kind, file };
          try {
            const { png, mime = "image/png", usage } = await PROVIDERS[m.provider](m.id, prompt, input);
            await mkdir(join(OUT, m.id), { recursive: true });
            await writeFile(join(OUT, file), png);
            Object.assign(entry, { ok: true, ms: Date.now() - started, mime, usage });
            console.log(`✓ ${file} (${entry.ms} ms)`);
          } catch (err) {
            Object.assign(entry, { ok: false, ms: Date.now() - started, error: String(err.message ?? err) });
            console.error(`✗ ${file}: ${entry.error}`);
          }
          manifest.results = manifest.results.filter((r) => r.file !== file).concat(entry);
          await writeFile(manifestPath, JSON.stringify(manifest, null, 2));
        }
      }
    }),
  );

  const failed = manifest.results.filter((r) => !r.ok).length;
  if (failed) {
    console.error(`${failed} image(s) failed — see manifest.json`);
    process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error(err.message ?? err);
  process.exit(1);
});
