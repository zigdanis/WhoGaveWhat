# Gift icon Worker

A small Cloudflare Worker that picks an emoji, and optionally an approximate price, for a gift name with
[TypeSafe Jev](https://docs.typesafe.ai/primitives/choice). The app calls it only
after the user opts in to cloud icon suggestions. The Jev API key stays in Cloudflare;
the app holds no secret.

## API

`POST /v1/gift-icon` with `Content-Type: application/json`, an `X-Install-ID` header
(a random per-install UUID) and `{"name": "<gift name>"}`, optionally with
`"currency": "RUB"` or `"USD"` to also get a price.

- `200 {"emoji": "🎸", "confidence": 0.82}`. `emoji` is `null` when no specific icon fits
  or confidence is below `MIN_CONFIDENCE`; the app then keeps its own icon.
- With `currency`, the answer also has `"price": 10000, "priceConfidence": 0.44`. `price` is a whole
  number in that currency, or `null` when Jev is not sure enough (`priceConfidence` below
  `MIN_PRICE_CONFIDENCE`) or gave no usable price. `priceConfidence` says how concentrated Jev's
  probability is around the estimate, from 0 for an even spread to 1, or is Jev's own confidence when
  it sent no distribution (see below). Requests without `currency` get exactly the
  icon-only answer above, so older app versions are unaffected.
- `400 invalid_request`: missing or malformed install ID, name outside 2–80 characters,
  a `currency` other than `RUB` or `USD`, body over 4 KB, or not JSON.
- `429 rate_limited`, `503 budget_exhausted` or `503 unavailable`, each with `Retry-After`: until the
  next minute or day for rate limits, the next UTC day or month for a spent budget, 30 s after a
  provider failure and 5 minutes while the Worker is misconfigured or its key is rejected.

`GET /health` returns `ok`. No other routes exist, so this is not a general model proxy.

## How it works

- `src/icons.ts` is the curated catalog: one Jev Choice option per icon (at most 255),
  with an English description and optional Russian hints (`JEV_RUSSIAN_HINTS`).
- `src/prices.ts` holds the price question: one Choice option per round price bucket in the
  currency (`rub_5000` → "About 5,000 Russian rubles"; the app keeps the same lists in
  `GiftPriceBuckets.swift`), with `PRICE_VERSION` for the cache. The buckets are ordered, so the
  estimate is the weighted median of Jev's `probabilities`, not its single top choice: for a broad
  item such as a bicycle, probability spreads over many neighbouring amounts, the top option holds
  little and Jev's own `confidence` falls to about 0, while most of the probability still lies around
  one amount. The confidence compares the probability on the median bucket and the bucket on each
  side of it with what an even spread would put there (3/15): 0 for an even spread or less, 1 when
  all of it is there. Without a usable distribution, the top choice and Jev's confidence, on the same
  0-to-1 scale, are used instead. The `jev` log line says which (`price`: `distribution`, `choice`
  or `none`). `MIN_PRICE_CONFIDENCE` is 0.05, so a price is shown unless Jev has next to no idea. When the icon is money-like
  (`money`, `banknotes`, `gift_card`, `coins`) and the name holds one clear amount ("Деньги 5000р",
  "5к", "$100"), that amount is returned as the price instead of a bucket, unsnapped and
  whatever the confidence; the currency is not converted.
- `src/jev.ts` sends only the normalized gift name as the Jev `state`; with a currency, the
  same call carries a second Choice question, `price`, next to `icon`. Each attempt times
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
  model and hint setting (and, with a currency, the price version and currency; the key for
  requests without one is unchanged). A reply that asked for a price but has no usable price answer
  is cached for only an hour, so one bad reply doesn't hide the price for a month. The cache table gained nullable `price` and
  `price_confidence` columns, added on startup to a table that predates them. Install IDs and IP addresses are counted under HMACs with a
  random key per UTC day; each key and its counters are deleted within about two days. Raw names, install IDs
  and IP addresses are not stored, and logs contain only model, token count, latency and where the price came from.
  Requests prune expired rows, and an hourly alarm does the same while the Worker is idle.

The price question adds about 15 short options, roughly 250 input tokens on top of the icon
catalog, and only to requests with a currency. The reservation per call is still the 64k request
ceiling, and the caps stay at $0.50 a day and $3 a month.

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
brands, other languages and vague names) against the deployed Worker. Cases with `rub` / `usd`
ranges are also asked for a price in each currency (`--currency RUB|USD|both`, default both),
while the icon is judged once per case. The job summary shows icon accuracy, price accuracy
(answers inside the range, plus the share of `null` prices), the misses, latency and mean Jev
input tokens from `wrangler tail`. Requests stay paced under the per-IP limit. The `jev_model`
and `russian_hints` inputs override the configured values for that deployment, so
variants can be compared; the next plain deploy restores `wrangler.jsonc`.

## Icon benchmark (unrestricted emoji)

`eval/cases1000/*.json` holds ~1,000 gift names with the ideal emoji from the whole Unicode set (not
only the catalog), so the score also shows what the catalog cannot express. `eval/bench.ts` runs a
picker over them and prints accuracy by part and tag; `eval/results/<date>/` keeps every run, committed, so changes can be tracked over time.

```sh
node --experimental-strip-types eval/bench.ts --picker ceiling          # best the current catalog could do, no requests
node --experimental-strip-types eval/bench.ts --picker cldr             # local CLDR keyword match (ru + en)
node --experimental-strip-types eval/bench.ts --picker worker --out eval/results/$(date +%F)/worker.json   # the deployed Worker, paced under its limits
JEV_API_KEY=… node --experimental-strip-types eval/bench.ts --picker jev-two-stage   # Jev over ~1,100 CLDR-described emoji
node --experimental-strip-types eval/bench.ts --compare eval/results/2026-10-27/2026-10-27-worker.json eval/results/<date>/worker.json
```

`eval/data/` has the CLDR `ru` and `en` emoji annotations and Unicode `emoji-test.txt` the local pickers use.
