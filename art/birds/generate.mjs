// Draws the birds in species.mjs with gemini-3-pro-image, on flat white (cutout.swift cuts them out).
//
// Usage (Node 24, from the repo root):
//   node --env-file=.env art/birds/generate.mjs --sync --species norcar   # one image now (standard price)
//   node --env-file=.env art/birds/generate.mjs                           # the rest as one batch (half price)
//   node --env-file=.env art/birds/generate.mjs --redo norcar,blujay      # redraw some, even if they exist
//
// A batch can take minutes to hours. The script submits it, saves its name to out/batch.json, and
// polls. If it's interrupted, rerun the same command to pick the batch back up.
// Birds that already have an image in out/raw/ are skipped.
//
// Writes out/raw/<code>.jpg (Gemini returns JPEG) and out/log.json.

import { existsSync } from "node:fs";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { SPECIES, prompt } from "./species.mjs";

const MODEL = "gemini-3-pro-image";
const API = "https://generativelanguage.googleapis.com/v1beta";
const DOWNLOAD_API = "https://generativelanguage.googleapis.com/download/v1beta";
const POLL_MS = 30_000;

const OUT = join(dirname(fileURLToPath(import.meta.url)), "out");
const RAW = join(OUT, "raw");
const BATCH_FILE = join(OUT, "batch.json");
const LOG_FILE = join(OUT, "log.json");

const headers = { "content-type": "application/json", "x-goog-api-key": process.env.GEMINI_API_KEY };

// --- Command line -----------------------------------------------------------

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  if (i === -1) return undefined;

  const next = process.argv[i + 1];
  return next && !next.startsWith("--") ? next : true;
}

function codesArg(name) {
  const value = arg(name);
  if (typeof value !== "string") return [];

  const codes = value.split(",");
  for (const code of codes) {
    if (!SPECIES.some((s) => s.code === code)) throw new Error(`unknown species code: ${code}`);
  }
  return codes;
}

/** The birds to draw: those asked for (or all), minus ones that already have an image. */
async function birdsToDraw() {
  const only = codesArg("species");
  const redo = codesArg("redo");

  // Redone birds lose their old image, so they're drawn along with any others missing one.
  for (const code of redo) await rm(join(RAW, `${code}.jpg`), { force: true });

  const wanted = only.length ? SPECIES.filter((s) => only.includes(s.code)) : SPECIES;
  return wanted.filter((s) => !existsSync(join(RAW, `${s.code}.jpg`)));
}

// --- Gemini -----------------------------------------------------------------

function request(s) {
  return {
    contents: [{ parts: [{ text: prompt(s) }] }],
    generationConfig: { responseModalities: ["IMAGE"], imageConfig: { aspectRatio: "1:1" } },
  };
}

async function api(url, init = {}) {
  const res = await fetch(url.startsWith("http") ? url : `${API}/${url}`, { headers, ...init });
  const json = await res.json();
  if (!res.ok) throw new Error(`${res.status} ${JSON.stringify(json.error ?? json)}`);
  return json;
}

/** The image in a generateContent response, or an error saying why there isn't one. */
function imageFrom(response) {
  const part = response?.candidates?.[0]?.content?.parts?.find((p) => p.inlineData ?? p.inline_data);
  if (part) return Buffer.from((part.inlineData ?? part.inline_data).data, "base64");

  const reason = response?.candidates?.[0]?.finishReason ?? response?.promptFeedback?.blockReason;
  throw new Error(`no image (${reason ?? "empty response"})`);
}

// --- Saving -----------------------------------------------------------------

/** Writes one bird's image; returns its log entry. */
async function save(code, response) {
  try {
    await writeFile(join(RAW, `${code}.jpg`), imageFrom(response));
    console.log(`✓ ${code}`);
    return { code, ok: true, usage: response.usageMetadata };
  } catch (err) {
    console.error(`✗ ${code}: ${err.message}`);
    return { code, ok: false, error: err.message };
  }
}

async function log(entries) {
  const all = await readFile(LOG_FILE, "utf8").then(JSON.parse, () => ({}));
  for (const e of entries) all[e.code] = { ...e, at: new Date().toISOString() };
  await writeFile(LOG_FILE, JSON.stringify(all, null, 2));
}

// --- Sync: one request per bird ---------------------------------------------

async function drawNow(birds) {
  const entries = [];

  for (const s of birds) {
    try {
      const body = JSON.stringify(request(s));
      const response = await api(`models/${MODEL}:generateContent`, { method: "POST", body });
      entries.push(await save(s.code, response));
    } catch (err) {
      console.error(`✗ ${s.code}: ${err.message}`);
      entries.push({ code: s.code, ok: false, error: err.message });
    }
  }

  return entries;
}

// --- Batch: all birds in one job, half price --------------------------------

async function submitBatch(birds) {
  const body = {
    batch: {
      display_name: `overheard-birds-${new Date().toISOString().slice(0, 10)}`,
      input_config: {
        requests: { requests: birds.map((s) => ({ request: request(s), metadata: { key: s.code } })) },
      },
    },
  };

  const job = await api(`models/${MODEL}:batchGenerateContent`, { method: "POST", body: JSON.stringify(body) });
  const name = job.name ?? job.metadata?.name;

  await writeFile(BATCH_FILE, JSON.stringify({ name, codes: birds.map((s) => s.code) }, null, 2));
  console.log(`submitted ${name} (${birds.length} birds)`);
  return name;
}

/** Polls until the batch is done; returns [{ key, response, error }]. */
async function waitForBatch(name) {
  for (;;) {
    const job = await api(name);
    const state = job.metadata?.state ?? job.state ?? "pending";

    if (state.endsWith("SUCCEEDED")) return batchResults(job);
    if (/FAILED|CANCELLED|EXPIRED/.test(state)) {
      throw new Error(`batch ${state}: ${JSON.stringify(job.error ?? job).slice(0, 300)}`);
    }

    console.log(`${new Date().toLocaleTimeString()} ${state}…`);
    await new Promise((resolve) => setTimeout(resolve, POLL_MS));
  }
}

/** Results come back inline for small jobs, or as a JSONL file for large ones. */
async function batchResults(job) {
  const output = job.response ?? job.metadata?.output ?? job.output ?? {};

  const inline = output.inlinedResponses?.inlinedResponses ?? output.inlinedResponses;
  if (Array.isArray(inline)) {
    return inline.map((r) => ({ key: r.metadata?.key, response: r.response, error: r.error }));
  }

  if (output.responsesFile) {
    const res = await fetch(`${DOWNLOAD_API}/${output.responsesFile}:download?alt=media`, { headers });
    const lines = (await res.text()).trim().split("\n");
    return lines.map((line) => JSON.parse(line));
  }

  throw new Error(`batch succeeded but has no results: ${JSON.stringify(output).slice(0, 300)}`);
}

async function drawInBatch(birds) {
  // Pick up a batch from an interrupted run before submitting a new one.
  const pending = await readFile(BATCH_FILE, "utf8").then(JSON.parse, () => null);
  if (!pending && !birds.length) {
    console.log("nothing to draw: every bird has an image (use --redo)");
    return [];
  }

  const name = pending?.name ?? (await submitBatch(birds));
  const results = await waitForBatch(name);

  const entries = [];
  for (const r of results) {
    if (r.error) entries.push({ code: r.key, ok: false, error: JSON.stringify(r.error) });
    else entries.push(await save(r.key, r.response));
  }

  await rm(BATCH_FILE);
  return entries;
}

// --- Run --------------------------------------------------------------------

async function main() {
  if (!process.env.GEMINI_API_KEY) throw new Error("GEMINI_API_KEY is required (in .env)");
  await mkdir(RAW, { recursive: true });

  const birds = await birdsToDraw();
  const entries = arg("sync") ? await drawNow(birds) : await drawInBatch(birds);
  await log(entries);

  const failed = entries.filter((e) => !e.ok).length;
  console.log(`${entries.length - failed} drawn, ${failed} failed`);
  if (failed) process.exitCode = 1;
}

main().catch((err) => {
  console.error(err.message ?? err);
  process.exit(1);
});
