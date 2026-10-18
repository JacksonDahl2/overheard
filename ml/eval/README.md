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
swift run -c release --package-path apps/ios/OverheardKit overheard-eval [--verbose] [--json results.json] [--no-mix]
```

A full run takes about 75 s: 110 recordings × 4 noise conditions.

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
- **Caveat:** xeno-canto is probably part of BirdNET's training data, so these numbers are likely optimistic. Real park audio is harder.
