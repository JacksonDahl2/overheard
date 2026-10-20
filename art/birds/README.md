# Bird art

Hand-drawn bird illustrations for the app, one per species, as transparent PNGs in `cutouts/<code>.png`. The file name is the app's species code (from `species.json`), the same key walks store.

The first set is 50 birds commonly heard in Central Park (`species.mjs`). They're placeholders until the backend draws birds on demand (Phase 5).

## Pipeline

1. **Draw** (`generate.mjs`): `gemini-3-pro-image` with the field-journal style prompt, on a flat white background. It runs through the Batch API at half price, about $0.067 per bird.
2. **Cut out** (`cutout.swift`): Vision subject lifting removes the white, then the edges are defringed so there's no pale halo on darker pages.
3. **Review** (`review.mjs`): a local page with every bird on the page color and the darkest Candlelight color.
4. **Check against photos:** compare each drawing with a real photo of the species (field marks, colors, one bird only). When one is wrong, make its `marks` more specific and redraw it with `--redo`. The first set needed 12 redraws, mostly for a second bird, a missing trunk, or the wrong plumage.

```sh
nvm use   # Node 24
node --env-file=.env art/birds/generate.mjs --sync --species norcar   # try one bird now (full price)
node --env-file=.env art/birds/generate.mjs                           # the rest, as one batch
swift art/birds/cutout.swift art/birds/out/raw art/birds/cutouts
node art/birds/review.mjs && open art/birds/out/review.html

# Redraw birds that came out wrong, then cut them out again
node --env-file=.env art/birds/generate.mjs --redo blujay,veery
swift art/birds/cutout.swift art/birds/out/raw art/birds/cutouts --only blujay,veery
```

A batch usually takes minutes but can take hours. If the script is interrupted, rerun it and it picks the batch back up (`out/batch.json`).

## Files

- `species.mjs`: the species, their field marks, and the style prompt. Dimorphic species are drawn as the adult male in breeding plumage.
- `cutouts/`: the finished PNGs (Git LFS), at most 768 px on the long side.
- `out/`: raw drawings, the batch log and the review page (gitignored).

The illustrations belong to the project owner; they aren't covered by the code's MIT license.
