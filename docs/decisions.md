# Decisions

What's settled, and why. Grouped by topic and kept current. When a decision changes, edit its line and note what it replaced; git history keeps the rest. Detailed numbers live in `ml/eval/README.md`. A short "don't redo without new evidence" list is in `AGENTS.md` (Settled decisions).

## Product

- **Walks, not all day.** The app listens during a walk and turns it into an illustrated journal page.
  - *Why:* Manhattan window audio is noisy and has few species; Central Park is a migration hotspot; walk sessions avoid iOS background-recording and battery problems.
- **Name:** *Overheard: Bird Journal*, at `overheardbirds.app` (Cloudflare Registrar).
- **Free, for friends and family; no monetization.** TestFlight first, the App Store later.
  - *Why:* BirdNET's models are CC BY-NC-SA 4.0, so non-commercial use only.
- **License:** code is **MIT**. The BirdNET-derived models stay CC BY-NC-SA 4.0. The bird illustrations and logo belong to the owner.
- **Location privacy:** shared points snap to a ~500 m grid; routes are trimmed ~200 m at each end; sensitive species (owls, etc.) show no location to others. Detection only needs approximate location.

## Detection (on device)

- **BirdNET v2.4 on Core ML,** with audio never leaving the phone. Both the audio and location models are converted by `ml/convert.py`, and match TensorFlow within float rounding.
  - The location model's input layer is rebuilt so it converts.
  - *Replaced:* a precomputed Central Park species table.
- **FP32 models.** *Rejected:* FP16, even with the spectrogram at FP32. It saved ~35 MB but shifted confidences by up to ±0.17.
- **Location anywhere:** approximate GPS at start, re-run after a ~10 km move or a new week. Without permission, the location filter is off and non-birds are still blocked.
- **Overlapping clips:** a 3 s clip every **1 s**. *Why:* recall +4–9 points, most in city noise.
- **"×count" = separate songs or bursts of calls:** detections ≤ 2.5 s apart merge. It drives bird size, on a capped log scale.
  - *Rejected:* minutes present, and separate visits.
- **Confirmation:** a call counts at **≥ 2 clips above its bar, or one clip ≥ max(0.70, bar + 0.15)**. Until then a new species is *pending*: the "sketching" bird, which fades if unconfirmed. *Why:* it halved wrong species per recording.
- **Operating point: base threshold 0.50 ("fewer wrong birds").**
  - *Why:* a wrong bird on a shared journal page is worse than a missed one, and pending birds still appear as sketches.
  - *Rejected:* 0.35, which gave more recall but less precision.
- **Likelihood-scaled bar** (`ConfidenceBar.standard`): +0 for common species here (≥ 10%), +0.20 for uncommon (≥ 3%), +0.40 for unusual (≥ 1%); rarer species are hidden; capped at 0.95.
  - *Why steep:* the only bar that beat the old hard cutoff on precision. On real unlikely-here birds it finds 70%, where the cutoff found 0%.
  - *Rejected:* gentler tiers (more rare birds, lower everyday precision). *Replaced:* the hard 3% cutoff.
- **Commonness** (common / uncommon / unusual) travels with every score and bird. It's the single source for the rare-bird flourish, sketch styling and life-list badges.
- **Non-birds are never reported:** BirdNET's 101 sound, frog, insect and mammal classes, identified against the eBird taxonomy.
- **Adaptive gate: built, off by default.** It skipped ~half the clips but cost 2–6 points of recall in city noise. It gets turned on only if battery measured on a device (todo 6b) says so.

## Species identity

- **Store species by stable code, never by model index.** Codes are eBird species codes (`norcar`), or `birdnet:<scientific>` for birds current eBird names differently. *Why:* indices change between model versions; saved walks, life lists, the backend and art need a stable key.
- **Split species keep BirdNET's concept.** For the 32 labels eBird has since split, the code is BirdNET's name with eBird's group code (`yelwar`) or `birdnet:<scientific>`, and the daughter species are listed in `split`.
  - *Why:* BirdNET can't tell the daughters apart, and matching by scientific name picked the wrong one (NYC's Yellow Warbler had become the tropical Mangrove Yellow Warbler).
  - A future version could pick the local daughter by location.

## Walks (on device)

- **Walks save continuously** with SwiftData: confirmed birds at once, the route at least every 30 s, everything when the app goes to the background. A walk a killed app left open is closed at its last save and marked interrupted.
  - *Why:* iOS can kill the app mid-walk, and nothing heard should be lost.
- **Birds are stored by species code only;** names come from the catalog at display time.
- **Route:** a fix is kept only if it's accurate (≤ 50 m) and at least 10 m (or the two fixes' uncertainty) from the last point, so standing still to listen doesn't add jitter distance. One encoded blob per walk, since it's only read whole.
- **Background location** (`location` background mode plus `CLBackgroundActivitySession`) keeps the route recording with the screen locked.

## Evaluation and testing

- **`overheard-eval` runs the app's exact Swift pipeline on the Mac** against labeled sets:
  - xeno-canto focal recordings
  - ESC-50 city noise, also mixed under the birds
  - a rare-bird set of real unlikely-here birds
  - annotated soundscapes, planned for call counts and timing (`docs/research/soundscape-eval.md`)
- **The eval is a list of named variants** (rules + confirmation + gate). A new experiment is one line.
- **Caveat:** xeno-canto results are optimistic, since it's likely in BirdNET's training data.
- **Logic lives in `OverheardKit`** as plain, model-free types with unit tests. App-level logic gets tests as it's built.
- **CI:** GitHub Actions runs OverheardKit tests, an unsigned iOS build, and Ruff on every PR and on `main`.

## iOS app and tooling

- **iOS 17+, SwiftUI, SwiftData; Swift 6 strict concurrency.** The pipeline is an actor (`ListeningPipeline`); the UI only sends clips and receives updates.
- **XcodeGen** generates the project from `project.yml` (the `.xcodeproj` is gitignored). The signing team lives in gitignored `Config/Local.xcconfig`.
- **Built models live in Git LFS,** so a fresh clone and CI build without TensorFlow. CI caches LFS to stay inside GitHub's free bandwidth. *Replaced:* gitignored model files.
- **Workflow:** every body of work goes on a branch and through a pull request; never commit to `main`.

## Look and art

- **One journal page view** draws both the live Listen page and a finished walk's page. Birds are placed in first-heard order by `PageLayout`, so a new bird never moves the ones already drawn; if they don't fit, everything shrinks together.
- **Notebook scatter, not a cluster:** each bird aims for its own spot (an even spread by heard order, nudged by species code) with a small tilt, and takes the nearest free space. *Replaced:* a tidy cluster around one point, which read as a grid. Sizes run from 30% (one call) to full size at 10 calls; *replaced:* 47% to 12 calls, too similar.
- **Labels move around their bird** (below, above, beside, sometimes apart with an arrow) and the arrangement is seeded by the walk, so the same species looks different on different walks.
- **Bigger birds over a fixed arrangement:** when the next bird doesn't fit, a few alternative arrangements are tried before anything shrinks, so the page can rearrange as birds arrive (the owner prefers that to small birds). Largest drawing 280 pt (70% of the page width), smallest 96 pt; a few birds may grow 1.7× to fill the page.
- **New-bird alerts** fire once per species, when it's first confirmed (never for a repeat call or a sketch): a light tap, a stronger one for unusual birds, or a notification when the phone is locked. On by default; a switch in Me.
- **Own tab bar** (not the system one) so the icons and type match the mockups; the system TabView still holds each tab's state.
- **Static font weights** bundled with the app, rather than variable fonts, so each weight has a reliable name.

- **A hand-drawn field journal on parchment, across the whole app;** the dark mode is **"By Candlelight"**. Details are in `docs/design.md`.
- **Page rules:** bird size = call count (Listen and Journal); Flock cards use even sizes; rare birds get the red-ink naturalist flourish, not a bigger size.
- **First bird art:** 50 Central Park birds, bundled with the app for now (`art/birds/cutouts`, Git LFS). Birds drawn on demand move to R2 with the backend.
  - **True-to-life color,** as in a modern field guide. *Rejected:* a "muted, faded" style; checked against photos, red birds read brown and black birds gray.
  - **Cut out with Vision** subject lifting on the Mac, then defringed (white removed from soft edges). *Rejected:* BiRefNet (a ~1 GB model download, for no gain on flat white).
  - **Every bird is checked against a real photo** before it ships; field marks in `species.mjs` are tightened when a drawing is wrong.
- **Bird art:** `gemini-3-pro-image` via the Batch API (~$0.067 per image), on flat white, then cut out to transparent PNGs.
  - *Why:* best field-journal style and variations in the trial (`art/model-comparison/`).
  - *Rejected:* OpenAI image models (halos, a digital-painting look).

## Backend (planned)

- **Cloudflare:** Workers, D1, R2, Queues, managed with Terraform. *Why:* about $5/month, no image egress fees, little infrastructure.
  - *Rejected:* AWS (cost and setup), and Go on Workers (only through WebAssembly).
- **TypeScript, Hono, Drizzle;** a pnpm monorepo without Turborepo. An OpenAPI spec from zod generates the Swift client. Endpoints are in `docs/api.md`.
- **Sign in with Apple only,** verified in the Worker. *Why:* Apple requires it whenever Google sign-in is offered, and it needs the least setup.
- **Images in R2, keys in D1;** uploads go through the Worker. Traces go to Honeycomb and all errors to Sentry. Local dev is `wrangler dev`, without Docker.
