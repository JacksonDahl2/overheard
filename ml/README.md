# ml

Turns BirdNET v2.4 into the files the iOS app bundles.

The built files in `models/coreml/` are committed: the `.mlpackage` folders are in Git LFS. **You only need this folder's setup to regenerate them**, or to fetch eval data. The raw BirdNET downloads stay gitignored. Everything is CC BY-NC-SA 4.0; attribution is in `models/coreml/README.md`.

## Setup

```sh
cd ml
uv venv --python 3.11 .venv
uv pip install --python .venv/bin/python -r requirements.txt

# Download BirdNET v2.4 from Zenodo (record 15050749)
mkdir -p models/birdnet-v2.4 && cd models/birdnet-v2.4
curl -L -o protobuf.zip "https://zenodo.org/api/records/15050749/files/BirdNET_v2.4_protobuf.zip/content"
unzip -q protobuf.zip -d protobuf && cd ../..
```

## Regenerate the app's model files

```sh
.venv/bin/python -I convert.py       # → models/coreml/BirdNETAudio.mlpackage, BirdNETMeta.mlpackage, labels.txt
.venv/bin/python -I bird_labels.py   # → models/coreml/species.json (eBird codes; downloads the eBird taxonomy once)
.venv/bin/python -I verify.py        # Core ML vs TensorFlow, both models
```

Each regeneration adds about 100 MB to Git LFS, so only commit new models when they've actually changed.

## Notes

- **Audio model**
  - Input `inputs` is 144,000 samples (3 s at 48 kHz, mono Float32). Output `Identity` is 6,522 logits. Apply a sigmoid, with input clipped to ±15, to get confidences.
  - **Conversion fix:** BirdNET's spectrogram layer casts the complex STFT to float, which keeps the real part. coremltools can't convert that cast, so `convert.py` overrides `Cast` to map it to `complex_real`.
  - **Verified** on the BirdNET example soundscape: max logit difference 0.07, and the top species matched on all 40 clips.
- **Location model**
  - Input `location` is [latitude, longitude, week], where week is 1–48, or -1 for all year. Output `Identity` is 6,522 occurrence values, 0–1. BirdNET's default "expected here" cutoff is 0.03.
  - **Why it's rebuilt:** the original's encoding layer slices each input to a scalar and re-expands it, which coremltools mis-infers. `convert.py` rebuilds the layer with explicit shapes and loads the original dense weights.
  - **Verified:** the rebuild matches the original within 2e-5 on 500 inputs. The Core ML version agrees on 74,506 of 74,508 "expected" decisions across 300 random places.
- **Precision:** both models are FP32. FP16 saved only about 35 MB, and even with the spectrogram kept at FP32 it shifted confidences by up to ±0.17.
- **`species.json`**
  - Maps each output index to a stable species code: the eBird code, or `birdnet:<scientific>` for 32 birds current eBird names differently. It also gives the current eBird common name and a bird/non-bird flag.
  - 101 labels aren't birds: sounds, frogs, insects, mammals.
  - **Splits:** 32 species eBird has split since v2.4 (e.g. Yellow Warbler → Northern / Mangrove) keep BirdNET's broader concept: BirdNET's name, eBird's group code where one exists (`yelwar`) or `birdnet:<scientific>`, and the daughter codes in `split`. Matching by scientific name alone picked whichever daughter kept the name, so Central Park's Yellow Warblers were becoming tropical Mangrove Yellow Warblers.
  - The app stores codes, never indices.
