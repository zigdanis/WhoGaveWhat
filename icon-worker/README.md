# Gift icon Worker

A small Cloudflare Worker that picks an emoji for a gift name with
[TypeSafe Jev](https://docs.typesafe.ai/primitives/choice). The app calls it only
after the user opts in to cloud icon suggestions. The Jev API key stays in Cloudflare;
the app holds no secret.

## API

`POST /v1/gift-icon` with `Content-Type: application/json`, an `X-Install-ID` header
(a random per-install UUID) and `{"name": "<gift name>"}`.

- `200 {"emoji": "🎸", "confidence": 0.82}`. `emoji` is `null` when no specific icon fits
  or confidence is below `MIN_CONFIDENCE`; the app then keeps its own icon.
- `400 invalid_request`: missing or malformed install ID, name outside 2–80 characters,
  body over 4 KB, or not JSON.
- `429 rate_limited` with `Retry-After`, `503 budget_exhausted` or `503 unavailable`.

`GET /health` returns `ok`. No other routes exist, so this is not a general model proxy.

## How it works

- `src/icons.ts` is the curated catalog: one Jev Choice option per icon (at most 255),
  with an English description and optional Russian hints (`JEV_RUSSIAN_HINTS`).
- `src/jev.ts` sends only the normalized gift name as the Jev `state`. Each attempt times
  out after 3 s; throttling, overload, server errors and timeouts get one retry. The
  answer must name a catalog option.
- `src/limiter.ts` is one SQLite-backed Durable Object that admits each provider call:
  per-IP per minute, global per minute, per-install per day, and daily and monthly
  budgets. Each call reserves both attempts at Jev's enforced per-request ceiling
  (`JEV_MAX_REQUEST_TOKENS`, the default 64k context; the long-context header is never
  sent) and is then charged the real `usage.input_tokens`, plus the ceiling for any
  attempt that may have been billed without reporting usage. Without a valid ceiling
  or API key the Worker fails closed.
  It caches answers for 30 days by a SHA-256 of the normalized name, catalog version,
  model and hint setting. Install IDs and IP addresses are counted under HMACs with a
  random key per UTC day, and each key is deleted after two days. Raw names, install IDs
  and IP addresses are not stored, and logs contain only model, token count and latency.
  Requests prune expired rows, and an hourly alarm does the same while the Worker is idle.

Limits and prices are `vars` in `wrangler.jsonc`. Keep TypeSafe credits prepaid with
auto-refill off, so the provider also stops at the purchased balance.

## Develop

```sh
npm ci
npx tsc --noEmit
npx vitest run
```

## Deploy and evaluate

Run the **Icon Worker deploy** workflow from GitHub Actions. It needs the
`CLOUDFLARE_API_TOKEN` (Edit Cloudflare Workers template) and `CLOUDFLARE_ACCOUNT_ID`
repository secrets. When the `JEV_API_KEY` repository secret exists, each deploy copies it
into the Worker's secrets with `wrangler secret put`; to rotate the key, update the
repository secret and run the workflow again.

With `run_eval`, the workflow runs `eval/cases.json` (Russian, English, mixed, typos,
brands, other languages and vague names) against the deployed Worker. The job summary
shows accuracy, latency and mean Jev input tokens from `wrangler tail`. The `jev_model`
and `russian_hints` inputs override the configured values for that deployment, so
variants can be compared; the next plain deploy restores `wrangler.jsonc`.
