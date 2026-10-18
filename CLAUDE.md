# Overheard: Bird Journal

An iPhone app that listens on walks, identifies birds by sound on the device (BirdNET), and draws each walk as a hand-drawn field-journal page. Friends follow each other's walks. It's free, for friends and family.

## Read first

- `todo.md`: the plan, by phase, with what's done.
- `docs/decisions.md`: what we decided and why. Add new decisions there.
- `docs/design.md`: colors, fonts, art and page-layout rules. Follow it for any UI.
- `docs/api.md`: API endpoints and conventions.
- `design/mockups/`: screen mockups (Listen, Journal page, Flock) in both themes.

## Stack

- **iOS** (`apps/ios`): SwiftUI and SwiftData, iOS 17+, and BirdNET through Core ML. The API client is generated with `swift-openapi-generator`.
- **API** (`apps/api`): Hono on Cloudflare Workers, TypeScript. It uses D1 through Drizzle, and its zod schemas generate the OpenAPI spec.
- **Art worker** (`apps/art-worker`): a Queues consumer that calls `gemini-3-pro-image` (Batch) and writes to R2.
- **Infra** (`infra/terraform`): Cloudflare R2, D1, Queues, Workers and DNS, with dev and prod environments.
- **Auth:** Sign in with Apple only.
- **Observability:** traces go to Honeycomb (OTLP from Workers), and all errors go to Sentry (iOS and Workers).

## Layout

```
apps/       ios, api, art-worker, web (later)
packages/   db (Drizzle schema + migrations), shared (zod/types), observability
infra/      terraform/{modules,envs/{dev,prod}}
ml/         BirdNET → Core ML conversion
art/        art generation scripts + prompts (model trial in art/model-comparison/)
design/     mockups
docs/       decisions, design, api
scripts/    seed data, one-off tools
```

## Conventions

- **Tooling:** Node 24 (`.nvmrc`) and pnpm workspaces. No Turborepo.
- **Local dev:** `wrangler dev`, with no Docker.
- **Secrets:** keep them in `.env` locally (gitignored) and in Worker secrets in prod. Never commit keys.
- **Images:** files live in R2; D1 stores only their keys.
- **IDs:** the phone generates walk and detection IDs, which makes uploads safe to retry.
- **Location privacy:** follow the rules in `docs/decisions.md` before exposing any location.
