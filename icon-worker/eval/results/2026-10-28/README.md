# Two-stage CLDR gift icon benchmark — 2026-10-28

**Quality target not met:** final accept is **73.3%**, versus **70.3%** for the saved Worker answers rescored on the same 969 unique names. This is +3.0 percentage points, short of the requested 85%+ target. Of the old misses, 160 are fixed, while 131 previously accepted answers regress (net +29). The change remains a draft for quality review.

| Metric | Before | After |
|---|---:|---:|
| Cases, aligned current labels | 969 | 969 |
| Accept | 70.3% (681/969) | 73.3% (710/969) |
| Top-1 | 59.0% | 62.5% |
| Null emoji | 6.0% | 13.5% |
| Mean input tokens per uncached gift | 7,952¹ | 23,665 |
| Direct Jev latency p50 / p90 | 249 / 298 ms¹ | 526 / 628 ms |
| Estimated USD / 1,000 uncached gifts | $0.334¹ | $1.005 |
| Model | jev-1.13.0 | jev-1.14.0 |
| Provider requests per gift, excluding retries | 1 | 1–2 |

¹ Token/cost and direct latency for the old picker were measured by replaying its original `criteria(true)` over 30 evenly spaced current names. The original saved Worker run has no token usage; its aligned end-to-end Worker latency is p50 540 ms / p90 643 ms. The new run calls production `chooseIcon` directly, bypassing the Worker cache, limiter and network hop; no new Worker deployment was made. Thus these are provider-path latency measurements, not a deployed end-to-end comparison. All accuracy figures use the full aligned 969-case data, not that 30-case sample.

The original published Worker report contains 1,000 rows and scored 70.4% accept / 59.0% top-1. `2026-10-28-worker-matched.json` takes the last saved answer per unique name and re-scores it against the current 969 labels. Its `source` points at the moved `../2026-10-27/2026-10-27-worker.json`.

## Final configuration and limits

- Catalog `cldr-e074edda57dd`: 899 emoji, 64 Unicode subgroups, largest subgroup 63; Choice has 65 stage-one options and at most 64 stage-two options with `none`.
- Picker `jev-two-stage-v2`, pinned `jev-1.14.0`, confidence threshold 0.35 using the minimum of both stage confidences; explicit `none` returns null. Each gift runs stages sequentially; the benchmark used two concurrent gifts and 300 ms pacing per runner.
- First-stage examples enumerate every actual CLDR TTS name in both languages. Emoji options contain their English/Russian TTS names and all keywords. Instructions permit a related object, function or activity when no literal emoji exists. All source/generated emoji retain required U+FE0F selectors.
- One retry per stage, 3-second per-attempt timeout, shared 7-second deadline including backoff. Four possible attempts are reserved at 65,536 tokens each. Actual reported tokens from both stages survive later failures; unknown usage is conservatively charged at that ceiling.
- Final run: one failed gift request, four attempts with unknown usage (retained in accuracy and cost). Cost uses $0.042/M input tokens and free output tokens: `(sum(inputTokens) + 65,536 * unknownUsageAttempts) / n * 1,000 * 0.042 / 1,000,000`. Cache hits use no Jev tokens.
- Catalog ceiling is now 99.8% accept / 99.2% top-1 on 969 cases. Most remaining misses are routing, representative-icon choice and low confidence, rather than absent glyphs. Examples include books/tickets choosing a different valid variant, pet supplies mapped to food or toys instead of pets, and appliances lacking a literal glyph.
- The model comparison pilot sampled indices `floor(i * 968 / 99)` for `i=0…99`: same catalog/instructions yielded 78% on 1.13 and 83% on 1.14. That exploratory sample overestimated full-run accuracy; the full-run result above is authoritative. Both models have the same published token price.

Reproduce from `icon-worker/` with Node 24 and a privately supplied `JEV_API_KEY`:

```sh
node --experimental-strip-types eval/bench.ts --picker jev-two-stage --concurrency 2 --out eval/results/2026-10-28/replay.json
node --experimental-strip-types eval/bench.ts --compare eval/results/2026-10-28/2026-10-28-worker-matched.json eval/results/2026-10-28/2026-10-28-jev-two-stage.json
```

[TypeSafe model pricing/context](https://docs.typesafe.ai/models), [Choice and parallel questions](https://docs.typesafe.ai/primitives/choice).

## Saved runs

Every run is committed under this date; nothing in `eval` is ignored.

- `2026-10-28-jev-two-stage.json` / `.md`: final full run, production code/catalog/threshold, 969 cases.
- `2026-10-28-worker-matched.json` / `.md`: saved old Worker answers aligned to current 969 names/labels.
- `2026-10-28-ceiling.json` / `.md`: current catalog's theoretical coverage, no network calls.
- `2026-10-28-legacy-cost-sample.json`: 30-name direct legacy replay for tokens and provider latency.
- `pilot-jev-1.13.0.json`, `pilot-jev-1.14.0.json`: 100-name model pilot with both stage distributions. `2026-10-28-model-pilot-100.json` is its compact comparison.
- `2026-10-28-price-probe.json`: real shared-picker RUB/USD probes. Stage-one price distributions produced RUB 5,000 and USD 200 for “гитара”.
- `jev-two-stage-smoke.json` / `.md`: initial 100-case smoke, 78% accept, before later catalog/instruction/model changes.
- `jev-two-stage-initial-partial.json`: interrupted exploratory initial run, 282 cases; not used in the final comparison.
- `jev-two-stage-literal.json` / `.md`: complete earlier literal-depiction configuration, 65.9% accept; retained to show the effect of routing instructions and care/sport eligibility changes.

## Privacy and validation

Only the gift name is user text sent to Jev, now once per stage and again on a retry; optional currency remains encoded in the static price question. Install IDs, IPs, people, dates and photos stay outside Jev. The Worker stores/logs no raw gift names. Public Unicode/CLDR metadata supplies the enlarged catalog. No iOS code or response fields changed, and no deployment was dispatched.

Local validation: `npx tsc --noEmit`, `npx vitest run` (91 passing tests), deterministic generator `--check`, Wrangler dry-run bundle (658.88 KiB / 97.93 KiB gzip), Swift formatting, repository Python tests (77), and secret-pattern check. Independent Opus 5.5 and GPT-6.1-Sol re-checks found no remaining correctness bugs.
