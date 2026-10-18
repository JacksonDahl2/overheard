# ml

Turns BirdNET v2.4 into files the iOS app bundles. The model files are CC BY-NC-SA 4.0 and gitignored, so rebuild them locally.

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

## Build the app's model files

```sh
.venv/bin/python -I convert.py        # → models/coreml/BirdNETAudio.mlpackage + labels.txt
.venv/bin/python -I species_list.py   # → models/coreml/species-central-park.json
.venv/bin/python -I verify.py         # compare Core ML vs TensorFlow on a 48 kHz mono WAV
```

To build a species list for another place: `species_list.py <lat> <lon> <name>`.

## Notes

- **Audio model.** Input is 144,000 samples (3 s at 48 kHz, mono Float32). Output `Identity` is 6,522 logits. Apply a sigmoid, with input clipped to ±15, to get confidences.
- **Conversion fix.** BirdNET's spectrogram layer casts the complex STFT to float, which keeps the real part. coremltools can't convert that cast, so `convert.py` overrides `Cast` to map it to `complex_real`. Verified on the BirdNET example soundscape: max logit difference 0.07, and the top species matched on all 40 clips.
- **Location model.** This model doesn't convert yet: it fails in coremltools' `ExpandDims` on a scalar. `species_list.py` precomputes its output (threshold 0.03) for each of the 48 weeks instead.
