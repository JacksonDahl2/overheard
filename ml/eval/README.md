# Detection eval

This measures detection quality on the Mac using the **app's own Swift pipeline** (`apps/ios/OverheardKit`), so tuning here carries over to the phone exactly.

## Data

```sh
ml/.venv/bin/python -I ml/eval/fetch.py            # download what manifest.json lists
ml/.venv/bin/python -I ml/eval/fetch.py --rebuild  # re-query sources, rewrite manifest.json
```

- **Birds:** xeno-canto, 5 recordings each for 22 Central Park species (110 total), quality A, 10–90 s, Northeast US first. Needs `XENO_CANTO_API_KEY` in `.env`; get a free key at https://xeno-canto.org/account.
- **Noise:** ESC-50 clips (CC BY-NC 3.0) in 13 categories: car horn, siren, engine, train, airplane, dog, footsteps, laughing, coughing, crying baby, church bells, rain, wind.

`manifest.json` is committed so every run uses the same files. `audio/` is gitignored.

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

- **Caveat:** xeno-canto is probably part of BirdNET's training data, so these numbers are likely optimistic. Real park audio is harder.
