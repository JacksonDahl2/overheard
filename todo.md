# Bird App — Todo

An iPhone app that listens on walks, identifies birds by sound on-device (BirdNET),
and turns each walk into an illustrated field-journal page. Social features, art
variations, and a Cloudflare backend managed with Terraform.

Inspired by [AvianVisitors](https://theodore.net/projects/AvianVisitors/).

---

## Phase 0 — Planning & decisions

- [x] Decide on monetization → free, for friends & family, no monetization (BirdNET CC BY-NC-SA 4.0 is fine with attribution)
- [x] Decide distribution → TestFlight first (public link, builds expire every 90 days); public App Store later via full App Review
- [x] Pick an app name → **Overheard: Bird Journal**
- [x] Check domain availability (2026-10-18) → unregistered: overheardbirds.app, overheardbirds.com, overheardjournal.app, overheardjournal.com, overheard.garden, overheard.studio, overheard.place (taken: overheard.app, overheard.com)
- [x] Registered **overheardbirds.app** via Cloudflare Registrar → `api.`, `img.`, universal links, privacy/support pages
- [ ] Check App Store Connect name availability (when Apple Developer account exists)
- [x] Decide minimum iOS version → iOS 17+ (SwiftData / Observation)
- [x] Decide backend language → TypeScript on Cloudflare Workers
- [x] Choose image model → **gemini-3-pro-image** via Batch API (~$0.067/img); prompt for flat white bg, then background removal (e.g. BiRefNet) for true alpha. Trial: `art/model-comparison/`
- [x] Decide art style → hand-drawn birds on parchment; the **whole app** follows this look
- [x] Define the visual system → `docs/design.md` (tokens, fonts, art + page rules)
- [x] Dark mode approach → "By Candlelight" theme (warm, dim parchment lit by candlelight); prototype alongside the light theme
- [x] Decide art format → ink + light watercolor wash on flat white, cut out to transparent PNG so birds composite onto one shared parchment page
- [ ] Species data source (later): seed from BirdNET labels / eBird taxonomy, progressively add art + species
- [x] Sketch core screens → Listen, Journal page, Flock in both themes (`design/mockups/`)
- [ ] Mock up remaining screens: Profile, Life list, Bird detail
- [x] Define data model → D1 + Drizzle; users, follows, walks, detections, species, art_variants, likes, comments, blocks, reports, push_tokens (images in R2, keys in D1)
- [x] Monorepo layout → pnpm workspaces (no Turborepo): `apps/{ios,api,art-worker,web}`, `packages/{db,shared,observability}`, `infra/terraform`, `ml/`, `art/`, `design/`, `scripts/`, `docs/`
- [x] API framework → Hono on Workers; OpenAPI generated from zod → Swift client via `swift-openapi-generator`
- [x] Auth → Sign in with Apple only (no hosted auth service; Worker verifies Apple identity tokens)
- [x] Define API surface → `docs/api.md` (OpenAPI + Swagger/Scalar at `/docs`)
- [x] Location privacy rules → shared locations snapped to a ~500 m grid; walk routes trimmed ~200 m at start/end (hides home); sensitive species (owls, etc.) show no location to others
- [ ] Set up Apple Developer account ($99/yr) — needed for TestFlight; not needed for Phase 1 (free Xcode signing on your own phone)
- [x] Set up Cloudflare account
- [x] Set up Honeycomb + Sentry accounts (free tiers)

## Phase 1 — On-device MVP (no backend)

Goal: prove the core experience works in Central Park.

- [x] Create Xcode project (SwiftUI) under `apps/ios/` (XcodeGen `project.yml`; spike UI)
- [x] Mic permission + `AVAudioSession` setup (`.record` / `.measurement` mode)
- [x] Audio capture with `AVAudioEngine` (3s windows, resampled to 48kHz)
- [x] Convert BirdNET → Core ML and bundle it (`ml/convert.py`; verified vs TensorFlow)
- [x] Run inference on audio windows; confidence threshold (smoothing: see detection-quality plan) — ~21 ms/clip on iPhone 17 Pro
- [x] BirdNET location/week filter using CoreLocation — location model converted to Core ML and runs on device (any location; approximate location is enough); recomputes on ~10 km move or new week
- [x] Noise gating (skip inference on quiet windows) — threshold needs field tuning
- [x] Handle interruptions (calls, Siri, other audio) and resume — basic; verify on device
- [x] Background audio mode so a walk keeps listening with the screen locked — verify on device
- [x] **Architecture fixes** (2026-10-18 review):
  - [x] Stable species IDs: eBird codes via `species.json`; HeardBird keyed by code
  - [x] `DetectionSession` (pure, tested) + `ListeningPipeline` actor; no `DispatchQueue.main.sync`; Swift 6 strict mode
  - [x] Eval plays recordings through `DetectionSession`, uses each recording's real location, streams audio
  - [x] Audio route changes / media-services reset handled; tap buffers copied before leaving the callback
  - [x] Built models in Git LFS (no TensorFlow needed to build); CI (tests, unsigned build, Ruff)
  - [x] FP16 evaluated and rejected (confidence shifts up to ±0.17)
  - [x] Signing team in gitignored `Config/Local.xcconfig`; BirdNET credits in the app
- [ ] **Detection-quality plan** (do in this order; measure every step with the harness):
  1. [x] Eval harness (bird recordings pending xeno-canto key): labeled NYC recordings (xeno-canto) + no-bird noise clips → run the app's own Swift pipeline on the Mac → precision/recall report
  2. [x] Non-bird labels (Human vocal, Engine, Dog, Siren, Fireworks…) excluded from the tally always
  3. [x] Overlapping windows (3 s clip every 1 s) + merge back-to-back detections into one "call" (gap > ~3 s = new call) so ×counts stay honest
  4. [x] Confirmation: a call counts when it has ≥2 clips above the threshold or one clip ≥0.70; until then the species is "pending" (the sketching bird), and it fades if the call ends unconfirmed
  5. [x] Occurrence-scaled confidence bar (`ConfidenceBar`, steep tiers +0.20/+0.40; `Commonness` on every score/bird): replace the hard 0.03 location cutoff with a bar that rises as a species gets less likely here (common ~0.5, unusual ~0.75, very unlikely hidden) — same score drives the rare-bird flourish. (Location model on device: done.)
  5b. [x] Rare-bird eval set (`ml/eval/fetch_rare.py`, 40 recordings; steep bar finds 70%, old cutoff 0%): ~20 xeno-canto recordings of species the location model rates 1–3% at their place/date (out-of-season migrants, western vagrants) — the current set has none, so the rare-bird upside is unmeasured
  6. [x] Adaptive noise gate (`AdaptiveGate`: bird-band level vs. recent background) — built and evaluated, **off by default** (cost 2–6 pts recall, most in city noise)
  6b. [ ] Measure battery on a device (Xcode energy gauge, 30+ min walk) with the gate off vs. 1.5×; turn it on only if it matters
- [x] "Start walk" / "End walk" flow with live detection list
- [x] Record walk route (CoreLocation) and show on MapKit
- [x] Persist walks + detections locally with SwiftData — save continuously during a walk (iOS can kill the app mid-walk); store species by `Species.code`
- [x] Placeholder art for ~50 NYC-area species (`art/birds/`)
- [x] Journal page view: collage of birds heard on a walk + date/time/map (first version; render-to-image is separate)
- [ ] Prototype a "being sketched" reveal animation when a new bird is heard (today: faint grayscale in a dashed red circle, easing to full color when confirmed)
- [x] New-bird alert: a light haptic (and a notification when the screen is locked) the moment a new species is confirmed on a walk; easy to turn off in Me
- [ ] Plumage variants: female and non-breeding drawings for the ~25 of the 50 birds where they differ; the page picks by date
- [x] Size birds on the page by call count (more calls → larger, capped), growing live as repeat calls come in; birds cluster closely. Applies to Listen + Journal page; Flock cards use even sizes
- [x] Rare-bird "naturalist flourish": red-ink handwritten note + arrow (e.g. "uncommon here this late in October"); rarity from BirdNET's location/week occurrence score; also mark life birds
- [ ] Render journal page to image + share sheet
- [ ] Life list (all species ever heard)
- [ ] Field test in Central Park; tune thresholds; measure battery drain

## Phase 2 — Infrastructure (Cloudflare + Terraform)

- [ ] `infra/terraform/` layout + remote state (R2 or Terraform Cloud)
- [ ] Cloudflare provider + API token setup
- [ ] R2 bucket(s): base art, variants, user journal images
- [ ] Custom domain for image delivery (e.g., `img.<domain>`)
- [ ] D1 database
- [ ] Queues: art-variation jobs
- [ ] Workers: API worker, variation worker (consumer)
- [ ] Secrets: image model API key, Apple sign-in config, APNs key
- [ ] Separate dev / prod environments
- [ ] CI: deploy Workers + run migrations (GitHub Actions)

## Phase 3 — Backend core

- [ ] pnpm workspace setup; `apps/api` (Hono) + `apps/art-worker` Workers projects (TypeScript, Wrangler)
- [ ] Local dev via `wrangler dev` (local D1/R2/Queues, logs in terminal; no Docker, no local traces)
- [ ] Dev-only flags: fake image service (placeholder art) + dev login bypass (disabled in prod)
- [ ] Seed script: sample users, walks, detections, art
- [ ] iOS Simulator → `localhost` config; physical device → Mac's LAN IP
- [ ] D1 schema + migrations with Drizzle ORM (`drizzle-kit` generates, Wrangler applies)
- [ ] Observability: enable Workers logs + tracing, export OTLP to **Honeycomb** (free tier)
- [ ] Structured logging with request/trace IDs
- [ ] iOS: OpenTelemetry Swift for network spans, send `traceparent` header to API (verify Workers continues the trace)
- [ ] Error reporting with **Sentry** (free tier) everywhere: iOS (`sentry-cocoa`) + all Workers incl. queue consumer (`@sentry/cloudflare`); traces stay in Honeycomb
- [ ] Sign in with Apple: verify identity token against Apple's JWKS, issue session tokens
- [ ] User profile endpoints (create, update, avatar)
- [ ] Upload walk + detections
- [ ] Upload journal page image to R2 (through the Worker)
- [ ] Account deletion endpoint (App Store requirement)
- [ ] Rate limiting
- [ ] iOS: networking layer, auth flow, sync local SwiftData ↔ backend

## Phase 4 — Social

- [ ] Follow / unfollow
- [ ] Feed of followed users' walks
- [ ] Likes + comments
- [ ] "Heard nearby this week" map (fuzzed locations, sensitive species hidden)
- [ ] Push notifications via APNs — **spike early** to confirm Workers can talk to APNs; fallback: OneSignal
- [ ] Moderation (App Store requirement): report content, block users, hide reported content, admin review
- [ ] Privacy settings (public / followers-only / private walks)
- [ ] Shareable walk links + universal links (`apple-app-site-association` on the domain) with web preview

## Phase 5 — Art & variations

- [ ] Generate base illustrations for launch species set
- [ ] Review base art for anatomical accuracy
- [ ] Upload base art to R2
- [ ] Variation worker: base image + context prompt (season, time of day, weather, pose) → image model → R2
- [ ] Variant pool per species (~5–10), rotated over time
- [ ] Review / approve step before variants go live
- [ ] App picks a variant per detection based on context
- [ ] Cost caps + monitoring on image generation

## Phase 6 — Polish & launch

- [ ] App icon, onboarding, empty states
- [ ] Home screen widget (today's birds / last walk)
- [ ] Privacy policy + terms (mic, location, user content)
- [ ] App Store privacy labels
- [ ] BirdNET attribution in the final UI (spike app already has it in Credits)
- [ ] TestFlight beta
- [ ] App Store submission

---

## Open questions

- Should the windowsill / all-day listening mode exist as an optional mode later?
- Expand beyond NYC — how is the species set / art scaled?
