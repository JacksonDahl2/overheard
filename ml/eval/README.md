# Detection eval

This measures detection quality on the Mac using the **app's own Swift pipeline** (`apps/ios/OverheardKit`), so tuning here carries over to the phone exactly.

## Data

```sh
ml/.venv/bin/python -I ml/eval/fetch.py            # download what manifest.json lists
ml/.venv/bin/python -I ml/eval/fetch.py --rebuild  # re-query sources, rewrite manifest.json
```

- **Birds:** xeno-canto, 5 recordings each for 22 Central Park species (110 total), quality A, 10–90 s, Northeast US first. Needs `XENO_CANTO_API_KEY` in `.env`; get a free key at https://xeno-canto.org/account.
- **Noise:** ESC-50 clips (CC BY-NC 3.0) in 13 categories: car horn, siren, engine, train, airplane, dog, footsteps, laughing, coughing, crying baby, church bells, rain, wind.

- **Rare birds** (`fetch_rare.py` → `manifest-rare.json`): 40 eastern-US xeno-canto recordings (quality A/B) of birds that BirdNET's location model rated **unlikely, 1–3%, at the place and week they were recorded**. That's the app's "unusual" tier. At most 2 per species; 24 species, e.g. late-May shorebirds and geese, rails, nightjars, woodcock. They're reported in their own table, so the main baseline stays comparable.

`manifest.json` and `manifest-rare.json` are committed so every run uses the same files. `audio/` is gitignored.

```sh
ml/.venv/bin/python -I ml/eval/fetch_rare.py            # download what manifest-rare.json lists
ml/.venv/bin/python -I ml/eval/fetch_rare.py --rebuild  # re-query and re-score with the location model
```

## Run

```sh
swift run -c release --package-path apps/ios/OverheardKit overheard-eval [--verbose] [--json results.json] [--no-mix] [--hop 1]
```

A full run takes about 3.5 minutes: 110 recordings × 4 noise conditions, with a 3 s clip every second like the app. `--hop 3` gives back-to-back clips, which is faster for quick checks.

The report also shows, for recordings where the target was found, when it was **first heard** and how many **calls** (separate songs) it counted.

**Main table** (clean recordings), for each threshold with the location filter off and on:
- **recall:** the share of bird recordings whose target species was detected.
- **precision:** correct species out of all species reported, across bird and noise files.
- **false/bird-file:** extra species reported per bird recording. Background birds the recordist listed don't count as false.
- **noise→bird:** the share of noise clips where a bird species was reported.
- **non-bird hits:** reports of BirdNET's non-bird labels (Engine, Dog, Siren, …).

**City-noise table:** each bird recording is re-scored with a continuous bed of ESC-50 noise mixed underneath. Filter on.
- **+10 dB:** the bird is clearly louder than the noise.
- **0 dB:** equally loud.
- **−5 dB:** the noise is louder.

This stands in for a walk next to traffic and people. `--no-mix` skips it, and `--verbose` adds a line per clean recording.

## Baseline (2026-10-18, before any quality work)

110 bird recordings (22 species × 5) and 26 noise clips, with 3 s clips and no overlap. The location filter is on unless noted.

| Condition | Threshold | Recall | Precision | False/bird-file |
|---|---|---|---|---|
| clean, filter **off** | 0.50 | 81.8% | 57.7% | 0.50 |
| clean | 0.50 | 80.9% | 80.9% | 0.19 |
| clean | 0.65 | 75.5% | 87.4% | 0.11 |
| clean | 0.80 | 62.7% | 92.0% | 0.05 |
| +10 dB city noise | 0.50 | 74.5% | 79.6% | 0.19 |
| 0 dB city noise | 0.50 | 74.5% | 83.7% | 0.15 |
| −5 dB city noise | 0.50 | 71.8% | 86.8% | 0.11 |

- **The location filter adds about 23 points of precision** without hurting recall. Most false species are lookalikes from other continents: Italian Sparrow, Spotless Starling, Zeledon's Antbird, Cirl Bunting.
- **City noise costs about 6–9 points of recall** at 0.50. Precision goes *up*, because noise drowns out faint lookalike hits along with faint real ones.
- **Non-bird labels:** with the filter off at 0.50, they fire 11 times on the 26 noise clips: Siren, Engine, Dog, "Fireworks" for footsteps, "Human vocal".
- **Misses** are mostly recordings where the target is faint or only giving calls.
### After step 2: non-bird labels dropped

- `SpeciesFilter` now never reports any of BirdNET's 101 non-bird labels. That's 13 sound classes plus frogs, insects and mammals, found by `ml/bird_labels.py`.
- **Filter off at 0.50:** precision 57.7% → **62.1%**, with recall unchanged.
- **Filter on:** unchanged, because the Central Park table already excluded non-birds.

### After the architecture fixes: real locations

The location filter now uses BirdNET's location model at each recording's own coordinates and date, like the app, instead of a fixed Central Park table. Recordings also play through `DetectionSession`, the app's tally logic.

| Condition | Threshold | Recall | Precision | False/bird-file |
|---|---|---|---|---|
| clean, filter off | 0.50 | 81.8% | 62.1% | 0.50 |
| clean | 0.50 | 81.8% | 76.3% | 0.25 |
| clean | 0.65 | 76.4% | 85.7% | 0.13 |
| clean | 0.80 | 62.7% | 90.8% | 0.06 |
| 0 dB city noise | 0.50 | 74.5% | 81.2% | 0.17 |
| −5 dB city noise | 0.50 | 71.8% | 84.0% | 0.11 |

- **Recall** rose slightly (80.9% → 81.8%), because birds outside Central Park's list are no longer wrongly dropped.
- **Precision** fell (80.9% → 76.3%), because the real-location expected lists are broader than the strict Central Park table, so more lookalikes get through. Steps 4–5 of the detection plan (confirmation, likelihood-scaled thresholds) target this.
- **Memory:** the eval now streams one recording at a time, with a peak of about 300 MB.

### After step 3: overlapping clips and call merging

The eval now uses a 3 s clip every 1 s instead of every 3 s. Detections of a species within 2.5 s of each other count as one call.

| Condition | Threshold | Recall (3 s → 1 s hop) | Precision (3 s → 1 s hop) |
|---|---|---|---|
| clean | 0.50 | 81.8% → **85.5%** | 76.3% → 72.9% |
| clean | 0.80 | 62.7% → **71.8%** | 90.8% → 87.8% |
| 0 dB city noise | 0.50 | 74.5% → **81.8%** | 81.2% → 75.6% |
| −5 dB city noise | 0.50 | 71.8% → **79.1%** | 84.0% → 79.8% |

- **Recall rises 4–9 points,** most in noise. Songs that straddled a clip boundary are now caught whole.
- **Precision drops 3–5 points:** three times as many clips give a stray lookalike more chances. Step 4's confirmation rule targets this, since real songs span several overlapping clips and spurious hits usually span one.
- **Calls per found bird:** the median is 3, against 1.5 before. Counts now reflect separate songs.
- **First heard:** the median is 3 s for both, because xeno-canto recordings start with the bird already singing. This metric needs real walks to be informative.

### After step 4: call confirmation (the app's current default)

A call counts once it has 2 clips above the threshold, or one clip ≥ 0.70. Otherwise the bird stays "sketching" and fades. The eval compares rules in a sweep table.

| Condition | Threshold | Recall | Precision | False/bird-file |
|---|---|---|---|---|
| clean, filter off | 0.50 | 79.1% | 67.4% | 0.38 |
| **clean** | **0.50** | **79.1%** | **83.7%** | **0.15** |
| +10 dB city noise | 0.50 | 75.5% | 83.8% | 0.15 |
| 0 dB city noise | 0.50 | 76.4% | 85.7% | 0.13 |
| −5 dB city noise | 0.50 | 75.5% | 86.5% | 0.12 |

- **Against step 3 (no confirmation):** wrong species per recording halved (0.32 → 0.15). Precision went 72.9% → 83.7% and recall 85.5% → 79.1%.
- **Rules compared** (clean, 0.50, as recall / precision):

  | Rule | Recall | Precision |
  |---|---|---|
  | none | 85.5% | 72.9% |
  | 2 clips | 78.2% | 86.9% |
  | 2 clips or 0.90 | 78.2% | 86.0% |
  | 2 clips or 0.80 | 78.2% | 84.3% |
  | **2 clips or 0.70** | 79.1% | 83.7% |
  | 3 clips or 0.80 | 73.6% | 87.1% |

  "2 clips or 0.70" won on recall in noise.
- **Option not taken:** a 0.35 threshold with the same rule gives 83.6% recall and 78.6% precision, which beats the pre-overlap baseline on both. We chose 0.50 for fewer wrong birds; see `docs/decisions.md`.

### After step 5: likelihood-scaled confidence bar (the app's current default)

Instead of "expected here (≥ 3%) or hidden", a species needs more confidence the rarer it is here this week: +0 if common (≥ 10%), +0.20 if uncommon (≥ 3%), +0.40 if unusual (≥ 1%). Species rarer than that are hidden.

| Condition | Threshold | Recall | Precision | False/bird-file |
|---|---|---|---|---|
| **clean** | **0.50** | **78.2%** | **84.3%** | **0.15** |
| +10 dB city noise | 0.50 | 75.5% | 84.7% | 0.14 |
| 0 dB city noise | 0.50 | 76.4% | 87.5% | 0.11 |
| −5 dB city noise | 0.50 | 74.5% | 88.2% | 0.10 |

Bars compared (0.50, filter on, as recall / precision):

| Bar | Clean | 0 dB city noise |
|---|---|---|
| hard cutoff (old) | 79.1% / 83.7% | 76.4% / 85.7% |
| **steep +0.20/+0.40 (chosen)** | 78.2% / **84.3%** | 76.4% / **87.5%** |
| first try +0.15/+0.30 | 79.1% / 82.9% | 76.4% / 85.7% |
| gentle +0.10/+0.20 | 79.1% / 82.1% | 76.4% / 84.0% |

- **The test set has no rare targets.** "Unusual hits" is 0 for every bar: all 110 targets are common, in-season birds where they were recorded. So this table measures only the **cost** of opening the door to rarer species, which is more lookalikes.
- **Steep is the only bar that comes out ahead of the old cutoff on precision.** The upside, clearly heard rare birds no longer hidden, needs a rare-bird eval set (todo step 5b).

### Step 5b: the rare-bird set

Real but unlikely-here birds. This is what the confidence bar exists for. Filter on:

| Bar | Recall (clean) | Recall (0 dB noise) | Precision (clean) |
|---|---|---|---|
| hard cutoff (old) | **0%** | 0% | — |
| **steep +0.20/+0.40 (default)** | **70.0%** | 60.0% | **87.5%** |
| first try +0.15/+0.30 | 72.5% | 72.5% | 85.3% |
| gentle +0.10/+0.20 | 82.5% | 75.0% | 80.5% |

- **The old cutoff hid all 40** by design. The steep bar reports 70% of them with high precision, and every one it finds is flagged `unusual`, which is what gets the flourish.
- **Gentler bars find more rare birds** but cost main-set precision (82.1% vs 84.3%), so steep stays the default.

### Step 6: adaptive gate (built, off by default)

The gate skips a clip unless its level above 1 kHz is clearly over the recent background (the lower quartile of the last 30 clips). It never skips more than 4 clips in a row, and always skips true silence. Filter on, 0.50:

| Gate | Clips skipped | Recall clean | Recall −5 dB noise | Precision clean |
|---|---|---|---|---|
| **off (app default)** | 0% | 78.2% | 74.5% | 84.3% |
| 1.5× background | 48% | 76.4% | 70.9% | 87.5% |
| 2× background | 56% | 75.5% | 68.2% | 89.2% |
| 3× background | 63% | 75.5% | 62.7% | 92.2% |

- **Real walks would skip more:** these focal recordings have a bird singing most of the time.
- **It costs recall, most in city noise:** quiet songs under traffic don't stand out from the background. The precision gain overlaps with what confirmation already does.
- **It stays off until battery is measured on a device** (todo 6b).

- **Caveat:** xeno-canto is probably part of BirdNET's training data, so these numbers are likely optimistic. Real park audio is harder.
