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
- [ ] BirdNET location/week filter using CoreLocation — spike uses a precomputed Central Park table (`ml/species_list.py`); fix meta-model Core ML conversion or precompute a grid
- [x] Noise gating (skip inference on quiet windows) — threshold needs field tuning
- [x] Handle interruptions (calls, Siri, other audio) and resume — basic; verify on device
- [x] Background audio mode so a walk keeps listening with the screen locked — verify on device
- [ ] **Detection-quality plan** (do in this order; measure every step with the harness):
  1. [x] Eval harness (bird recordings pending xeno-canto key): labeled NYC recordings (xeno-canto) + no-bird noise clips → run the app's own Swift pipeline on the Mac → precision/recall report
  2. [x] Non-bird labels (Human vocal, Engine, Dog, Siren, Fireworks…) excluded from the tally always
  3. [ ] Overlapping windows (3 s clip every 1 s) + merge back-to-back detections into one "call" (gap > ~3 s = new call) so ×counts stay honest
  4. [ ] Confirmation: new species needs ≥0.8 in one clip or ≥0.5 in two clips within ~10 s; otherwise "maybe" (debug only)
  5. [ ] Real location filter: convert meta model to Core ML (custom op fix like `Cast`), fallback precomputed grid; replace hard 0.03 cutoff with occurrence-scaled confidence bar (common ~0.5, unusual ~0.75, very unlikely hidden) — same score drives the rare-bird flourish
  6. [ ] Adaptive noise gate (relative to recent noise floor) instead of a fixed RMS cutoff
- [ ] "Start walk" / "End walk" flow with live detection list
- [ ] Record walk route (CoreLocation) and show on MapKit
- [ ] Persist walks + detections locally with SwiftData
- [ ] Placeholder art for ~50 NYC-area species
- [ ] Journal page view: collage of birds heard on a walk + date/time/map
- [ ] Prototype a "being sketched" reveal animation when a new bird is heard
- [ ] Size birds on the page by call count (more calls → larger, capped), growing live as repeat calls come in; birds cluster closely. Applies to Listen + Journal page; Flock cards use even sizes
- [ ] Rare-bird "naturalist flourish": red-ink handwritten note + arrow (e.g. "uncommon here this late in October"); rarity from BirdNET's location/week occurrence score; also mark life birds
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
- [ ] BirdNET attribution in app
- [ ] TestFlight beta
- [ ] App Store submission

---

## Open questions

- Should the windowsill / all-day listening mode exist as an optional mode later?
- Expand beyond NYC — how is the species set / art scaled?
