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

- `scripts/build-cldr-catalog.ts` reads the pinned CLDR English/Russian annotations and Unicode
  emoji list in `eval/data/` and generates committed `src/cldr-catalog.ts`. Wrangler runs it at build
  time; the Worker imports a module and never reads files. It keeps fully-qualified single emoji,
  excluding ZWJ sequences, skin tones, flags, components and Symbols. Smileys and People are limited
  to gift-related hearts, kisses, a robot toy, hands, body/baby/maternity care, and sporting/rest activities. Each entry retains its Unicode group/subgroup,
  both TTS names and all keywords. The pinned data and selective gift filter produce **899 emoji in
  64 subgroups**, rather than the estimated 850/49; stage one has 65 options and the largest stage
  two has 64 (including `none`). Emoji presentation selectors (U+FE0F) are preserved.
- The manual catalog and `JEV_RUSSIAN_HINTS` switch are removed: the CLDR descriptions always include
  both languages. One catalog and one picker serve production and `eval/bench.ts`, avoiding a fallback
  that silently restores the old catalog ceiling. Stable code-point keys identify emoji; the generated
  content hash in `CATALOG_VERSION` invalidates the cache when catalog/descriptions change.
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
  (💸 💵 💴 💶 💷 💳 🪙 💰) and the name holds one clear amount ("Деньги 5000р",
  "5к", "$100"), that amount is returned as the price instead of a bucket, unsnapped and
  whatever the confidence; the currency is not converted.
- `src/jev.ts` makes **two sequential requests**. Stage one chooses a Unicode subgroup plus
  `none`, with uniformly structured includes/excludes/examples in English and Russian (all actual
  CLDR TTS names appear as examples, so a rare item cannot disappear behind a short sample list); the optional
  `price` question runs alongside it. Stage two chooses only among that subgroup's emoji plus `none`.
  Instructions allow a recognizable related object, function or activity when no literal emoji exists.
  Each stage validates against exactly the options sent. `none` produces a null emoji, and the final
  confidence is the minimum of the two stage confidences; `MIN_CONFIDENCE` still gates the result.
  The price from stage one survives an icon `none`. Each attempt times out after 3 seconds and gets
  one retry for throttling, overload, server errors or network timeouts. A successful first stage is
  never repeated when the second stage retries. A shared seven-second deadline covers both stages
  and retries, keeping the response within the existing iOS client's eight-second timeout.

  [Jev evaluates questions in parallel](https://docs.typesafe.ai/primitives/choice), so sending the
  subgroup question and **every** subgroup's emoji question together could save one network round
  trip. It would send the whole catalog on every request and charge all those questions, including
  irrelevant groups. Sequential requests keep only the selected group in stage two, stay comfortably
  below the 255-option limit and reduce tokens. The tradeoff is an extra round trip and greedy routing:
  a wrong first-stage subgroup cannot be recovered in stage two. We pin `jev-1.14.0` after a 100-name pilot spread evenly across all five parts gave
  83% accept, versus 78% for `jev-1.13.0` with the same catalog and instructions. Both versions
  have the same published token price. The final comparison therefore includes the model upgrade.
- `src/limiter.ts` is one SQLite-backed Durable Object that admits each provider call:
  per-IP per minute, global per minute, per-install per day, and daily and monthly
  budgets. Each gift reserves all four possible attempts (two per stage) at Jev's enforced per-request ceiling
  (`JEV_MAX_REQUEST_TOKENS`, the default 64k context; the long-context header is never
  sent) and is then charged the real `usage.input_tokens`, plus the ceiling for any
  attempt that may have been billed without reporting usage. Known stage-one usage is charged even
  when stage two fails. `none` at stage one releases the unused second-stage reservation. Without a valid ceiling
  or API key the Worker fails closed.
  It caches answers for 30 days by a SHA-256 of the normalized name, catalog version, picker/instruction version,
  model (and, with a currency, the price version and currency). A reply that asked for a price but has no usable price answer
  is cached for only an hour, so one bad reply doesn't hide the price for a month. The cache table gained nullable `price` and
  `price_confidence` columns, added on startup to a table that predates them. Install IDs and IP addresses are counted under HMACs with a
  random key per UTC day; each key and its counters are deleted within about two days. Raw names, install IDs
  and IP addresses are not stored, and logs contain only model, token count, latency and where the price came from.
  Requests prune expired rows, and an hourly alarm does the same while the Worker is idle.

The price question adds about 15 short options, roughly 250 input tokens on top of the icon
catalog, and only to requests with a currency. Each attempt reserves the 64k request
ceiling; a gift reserves four attempts up front, and the caps stay at $0.50 a day and $3 a month.

Limits and prices are `vars` in `wrangler.jsonc`. Keep TypeSafe credits prepaid with
auto-refill off, so the provider also stops at the purchased balance.

## Develop

```sh
npm ci  # Node 24 (same as CI)
npm run build:catalog
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
input tokens from `wrangler tail`. Requests stay paced under the per-IP limit. The `jev_model` input overrides the configured model for that deployment, so
variants can be compared; the next plain deploy restores `wrangler.jsonc`.

## Icon benchmark (unrestricted emoji)

`eval/cases1000/*.json` holds ~1,000 gift names with the ideal emoji from the whole Unicode set (not
only the catalog), so the score also shows what the catalog cannot express. `eval/bench.ts` runs a
picker over them and prints accuracy by part and tag; `eval/results/<date>/` keeps every run, committed, so changes can be tracked over time.

```sh
node --experimental-strip-types eval/bench.ts --picker ceiling          # best the current catalog could do, no requests
node --experimental-strip-types eval/bench.ts --picker cldr             # local CLDR keyword match (ru + en)
mkdir -p eval/results/$(date +%F)
node --experimental-strip-types eval/bench.ts --picker worker --out eval/results/$(date +%F)/worker.json
JEV_API_KEY=… node --experimental-strip-types eval/bench.ts --picker jev-two-stage --concurrency 2 --out eval/results/$(date +%F)/jev-two-stage.json
node --experimental-strip-types eval/bench.ts --compare eval/results/2026-10-27/2026-10-27-worker.json eval/results/<date>/worker.json
```

Direct Jev runs default to one concurrent gift; `--concurrency 2` (up to 4) speeds up the run while
each gift still makes its two stages sequentially. Worker runs require concurrency 1 to respect its
rate limits. Results are checkpointed after every gift, retaining original case order.

`eval/data/` has the CLDR `ru` and `en` emoji annotations and Unicode `emoji-test.txt` the local pickers use.

Only the normalized gift name is sent as Jev state, once per stage (and again on retries); optional
currency is encoded in the price question as before. No install ID, IP, people, dates, photos or other
user data reaches Jev. Raw names are neither logged nor stored by the Worker. The new catalog consists
of public Unicode/CLDR metadata. No iOS code or API response fields change.

### Benchmark comparison

The published 2026-10-27 Worker result is **70.4% accept / 59.0% top-1** on its original 1,000 rows.
The current deduplicated benchmark contains **969 names**. For an aligned comparison, replay the last
saved Worker answer per name against the current accepted labels: **70.3% accept / 59.0% top-1**.
Production confidence thresholds apply to direct `jev-two-stage` runs too. Input tokens include both
stages; failures keep reported usage plus unknown attempts. Cost uses
[TypeSafe's $0.042 per million input tokens](https://docs.typesafe.ai/models), with output tokens free;
unknown usage is conservatively charged at 65,536 tokens per attempt. Cache hits cost no Jev tokens.


The [2026-10-28 report](eval/results/2026-10-28/README.md) contains all runs and their limits.
The final full run scored **73.3% accept / 62.5% top-1**, versus the aligned old Worker's
**70.3% / 59.0%**. Mean input was 23,665 tokens; direct latency p50/p90 was 526/628 ms;
estimated cost including unknown attempts was **$1.005 per 1,000 uncached gifts** (old direct replay:
7,952 tokens and $0.334). **The 85%+ quality target remains unmet**. Danis has accepted the current result for a production
trial; 85% remains an improvement target rather than a deployment gate. The 83% model-selection pilot is exploratory and does not replace the full result.


### Prompt experiments without deploying

The **Icon Worker deploy** workflow also has a `benchmark` selector. `compare-prompts` runs the
current prompt and two simpler variants on the same 200 names chosen by a seeded shuffle.
`full-current`, `full-short` and `full-compact` run all 969 cases with the selected variant.
Every benchmark mode skips the deploy job and uses only the existing repository `JEV_API_KEY`;
Cloudflare credentials are not supplied to that job. `none` keeps the usual deploy behavior.

```sh
gh workflow run icon-worker.yml --ref feature/jev-two-stage-cldr -f benchmark=compare-prompts
# Or locally with a privately supplied key:
node --experimental-strip-types eval/prompt-study.ts --out-dir eval/results/2026-10-28/new-study
node --experimental-strip-types eval/prompt-study.ts --dry-run
```

`eval/prompt-study.ts` calls production `chooseIcon`; variants only replace question text and
criteria descriptions, preserving every choice key and the gift-name state. Gold labels are used
only after the reply. It records stage-one reachability, stage-two choices, confidence rejections,
provider failures, tokens, cost and latency. Output directories must be new dated run folders;
results are checkpointed and partial artifacts are uploaded on failure. Download the
`icon-prompt-study` artifact and commit it under `eval/results/<date>/` after each run.

The study includes the app's price question by default (`--currency RUB`); `USD` and `none` are also
available and the choice is saved in the configuration. Regular `bench.ts` keeps its historical
icon-only default and accepts `--currency RUB|USD` when measuring the current app request.

The regular benchmark now counts failed provider requests separately from intentional `null`
answers. `--compare` re-scores the last saved answer per name against the current case names and
labels, and rejects incomplete runs, so old 1,000-row runs can be compared with the current 969.
Historical raw files and their original reports stay unchanged.


The [200-case prompt comparison](eval/results/2026-10-28/actions-40660807139-1/study.md)
uses the same random sample and RUB price question for all variants: current 74.0%, short 69.0%,
compact 68.5%. Stage-one reachability falls from 88.0% to 83.5% / 82.0%, so the current production
prompt is retained. All prompts, requests, results and selection reasoning are saved alongside the report.


[Production-trial validation](eval/results/2026-10-28/production-trial.md) confirms **73.4% accept /
62.4% top-1** on all 969 cases with the app's RUB price question, no provider errors, and an estimated
**$1.015 per 1,000 uncached gifts**. Simpler prompts were measured and rejected; the production prompt
stays unchanged. The full request/trace data is in the linked Actions run folder.
