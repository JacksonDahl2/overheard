# Image model comparison

Picks the model for base illustrations and art variations. The style is hand-drawn ink and wash on parchment, with a transparent background.

## Candidates

Checked 2026-10-18 against the official docs:

| Model | Provider | 1K image (std / batch) | Transparent bg | Edits |
|---|---|---|---|---|
| `gemini-3.1-flash-image` (Nano Banana 2) | Google | $0.067 / $0.034 | No (needs bg removal) | Yes |
| `gemini-3-pro-image` (Nano Banana Pro) | Google | $0.134 / $0.067 | No (needs bg removal) | Yes |
| `gpt-image-2.5-flare` | OpenAI | token-based (~$30 / 1M output tokens) | Yes | Verify |
| `gpt-image-2.5-sunburst` | OpenAI | token-based (~$30 / 1M output tokens) | Yes | Yes (best for edits) |

`gemini-2.5-flash-image`, which AvianVisitors used, was shut down on 2026-10-02.

## Test

- **5 species:** Northern Cardinal, Blue Jay, Black-throated Blue Warbler, White-throated Sparrow, and Red-tailed Hawk.
- **Per model and species:**
  1. A **base** illustration.
  2. A **variation** made by editing that model's own base image (late-autumn twig, head turned).
- **Total:** 40 images, estimated at a few dollars.

Prompts are in `prompts.mjs`.

## Run

```sh
GEMINI_API_KEY=... OPENAI_API_KEY=... node art/model-comparison/run.mjs
# one model / one species:
node art/model-comparison/run.mjs --only gpt-image-2.5-flare --species norcar
```

Output goes to `out/` (gitignored): PNGs plus `manifest.json`, with timing and token usage for each image.

## Scoring (1–5 each)

- **Anatomy:** correct field marks, legs, toes, and bill.
- **Style:** looks like one artist's journal across all 5 species.
- **Variation:** still the same bird and the same style after the edit.
- **Transparency:** usable cut-out with no halos.
- **Cost and speed:** taken from `manifest.json`.
