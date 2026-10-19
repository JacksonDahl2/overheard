# Annotated soundscapes for the detection eval

Research note, 2026-10-18. The current eval (`ml/eval/`) uses xeno-canto focal recordings, which are labeled per file. It can't measure **call counts** or **time to first detection**, and it has few scenes with several birds. This note picks datasets that can, and proposes how to add them. `ml/eval/soundscapes.py` is a working prototype of the data side.

## Recommendation

Use **two CC BY 4.0 Zenodo sets**, both from the Northeastern US. Both use expert Raven boxes (start/end time, low/high frequency, species code) on long unedited recordings.

| | **SSW** (primary) | **NE parks** (secondary) | Powdermill (not now) |
|---|---|---|---|
| Name | *A collection of fully-annotated soundscape recordings from the Northeastern United States* | *Large-scale, Stratified, Fully Annotated Acoustic Forest Soundscape Dataset of Avian Vocalizations from Eastern North America* | *An annotated set of audio recordings of Eastern North American birds containing frequency, time, and species information* |
| Authors | Kahl, Charif, Klinck (Cornell), 2022 | Panwar, Cummings, Martinson, Lutz, ter Hofstede, Weed, Ayres, Symes (Dartmouth / NPS), 2025 (v2 updated 2026-05) | Chronister, Rhinehart, Place, Kitzes (Pitt), 2021; *Ecology* 102:e03329 |
| DOI | [10.5281/zenodo.7079380](https://doi.org/10.5281/zenodo.7079380) | [10.5281/zenodo.20038954](https://doi.org/10.5281/zenodo.20038954) | [10.5061/dryad.d2547d81z](https://doi.org/10.5061/dryad.d2547d81z) |
| License | CC BY 4.0 | CC BY 4.0 | CC0 1.0 (Dryad API) |
| Where | Sapsucker Woods, Ithaca NY (42.4768, −76.4527) | Acadia ME, Katahdin Woods ME, Hubbard Brook NH, Marsh-Billings VT; 104 sites | Powdermill Nature Reserve, Rector PA |
| Audio | 285 × 1 h, FLAC, 32 kHz mono 16-bit, Feb–Aug 2017, around the clock | 1,302 × 10 min, FLAC, 32 kHz mono 16-bit, May–Jul 2022–23, mostly dawn | 385 min of dawn chorus in 5-min segments, WAV + MP3, Apr–Jul 2018 |
| Size | 27.8 GB in one zip (~90 MB per hour) | 27.7 GB in 3 zips (~21 MB per file) | 1.05 GB WAV zip or 137 MB MP3 zip |
| Labels | 53,502 boxes, 81 species + `????` | 88–96 species (the record's prose and README disagree), ~183k boxes, plus chipmunk / red squirrel / deer and unknowns | 16,052 boxes, 48 species |
| Species key | **eBird codes** (2021 taxonomy); `species.csv` gives scientific + common names | 4-letter **AOU codes**; `species_metadata.csv` gives scientific names | not verified (see below) |
| Format | one `annotations.csv`: `Filename, Start Time (s), End Time (s), Low Freq (Hz), High Freq (Hz), Species eBird Code` | one Raven selection table per recording (tab-separated): `Selection, View, Channel, Begin Time (s), End Time (s), Low Freq (Hz), High Freq (Hz), Begin File, Species, Background` | "Raven-style tab-separated tables", `Recording_#_Segment_##.Table.1.selections.txt` |

**Why SSW first.** It's the closest habitat and region to NYC: suburban woods and ponds, with many city-park species. 17 of the eval's 22 Central Park species have annotations: Red-winged Blackbird 4,973 · Black-capped Chickadee 4,235 · Gray Catbird 2,943 · Northern Cardinal 2,583 · Blue Jay 2,268 · Tufted Titmouse 2,126 · Song Sparrow 1,706 · American Robin 1,493 · American Goldfinch 1,385 · Common Grackle 1,218 · Red-bellied Woodpecker 778 · Downy Woodpecker 576. It already uses eBird codes, and it covers Feb–Aug, so migration and non-dawn hours are in it. The busiest 10-minute windows hold 8–21 species.

**Why NE parks too.** Its 104 sites test whether results hold beyond one microphone and one marsh. It's dense with warblers and thrushes (Black-throated Blue Warbler 7,987, Junco 2,586, Yellow-rumped 2,347), which the eval has few of. Its 10-minute files are cheap to fetch one at a time. It's further north and more forested than NYC, so it's secondary.

**Why not Powdermill yet.** The owner remembered it correctly: it exists, and it's on **Dryad, not Zenodo**. The license (CC0) and file sizes are confirmed via the Dryad API. But scripted download failed: the API answered `401 Unauthorized, must have current bearer token` and the web download link answered `403`. So the README and annotation format are **not verified**. It's also small (6.4 h) and dawn-only. If you want it, download it in a browser, or get a free Dryad API token, then add a third adapter.

**Also checked:** Kahl et al.'s companion Zenodo sets are all CC BY 4.0 and use the same format as SSW, but none is in the East:
- Sierra Nevada: 7525805, 1.4 GB
- Hawai'i: 7078499, 5.8 GB
- Colombia / Costa Rica coffee farms: 7525349, 3.8 GB
- SW Amazon: 7079124, 2.4 GB

They'd be useful later as an out-of-region false-positive check. BirdCLEF Kaggle soundscapes weren't pursued; competition data has its own terms, and the hidden test labels aren't public.

### Verified vs. not

- **Verified via the Zenodo / Dryad APIs:** licenses, file lists, sizes and checksums for all three.
- **SSW, verified by download:** `annotations.csv` (md5 matches) and `species.csv`. I streamed the first 4 MB of `SSW_128_20170506_120007Z.flac` out of the remote zip. `afinfo` reads it as FLAC, 1 ch, 32 kHz, 16-bit, 3,600 s, and it decodes with `afconvert`. Zenodo serves HTTP ranges, so single members can be pulled out of the 27.8 GB zip.
- **NE parks, verified by download:** `ReadMe.txt`, `data_dictionary.csv`, `site_metadata.csv`, `species_metadata.csv`, and the ACAD and SIMR annotation zips.
  - I fetched one 10-min recording (`6751.38.01x.ACAD3401_20230523_050000.flac`, 21 MB) through the prototype. Its CRC checked, and `afinfo` reads 32 kHz mono, 600 s.
  - DatasetSIMR mixes HBEF, KAWW and MABI sites. Its tables are named `<rec>.Table.1.selections.txt`; the other sets use `<rec>.txt`.
- **Not verified:**
  - whether the NE parks start times are local time (assumed);
  - Powdermill's annotation columns and codes;
  - **whether BirdNET v2.4 was trained or tuned on SSW**. Kahl is a BirdNET author, and SSW-style soundscapes appeared in BirdCLEF. Treat SSW numbers as possibly optimistic, like xeno-canto. NE parks (published 2025, after v2.4) is the cleaner test.

### License notes

- **CC BY 4.0** allows any use, including in an MIT repo, with attribution. Keep audio out of git anyway, for size, the same as `ml/eval/audio/`.
- **Committing the derived manifest** (filenames, times, codes) is fine under CC BY with attribution. The manifest carries title, authors, DOI and license per dataset. Credit both datasets in `ml/eval/README.md` if this lands.
- **No NC or SA terms** on either set, unlike ESC-50 (NC) and many xeno-canto files (NC-ND / NC-SA).

## Mapping labels to our species

`species.json` (`code`, `common`, `scientific`, `bird`) has one entry per BirdNET output. **Map by scientific name, not by code.** Both datasets, like BirdNET's `labels.txt`, use pre-2025 names, but `species.json` codes come from a newer eBird taxonomy. Results for the 2 datasets:

- **SSW:** 81 of 81 species map. Only two codes differ from ours, both because of 2025 eBird splits: `yelwar` (*Setophaga petechia*) maps to our `manwar1`, and `warvir` (*Vireo gilvus*) maps to our `eawvir1`. Matching by name handles both.
- **NE parks:** 96 of 101 rows map.
  - Two need aliases, which the prototype includes: *Astur cooperii* → *Accipiter cooperii*, and *Larus smithsonianus* → *Larus argentatus*.
  - `????`, `UNMA` and `UNWO` (unknown, unknown mammal, unknown woodpecker) get `code: null`.
  - Chipmunk, red squirrel and deer map to BirdNET non-bird labels (`bird: false`), which the app never reports.
- **Scoring rule:** a box with `code: null` or `bird: false` is never a target. A detection that overlaps an unknown box is neither a TP nor an FP; drop it from both counts.

**Side finding (outside this task, worth a look):** `species.json` labels BirdNET's "Yellow Warbler" (*Setophaga petechia*) as **Mangrove Yellow Warbler** (`manwar1`), and "Herring Gull" (*Larus argentatus*) as **European Herring Gull**. So a Yellow Warbler in NYC would show under the Mangrove name. `ml/bird_labels.py` probably needs a split table that maps BirdNET's broad sense to the North American daughter (`yelwar` / American Yellow Warbler; American Herring Gull).

## Ground truth from boxes

For each recording window, per species code (bird, non-null):

- **Calls:** sort the boxes, then merge any whose gap to the previous merged span is **< 2.5 s**. That's the same constant as `DetectionSession`'s merge, stored as `call_gap` in the manifest. Each merged span is one true call, with a start, an end and a box count.
  - NE parks annotators already merged pauses under 2 s into one box, and SSW has long boxes too (p90 11.6 s, max 279 s). So boxes aren't songs, but merged spans match the app's definition of a call.
  - Across all SSW, this turns 53.5k boxes into 43.2k calls.
- **First vocalization:** the start of the first merged span. Clip it to the window start.
- **Present:** at least one call in the window.

## Metrics (per window, then pooled; filter on, at the app's default threshold)

1. **Species presence:** per-window recall and precision of the species set, the same as the current main table but on real scenes. Report it per species too, since SSW has 17 of our targets with real counts.
2. **Call-count error:** for each (window, species) present in both truth and output:
   - `app_calls − true_calls`, summarized as the median and mean absolute error (MAE) of `app/true`;
   - also the share of species within ±1 call or ±25%;
   - this is the number that drives bird size on the journal page.
3. **Call-level recall / precision:**
   - Match each confirmed app call (the time span of its clips) to a true call of that species when they overlap, allowing ±1.5 s for clip granularity.
   - Unmatched true calls are missed. Unmatched app calls are spurious, split into right species at the wrong time vs. wrong species.
4. **Detection latency:** time of the app's first *confirmed* call minus the true first vocalization. "Confirmed" means the end of the clip that confirmed it, since that's when the UI shows it. Report the median and p90 per species, plus the share never found.
5. **Windowed P/R:** split each window into 30 s bins and compute presence P/R per bin. This is less sensitive to box-boundary noise than call matching, and it's comparable to BirdCLEF-style scoring.
6. **Noise:** reuse the city-noise mix (+10 / 0 / −5 dB of ESC-50) on soundscapes. Real soundscapes have quieter birds than focal xeno-canto, so this is the realistic "park by the road" test.

## Fitting the existing eval

- **Separate file, separate kind.** `ml/eval/soundscapes-manifest.json` has top-level `"kind": "soundscape"`, `call_gap`, `datasets` (attribution) and `recordings`. `manifest.json` and `fetch.py` stay untouched, and the current tables and baselines don't move.
- **Each recording entry:**
  - `file`, `dataset`, `window: [start, end]` (seconds into the file), `date`, `time_utc` or `time_local`, `lat`, `lon`;
  - `archive` + `member` + `bytes`, for the download;
  - `annotations: [{start, end, label, scientific, code, bird}]`, with times in seconds from file start.
  - The location and date feed `LocationModel`, like the xeno-canto entries.
- **Prototype selection** (deterministic, `--rebuild`):
  - **SSW:** the 2 busiest files per month for Apr–Jul, and the 2 most species-rich 10-min windows in each. That gives 16 windows from 8 files, about 0.75 GB.
  - **NE parks:** the 3 richest recordings per zip, one per site. That gives 9 windows, about 0.2 GB.
  - In total, 25 windows (250 min) with 5,522 boxes. The manifest is 720 KB with one annotation per line.
  - The script downloads members with `bytes` / CRC verification into gitignored `ml/eval/soundscapes/`. `--summary` prints ground-truth calls per window without downloading.
- **Swift side** (not done here; another agent owns that code):
  - Add a `--soundscapes` mode to `overheard-eval` that reads this manifest.
  - Decode only `window` and play it through `ListeningPipeline` / `DetectionSession` with the 1 s hop, recording each confirmed call's clip times.
  - **Important:** `AudioDecoding.load48kMono` decodes a whole file into memory, and `clips()` copies every clip. A 1 h SSW file would be about 0.7 GB of samples and about 2 GB of clips. The mode should seek (`AVAudioFile.framePosition`) to the window and stream clips. Keep windows at 10 min.
  - Runtime: 250 min at 1 s hop is about 15k clips, so a few minutes on the Mac at the eval's current speed. Keep it opt-in, like `--no-mix` in reverse.
- **Report:** a new "Soundscapes" table (presence P/R, call-count MAE, call-level P/R, latency median/p90), plus a per-species line under `--verbose`. Add the first run as a new baseline in `ml/eval/README.md`.

## Open questions for the owner

1. **Download budget:** the default is about 1 GB. Up to 27.8 + 27.7 GB is available. More SSW windows from the same files are free once a file is downloaded; more months or files cost about 90 MB per SSW hour or 21 MB per NE parks file.
2. **Training leakage:** should SSW count toward headline numbers, given that BirdNET may have seen it? Proposal: report the two datasets separately and treat NE parks as the held-out one.
3. **Powdermill:** is a manual Dryad download (or a Dryad API token in `.env`) acceptable for a third set? It's CC0 and small, but unverified.
4. **Taxonomy fix:** should `bird_labels.py` map *Setophaga petechia* to `yelwar` (American Yellow Warbler) for this region? This affects the app, not just the eval.
