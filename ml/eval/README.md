# Detection eval

This measures detection quality on the Mac using the **app's own Swift pipeline** (`apps/ios/OverheardKit`), so tuning here carries over to the phone exactly.

## Data

```sh
ml/.venv/bin/python -I ml/eval/fetch.py            # download what manifest.json lists
ml/.venv/bin/python -I ml/eval/fetch.py --rebuild  # re-query sources, rewrite manifest.json
```

- **Birds:** xeno-canto, 2 recordings each for about 22 Central Park species, quality A, 10–90 s, Northeast US first. Needs `XENO_CANTO_API_KEY` in `.env`; get a free key at https://xeno-canto.org/account.
- **Noise:** ESC-50 clips (CC BY-NC 3.0) in 13 categories: car horn, siren, engine, train, airplane, dog, footsteps, laughing, coughing, crying baby, church bells, rain, wind.

`manifest.json` is committed so every run uses the same files. `audio/` is gitignored.

## Run

```sh
swift run -c release --package-path apps/ios/OverheardKit overheard-eval [--verbose] [--json results.json]
```

The report shows these columns for each threshold, with the location filter off and on:
- **recall:** the share of bird recordings whose target species was detected.
- **precision:** correct species out of all species reported, across bird and noise files.
- **false/bird-file:** extra species reported per bird recording. Background birds the recordist listed don't count as false.
- **noise→bird:** the share of noise clips where a bird species was reported.
- **non-bird hits:** reports of BirdNET's non-bird labels (Engine, Dog, Siren, …).

`--verbose` adds a line per recording.

## Baseline (2026-10-18, before any quality work)

44 bird recordings (22 species × 2) and 26 noise clips, with 3 s clips and no overlap.

| Filter | Threshold | Recall | Precision | False/bird-file |
|---|---|---|---|---|
| off | 0.50 | 68.2% | 48.4% | 0.48 |
| on | 0.50 | 68.2% | 76.9% | 0.20 |
| on | 0.65 | 59.1% | 86.7% | 0.09 |
| on | 0.80 | 50.0% | 95.7% | 0.02 |

- **The location filter roughly doubles precision** without hurting recall. Most false species are lookalikes from other continents: Italian Sparrow, Spotless Starling, Zeledon's Antbird, Cirl Bunting.
- **Non-bird labels:** with the filter off at 0.50, they fire 11 times on the 26 noise clips: Siren, Engine, Dog, "Fireworks" for footsteps, "Human vocal".
- **Misses** are mostly recordings where the target is faint or only giving calls; the target's top clip scores under 30%.
- **Caveat:** xeno-canto is probably part of BirdNET's training data, so these numbers are likely optimistic. Real park audio is harder.
