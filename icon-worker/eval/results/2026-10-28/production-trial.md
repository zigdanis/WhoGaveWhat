# Production trial validation

Danis accepted the existing result for a production trial on 2026-10-28 and authorized deployment through GitHub Actions. The 85% aspiration is not a deployment gate.

## Prompt decision

[Seeded 200-case comparison](actions-40660807139-1/study.md), with the app's RUB price question and identical cases, model, catalog, retry settings and confidence threshold:

| Variant | Accept | Stage-one reachability | USD / 1,000 |
|---|---:|---:|---:|
| Current | 74.0% | 88.0% | $1.0143 |
| Short instructions | 69.0% | 83.5% | $1.0041 |
| Compact descriptions and short instructions | 68.5% | 82.0% | $0.6379 |

Retain the current production prompt: both simpler versions lose accuracy, mainly at routing. Compact descriptions save tokens but omit useful examples. An offline hybrid estimate on the 177 shared-route cases also loses two accepted cases; it is explicitly labeled as a counterfactual in `selection.json`, not a new benchmark. No new prompt variant is shipped.

## Complete app-shaped request validation

[Full 969-case run](actions-40661681991-1/study.md), Actions [40661681991](https://github.com/zigdanis/WhoGaveWhat/actions/runs/40661681991), source `bc2591585e04452b66d7a8e6049697a4208cd627`:

- **73.4% accept (711/969)**, **62.4% top-1**; no provider errors or unknown-usage attempts.
- 24,163 mean input tokens for group + price then item; **$1.0149 per 1,000 uncached gifts** at $0.042/M input tokens. Cache hits remain free.
- Direct-provider latency on GitHub's runner: p50 **262 ms**, p90 **303 ms**. These are not deployed Worker latencies and are not comparable to the earlier local route without accounting for network differences.
- Stage one reaches an accepted option in 841/967 catalog-covered cases (**87.0%**). The final candidate is accepted in 727/841 of those (**86.4%** before confidence gating).
- Misses: 126 routing/first-stage-none, 113 item/second-stage-none, 17 confidence rejections, 2 absent glyphs. The catalog alone no longer explains most errors.

The prior 73.3% result used icon-only requests and included one provider failure. This new run includes the current app's price question; it confirms readiness rather than claiming that a shorter prompt improved accuracy. The saved old Worker answers still score 70.3% / 59.0% on the same full 969 labels. One of those titles is the single-grapheme `🚲`, rejected by the HTTP API with 400 but accepted by the direct Jev route; current reports disclose validation rejections separately. On the 968 API-valid names, old Worker accept is 70.4%, new app-shaped picker accept is 73.3% (the raw 969-case results remain unchanged).

## Delivery checks

- TypeScript, 115 Worker/evaluation tests, deterministic catalog generation and dry-run bundle.
- Swift formatting, 77 repository Python tests, secret-pattern and whitespace checks.
- Independent Opus 5.5 and GPT-6.1-Sol reviews, with their confirmed findings fixed and re-checked.
- All available raw runs, prompts, configs and partial-run formats are retained under `eval/results/`; none is ignored. No API key is saved in artifacts or repository files.

This is a backend-only change; no iOS code or API response fields change. Deployment is the existing `Icon Worker deploy` workflow, after merging the verified stack.
