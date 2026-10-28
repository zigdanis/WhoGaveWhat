import { env, reset, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { IconLimiter } from "../src/limiter";
import { handle, type Env } from "../src/index";
import { ICONS, SUBGROUPS, GENERIC_KEY } from "../src/cldr-catalog";
import { emojiCriteria, groupCriteria } from "../src/catalog";
import { JEV_URL, parseAnswer, chooseIcon } from "../src/jev";
import { PRICE_BUCKETS, explicitAmount, medianBucket, priceCriteria } from "../src/prices";

const INSTALL = "3f2b8c1e-4d5a-4e6f-8a9b-0c1d2e3f4a5b";
const NOW = Date.UTC(2026, 9, 16, 12, 0, 30);
afterEach(async () => {
  await reset();
});
const iconKey = (emoji: string) => Object.keys(ICONS).find((key) => ICONS[key].emoji === emoji)!;
const guitar = () => iconKey("🎸");
const groupFor = (key: string) => Object.keys(SUBGROUPS).find((group) => SUBGROUPS[group].keys.includes(key))!;
function request(body: unknown, init: { install?: string; ip?: string; method?: string; type?: string } = {}) {
  return new Request("https://icons.test/v1/gift-icon", {
    method: init.method ?? "POST",
    headers: {
      "Content-Type": init.type ?? "application/json",
      "X-Install-ID": init.install ?? INSTALL,
      "CF-Connecting-IP": init.ip ?? "203.0.113.7",
    },
    body: init.method === "GET" ? undefined : typeof body === "string" ? body : JSON.stringify(body),
  });
}
function reply(question: "group" | "icon", choice: string, confidence = 0.9, tokens = 1000, price?: unknown) {
  return new Response(
    JSON.stringify({
      model: "jev-1.13.0",
      answers: { [question]: { choice, confidence }, ...(price !== undefined && { price }) },
      usage: { input_tokens: tokens },
    }),
  );
}
function fakeJev(...replies: Array<Response | Error>) {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const fetcher = (async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    const response = replies[Math.min(calls.length - 1, replies.length - 1)];
    if (response instanceof Error) throw response;
    return response.clone();
  }) as unknown as typeof fetch;
  return { calls, fetcher };
}
const success = (confidence = 0.9) =>
  fakeJev(reply("group", groupFor(guitar())), reply("icon", guitar(), confidence, 2500));
const deps = (fetcher: typeof fetch, now = NOW) => ({ now: () => now, fetcher, sleep: async () => {} });
const testEnv = (overrides: Partial<Env> = {}): Env => ({ ...env, ...overrides });
const attemptMicros = () => Math.ceil(65_536 * 0.042);
const usd = (micros: number) => String(micros / 1_000_000);
const usage = () => env.LIMITER.get(env.LIMITER.idFromName("global")).usage(NOW);
const body = async (response: Response) => (await response.json()) as Record<string, unknown>;

describe("two-stage gift endpoint", () => {
  it("sends only the normalized name, group plus price first, selected emoji options second", async () => {
    const group = groupFor(guitar());
    const jev = fakeJev(
      reply("group", group, 0.82, 1000, { choice: "rub_5000", confidence: 0.6 }),
      reply("icon", guitar(), 0.9, 2500),
    );
    const result = await handle(request({ name: "  электро\nгитара ", currency: "RUB" }), testEnv(), deps(jev.fetcher));
    expect(await body(result)).toEqual({ emoji: "🎸", confidence: 0.82, price: 5000, priceConfidence: 0.6 });
    expect(jev.calls).toHaveLength(2);
    for (const call of jev.calls) {
      expect(call.url).toBe(JEV_URL);
      expect(new Headers(call.init.headers).get("Authorization")).toBe("Bearer test-key");
      const sent = JSON.parse(call.init.body as string);
      expect(sent.state).toBe("электро гитара");
      expect(sent.model).toBe("jev-1.13.0");
      expect(JSON.stringify(sent)).not.toContain(INSTALL);
    }
    const first = JSON.parse(jev.calls[0].init.body as string);
    const second = JSON.parse(jev.calls[1].init.body as string);
    expect(Object.keys(first.questions)).toEqual(["group", "price"]);
    expect(first.questions.group.criteria).toEqual(groupCriteria());
    expect(first.questions.price.criteria).toEqual(priceCriteria("RUB"));
    expect(Object.keys(second.questions)).toEqual(["icon"]);
    expect(second.questions.icon.criteria).toEqual(emojiCriteria(group));
    expect((await usage()).dayMicros).toBe(147);
  });

  it("preserves the icon-only API and caches the combined answer", async () => {
    const jev = success(0.82);
    const fresh = await handle(request({ name: "Гитара" }), testEnv(), deps(jev.fetcher));
    expect(await fresh.text()).toBe('{"emoji":"🎸","confidence":0.82}');
    expect(await body(await handle(request({ name: "гитара" }), testEnv(), deps(jev.fetcher)))).toEqual({
      emoji: "🎸",
      confidence: 0.82,
    });
    expect(jev.calls).toHaveLength(2);
  });

  it("returns null for none at either stage and applies the weaker confidence", async () => {
    const none = fakeJev(reply("group", GENERIC_KEY));
    expect(await body(await handle(request({ name: "что-то" }), testEnv(), deps(none.fetcher)))).toEqual({
      emoji: null,
      confidence: 0.9,
    });
    expect(none.calls).toHaveLength(1);
    for (const [name, first, second] of [
      ["пусто", 0.9, GENERIC_KEY],
      ["неуверенно", 0.2, guitar()],
    ] as const) {
      const jev = fakeJev(reply("group", groupFor(guitar()), first), reply("icon", second));
      expect((await body(await handle(request({ name }), testEnv(), deps(jev.fetcher)))).emoji).toBeNull();
    }
  });

  it("keeps stage-one price when no icon fits; separates currency caches and retries missing prices after an hour", async () => {
    const jev = fakeJev(reply("group", GENERIC_KEY, 0.9, 1000, { choice: "usd_100", confidence: 0.7 }));
    expect(
      await body(await handle(request({ name: "подарок", currency: "USD" }), testEnv(), deps(jev.fetcher))),
    ).toEqual({ emoji: null, confidence: 0.9, price: 100, priceConfidence: 0.7 });
    const missing = fakeJev(reply("group", GENERIC_KEY));
    await handle(request({ name: "подарок", currency: "RUB" }), testEnv(), deps(missing.fetcher));
    await handle(request({ name: "подарок", currency: "RUB" }), testEnv(), deps(missing.fetcher, NOW + 3600001));
    expect(missing.calls).toHaveLength(2);
    expect((await usage()).cachedAnswers).toBe(2);
  });

  it("preserves explicit amounts for CLDR money icons", async () => {
    const money = iconKey("💸");
    const jev = fakeJev(reply("group", groupFor(money)), reply("icon", money));
    expect(
      (await body(await handle(request({ name: "Деньги 5200р", currency: "RUB" }), testEnv(), deps(jev.fetcher))))
        .price,
    ).toBe(5200);
  });

  it("rejects malformed input and configuration before spending", async () => {
    const jev = success();
    for (const value of [
      request({ name: "a" }),
      request({ name: "x".repeat(81) }),
      request({ name: 42 }),
      request("not json"),
      request({ name: "гитара", currency: "EUR" }),
      request({ name: "гитара" }, { install: "bad" }),
      request({ name: "гитара" }, { type: "text/plain" }),
      request({ name: "гитара", pad: "x".repeat(5000) }),
    ]) {
      expect((await handle(value, testEnv(), deps(jev.fetcher))).status).toBe(400);
    }
    for (const overrides of [
      { JEV_API_KEY: undefined },
      { JEV_MAX_REQUEST_TOKENS: "" },
      { JEV_PRICE_PER_MTOK_USD: "0" },
      { MIN_CONFIDENCE: "high" },
      { MIN_PRICE_CONFIDENCE: "1.5" },
      { MONTHLY_BUDGET_USD: "" },
      { DAILY_BUDGET_USD: "-1" },
      { PER_INSTALL_PER_DAY: "1.5" },
      { GLOBAL_PER_MINUTE: undefined },
    ]) {
      expect((await handle(request({ name: "гитара" }), testEnv(overrides), deps(jev.fetcher))).status).toBe(503);
    }
    expect(jev.calls).toHaveLength(0);
  });

  it("reserves four attempts before any request and refunds unused stage two", async () => {
    const reserve = attemptMicros() * 4;
    const jev = fakeJev(reply("group", GENERIC_KEY));
    expect(
      (await handle(request({ name: "первый" }), testEnv({ DAILY_BUDGET_USD: usd(reserve - 1) }), deps(jev.fetcher)))
        .status,
    ).toBe(503);
    expect(jev.calls).toHaveLength(0);
    expect(
      (await handle(request({ name: "первый" }), testEnv({ DAILY_BUDGET_USD: usd(reserve) }), deps(jev.fetcher)))
        .status,
    ).toBe(200);
    expect((await usage()).dayMicros).toBe(42);
  });

  it("retries only the failed second stage and charges unknown usage in addition to both successful stages", async () => {
    const timeout = Object.assign(new Error("timed out"), { name: "TimeoutError" });
    const jev = fakeJev(reply("group", groupFor(guitar())), timeout, reply("icon", guitar(), 0.9, 2500));
    expect((await handle(request({ name: "гитара" }), testEnv(), deps(jev.fetcher))).status).toBe(200);
    expect(jev.calls).toHaveLength(3);
    expect(JSON.parse(jev.calls[2].init.body as string)).toEqual(JSON.parse(jev.calls[1].init.body as string));
    expect((await usage()).dayMicros).toBe(147 + attemptMicros());
  });

  it("retains known first-stage tokens when the second stage fails, without caching", async () => {
    const jev = fakeJev(reply("group", groupFor(guitar())), new Response("boom", { status: 500 }));
    const result = await handle(request({ name: "гитара" }), testEnv(), deps(jev.fetcher));
    expect(result.status).toBe(503);
    expect(result.headers.get("Retry-After")).toBe("30");
    expect((await usage()).dayMicros).toBe(42 + 2 * attemptMicros());
    expect((await usage()).cachedAnswers).toBe(0);
  });

  it("does not charge rejected requests, and counts valid usage on malformed choices", async () => {
    const rejected = fakeJev(new Response("bad key", { status: 401 }));
    const result = await handle(request({ name: "гитара" }), testEnv(), deps(rejected.fetcher));
    expect(result.headers.get("Retry-After")).toBe("300");
    expect(rejected.calls).toHaveLength(1);
    expect((await usage()).dayMicros).toBe(0);
    const malformed = fakeJev(reply("group", "__proto__", 0.9, 1000));
    expect((await handle(request({ name: "гитара" }), testEnv(), deps(malformed.fetcher))).status).toBe(503);
    expect((await usage()).dayMicros).toBe(42);
  });
});

describe("stage reply validation", () => {
  const json = (question: string, choice: unknown, confidence: unknown = 0.9) => ({
    answers: { [question]: { choice, confidence } },
    usage: { input_tokens: 1000 },
  });
  it("validates each stage against only the options actually asked", () => {
    const group = groupFor(guitar());
    expect(parseAnswer(json("group", group)).key).toBe(group);
    expect(parseAnswer(json("icon", guitar()), group).key).toBe(guitar());
    expect(() => parseAnswer(json("icon", iconKey("🌹")), group)).toThrow("unknown choice");
    expect(() => parseAnswer(json("group", "toString"))).toThrow();
    expect(() => parseAnswer(json("group", group, NaN))).toThrow();
    expect(() => parseAnswer({})).toThrow();
  });
});

describe("explicit amounts", () => {
  it.each([
    ["Деньги 5000р", 5_000],
    ["5 000 ₽", 5_000],
    ["5\u00a0000₽", 5_000],
    ["сертификат на 3000", 3_000],
    ["$100", 100],
    ["5к", 5_000],
    ["5К на подарок", 5_000],
    ["5k", 5_000],
    ["10 тыс", 10_000],
    ["10 тыс.", 10_000],
    ["10 тысяч рублей", 10_000],
    ["1.5к", 1_500],
    ["1,000", 1_000],
    ["1 000 000", 1_000_000],
    ["10 000 000", 10_000_000],
    // "к" before more letters is a unit, not the thousands multiplier.
    ["5 кг", 5],
    // A year-like number counts only with a currency mark; round amounts are never years.
    ["Деньги 1897р", 1_897],
    ["$2026", 2_026],
    ["1950 рублей", 1_950],
    ["Деньги 2000", 2_000],
    ["сертификат на 1500", 1_500],
    ["Деньги 1 950", 1_950],
    ["1950 rubles", 1_950],
    ["1950 euros", 1_950],
  ])("reads %j as %i", (name, amount) => {
    expect(explicitAmount(name)).toBe(amount);
  });

  it.each([
    ["Деньги", "no number"],
    ["500 или 1000", "several numbers"],
    ["5000 + 3000", "several numbers"],
    ["12 345 678", "above 10 000 000"],
    ["20000000 ₽", "above 10 000 000"],
    ["0", "zero"],
    ["0к", "zero"],
    ["2.5", "not a whole amount"],
    ["золотая монета 1897", "a year"],
    ["конверт 2026", "a year"],
    ["купюра 1961 года", "a year"],
  ])("ignores %j (%s)", (name) => {
    expect(explicitAmount(name)).toBeNull();
  });
});

describe("limiter", () => {
  const limits = {
    monthlyBudgetMicros: 1_000_000,
    dailyBudgetMicros: 1_000_000,
    perInstallPerDay: 100,
    perIpPerMinute: 1,
    globalPerMinute: 100,
  };
  const client = { installID: INSTALL, ip: "203.0.113.7" };

  function limiter() {
    return env.LIMITER.get(env.LIMITER.idFromName("global"));
  }

  function rows(stub: ReturnType<typeof limiter>) {
    return runInDurableObject(stub, async (_instance, state) => ({
      counters: state.storage.sql
        .exec<{ scope: string; bucket: string }>("SELECT scope, bucket FROM counters")
        .toArray(),
      cache: state.storage.sql.exec("SELECT hash FROM cache").toArray().length,
      reservations: state.storage.sql.exec("SELECT id FROM reservations").toArray().length,
      keys: state.storage.sql.exec("SELECT day FROM hash_keys").toArray().length,
      alarm: await state.storage.getAlarm(),
    }));
  }

  it("adds the price columns to a cache table created before them", async () => {
    const stub = limiter();
    // The production table, as it was before prices.
    const columns = await runInDurableObject(stub, async (_instance, state) => {
      const sql = state.storage.sql;
      sql.exec("DROP TABLE cache");
      sql.exec(
        "CREATE TABLE cache (hash TEXT PRIMARY KEY, icon TEXT, confidence REAL NOT NULL, created INTEGER NOT NULL)",
      );
      sql.exec("INSERT INTO cache (hash, icon, confidence, created) VALUES ('old', 'rose', 0.8, ?)", NOW);
      return sql
        .exec<{ name: string }>("PRAGMA table_info(cache)")
        .toArray()
        .map((column) => column.name);
    });
    expect(columns).toEqual(["hash", "icon", "confidence", "created"]);

    // A fresh instance over the same storage runs the constructor again; twice must be harmless.
    const migrated = await runInDurableObject(stub, async (_instance, state) => {
      const instance = new IconLimiter(state, env);
      new IconLimiter(state, env);
      const names = state.storage.sql
        .exec<{ name: string }>("PRAGMA table_info(cache)")
        .toArray()
        .map((column) => column.name);
      return {
        names,
        cached: await instance.admit({ cacheKey: "old", ...client, now: NOW, limits, reservationMicros: 10 }),
      };
    });
    expect(migrated.names).toEqual(["hash", "icon", "confidence", "created", "price", "price_confidence"]);
    expect(migrated.cached).toEqual({
      kind: "cached",
      key: "rose",
      confidence: 0.8,
      price: null,
      priceConfidence: null,
    });
  });

  it("returns the cached price and its confidence", async () => {
    const stub = limiter();
    const admitted = await stub.admit({ cacheKey: "k1", ...client, now: NOW, limits, reservationMicros: 10 });
    if (admitted.kind !== "go") throw new Error("not admitted");
    await stub.settle({
      reservationId: admitted.reservationId,
      costMicros: 5,
      answer: { cacheKey: "k1", key: "guitar", confidence: 0.9, price: 5_000, priceConfidence: 0.4 },
      now: NOW,
    });
    const again = await stub.admit({ cacheKey: "k1", ...client, now: NOW, limits, reservationMicros: 10 });
    expect(again).toEqual({ kind: "cached", key: "guitar", confidence: 0.9, price: 5_000, priceConfidence: 0.4 });
  });

  it("keeps newer rate counters when an older request settles late", async () => {
    const stub = limiter();
    const older = await stub.admit({ cacheKey: "k1", ...client, now: NOW, limits, reservationMicros: 10 });
    const later = NOW + 60_000;
    const newer = await stub.admit({ cacheKey: "k2", ...client, now: later, limits, reservationMicros: 10 });
    expect(older.kind).toBe("go");
    expect(newer.kind).toBe("go");
    if (older.kind !== "go") return;
    await stub.settle({ reservationId: older.reservationId, costMicros: 5, now: NOW });
    const third = await stub.admit({ cacheKey: "k3", ...client, now: later, limits, reservationMicros: 10 });
    expect(third.kind).toBe("rate_limited");
  });

  it("stores no raw identifiers and counts them under a different key each day", async () => {
    const stub = limiter();
    await stub.admit({ cacheKey: "k1", ...client, now: NOW, limits, reservationMicros: 10 });
    await stub.admit({ cacheKey: "k2", ...client, now: NOW + 86_400_000, limits, reservationMicros: 10 });
    const { counters, keys } = await rows(stub);
    const installs = counters.filter((row) => row.scope.startsWith("install:")).map((row) => row.scope);
    expect(installs).toHaveLength(2);
    expect(installs[0]).not.toBe(installs[1]);
    expect(JSON.stringify(counters)).not.toContain(INSTALL);
    expect(JSON.stringify(counters)).not.toContain("203.0.113.7");
    expect(keys).toBe(2);
  });

  it("keeps check-and-increment atomic for concurrent requests", async () => {
    const stub = limiter();
    const results = await Promise.all(
      Array.from({ length: 10 }, (_, i) =>
        stub.admit({
          cacheKey: `k${i}`,
          ...client,
          now: NOW,
          limits: { ...limits, perIpPerMinute: 3 },
          reservationMicros: 10,
        }),
      ),
    );
    expect(results.filter((result) => result.kind === "go")).toHaveLength(3);
  });

  it("keeps only today's and yesterday's hash keys and day counters", async () => {
    const stub = limiter();
    const day = 86_400_000;
    await stub.admit({ cacheKey: "k1", ...client, now: NOW, limits, reservationMicros: 10 });
    await stub.admit({ cacheKey: "k2", ...client, now: NOW + day, limits, reservationMicros: 10 });
    expect((await rows(stub)).keys).toBe(2);
    await stub.admit({ cacheKey: "k3", ...client, now: NOW + 2 * day, limits, reservationMicros: 10 });
    const { counters, keys } = await rows(stub);
    expect(keys).toBe(2);
    const days = counters.filter((row) => row.scope.startsWith("install:")).map((row) => row.bucket);
    expect(days.sort()).toEqual(["2026-10-17", "2026-10-18"]);
  });

  it("prunes expired data on an alarm without further traffic", async () => {
    const stub = limiter();
    // The alarm uses the real clock, so the data is created relative to it.
    const old = Date.now() - 3 * 86_400_000;
    const admitted = await stub.admit({ cacheKey: "k1", ...client, now: old, limits, reservationMicros: 10 });
    if (admitted.kind !== "go") throw new Error("not admitted");
    await stub.settle({
      reservationId: admitted.reservationId,
      costMicros: 5,
      answer: { cacheKey: "k1", key: "rose", confidence: 0.9, price: null, priceConfidence: null },
      now: Date.now() - 31 * 86_400_000,
    });
    await stub.admit({
      cacheKey: "k2",
      ...client,
      now: old,
      limits: { ...limits, perIpPerMinute: 2 },
      reservationMicros: 10,
    });
    const before = await rows(stub);
    expect(before.alarm).not.toBeNull();
    expect(before.keys).toBe(1);

    expect(await runDurableObjectAlarm(stub)).toBe(true);
    const after = await rows(stub);
    expect(after.counters.filter((row) => row.scope !== "spend")).toEqual([]);
    expect([after.cache, after.reservations, after.keys]).toEqual([0, 0, 0]);
    // Nothing left that expires, so the alarm stops.
    expect(after.alarm).toBeNull();
  });

  it("keeps waking while data remains", async () => {
    const stub = limiter();
    await stub.admit({ cacheKey: "k1", ...client, now: Date.now(), limits, reservationMicros: 10 });
    expect(await runDurableObjectAlarm(stub)).toBe(true);
    const after = await rows(stub);
    expect(after.keys).toBe(1);
    expect(after.alarm).not.toBeNull();
  });
});

describe("price distribution", () => {
  it("takes the first bucket where half of the probability is reached", () => {
    expect(medianBucket("USD", { usd_5: 0.6, usd_10: 0.4 })).toEqual({ bucket: 5, confidence: 1 });
    expect(medianBucket("USD", { usd_100: 0.3, usd_150: 0.3, usd_200: 0.4 })).toEqual({ bucket: 150, confidence: 1 });
    // Two far-apart peaks: the median sits between them with little probability nearby.
    expect(medianBucket("RUB", { rub_300: 0.45, rub_1000: 0.1, rub_1000000: 0.45 })).toEqual({
      bucket: 1_000,
      confidence: 0,
    });
    // The top bucket has a neighbour on one side only.
    expect(medianBucket("USD", { usd_20000: 1 })).toEqual({ bucket: 20_000, confidence: 1 });
  });

  it("accepts a sum that rounding moved slightly off 1", () => {
    expect(medianBucket("USD", { usd_5: 0.52, usd_10: 0.53 })).toEqual({ bucket: 10, confidence: 1 });
  });

  it.each([
    undefined,
    null,
    "usd_5",
    {},
    { usd_5: -0.1, usd_10: 1 },
    { usd_5: "0.5", usd_10: 0.5 },
    { usd_5: 0.2 },
    { usd_5: 0.9, usd_10: 0.9 },
    { usd_5: 0.5, rub_300: 0.5 },
  ])("has no estimate for %j", (probabilities) => {
    expect(medianBucket("USD", probabilities)).toBeNull();
  });

  it("ignores options of the other currency and inherited keys", () => {
    expect(medianBucket("USD", { rub_300: 1 })).toBeNull();
    expect(medianBucket("USD", Object.create({ usd_5: 1 }))).toBeNull();
  });
});

describe("endpoint guards and accounting", () => {
  it("keeps routing, grapheme length and streamed body limits", async () => {
    const jev = success();
    expect((await handle(new Request("https://icons.test/health"), testEnv(), deps(jev.fetcher))).status).toBe(200);
    expect((await handle(new Request("https://icons.test/wrong"), testEnv(), deps(jev.fetcher))).status).toBe(404);
    expect((await handle(request({}, { method: "GET" }), testEnv(), deps(jev.fetcher))).status).toBe(405);
    expect((await handle(request({ name: "👨‍👩‍👧".repeat(80) }), testEnv(), deps(jev.fetcher))).status).toBe(200);
    let pulled = 0;
    const streamed = new Request("https://icons.test/v1/gift-icon", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Install-ID": INSTALL },
      body: new ReadableStream<Uint8Array>({
        pull(controller) {
          pulled++;
          controller.enqueue(new Uint8Array(1024));
        },
      }),
    });
    expect((await handle(streamed, testEnv(), deps(jev.fetcher))).status).toBe(400);
    expect(pulled).toBeLessThan(10);
  });

  it("retains per-install, per-IP and global rate limits and serves free cached answers", async () => {
    const jev = fakeJev(reply("group", GENERIC_KEY));
    const limited = testEnv({ PER_INSTALL_PER_DAY: "1" });
    expect((await handle(request({ name: "один" }), limited, deps(jev.fetcher))).status).toBe(200);
    expect((await handle(request({ name: "один" }), limited, deps(jev.fetcher))).status).toBe(200);
    expect((await handle(request({ name: "два" }), limited, deps(jev.fetcher))).status).toBe(429);
    const ipLimit = testEnv({ PER_IP_PER_MINUTE: "1" });
    expect((await handle(request({ name: "три" }), ipLimit, deps(jev.fetcher))).status).toBe(429);
    expect((await handle(request({ name: "три" }, { ip: "198.51.100.1" }), ipLimit, deps(jev.fetcher))).status).toBe(
      200,
    );
    expect(
      (
        await handle(
          request({ name: "четыре" }, { ip: "198.51.100.2" }),
          testEnv({ GLOBAL_PER_MINUTE: "1" }),
          deps(jev.fetcher),
        )
      ).status,
    ).toBe(429);
    expect((await handle(request({ name: "два" }), limited, deps(jev.fetcher, NOW + 86400000))).status).toBe(200);
  });

  it("enforces monthly spend across days at the full two-stage reservation", async () => {
    const jev = fakeJev(reply("group", GENERIC_KEY));
    const tight = testEnv({ MONTHLY_BUDGET_USD: usd(4 * attemptMicros() + 40) });
    expect((await handle(request({ name: "один" }), tight, deps(jev.fetcher))).status).toBe(200);
    expect((await handle(request({ name: "два" }), tight, deps(jev.fetcher, NOW + 86400000))).status).toBe(503);
    expect((await handle(request({ name: "три" }), tight, deps(jev.fetcher, Date.UTC(2026, 10, 1)))).status).toBe(200);
  });

  it("charges unreadable replies conservatively and refunds rejected overloads", async () => {
    const malformed = fakeJev(new Response("not JSON"));
    expect((await handle(request({ name: "один" }), testEnv(), deps(malformed.fetcher))).status).toBe(503);
    expect(malformed.calls).toHaveLength(1);
    expect((await usage()).dayMicros).toBe(attemptMicros());
    const overloaded = fakeJev(new Response("busy", { status: 529 }), reply("group", GENERIC_KEY));
    expect((await handle(request({ name: "два" }), testEnv(), deps(overloaded.fetcher))).status).toBe(200);
    expect((await usage()).dayMicros).toBe(attemptMicros() + 42);
    const stalled = new Response(
      new ReadableStream({
        start(controller) {
          controller.error(Object.assign(new Error("timed out"), { name: "TimeoutError" }));
        },
      }),
    );
    const delayed = fakeJev(stalled, reply("group", GENERIC_KEY));
    expect((await handle(request({ name: "три" }), testEnv(), deps(delayed.fetcher))).status).toBe(200);
    expect((await usage()).dayMicros).toBe(2 * attemptMicros() + 84);
  });

  it("reapplies icon and price thresholds to cached results", async () => {
    const jev = fakeJev(
      reply("group", groupFor(guitar()), 0.9, 1000, { choice: "rub_5000", confidence: 0.4 }),
      reply("icon", guitar(), 0.7),
    );
    await handle(request({ name: "гитара", currency: "RUB" }), testEnv(), deps(jev.fetcher));
    expect(
      await body(
        await handle(
          request({ name: "гитара", currency: "RUB" }),
          testEnv({ MIN_CONFIDENCE: "0.8", MIN_PRICE_CONFIDENCE: "0.5" }),
          deps(jev.fetcher),
        ),
      ),
    ).toEqual({ emoji: null, confidence: 0.7, price: null, priceConfidence: 0.4 });
    expect(jev.calls).toHaveLength(2);
  });
});

describe("shared request deadline", () => {
  it("does not begin a retry after the shared deadline and keeps prior-stage usage", async () => {
    const jev = fakeJev(reply("group", groupFor(guitar())), new Response("busy", { status: 529 }));
    let slept = false;
    await expect(
      chooseIcon("guitar", {
        apiKey: "test-key",
        model: "jev-1.13.0",
        attemptTimeoutMs: 3000,
        maxAttempts: 2,
        totalTimeoutMs: 50,
        fetcher: jev.fetcher,
        sleep: async () => {
          slept = true;
          await new Promise((resolve) => setTimeout(resolve, 70));
        },
      }),
    ).rejects.toMatchObject({ inputTokens: 1000, unknownUsageAttempts: 0 });
    expect(slept).toBe(true);
    expect(jev.calls).toHaveLength(2);
  });

  it("accumulates an unknown first attempt and a malformed second-stage answer with known usage", async () => {
    const jev = fakeJev(
      new Error("network"),
      reply("group", groupFor(guitar())),
      reply("icon", "not_asked", 0.9, 2500),
    );
    expect((await handle(request({ name: "guitar" }), testEnv(), deps(jev.fetcher))).status).toBe(503);
    expect((await usage()).dayMicros).toBe(147 + attemptMicros());
    expect((await usage()).cachedAnswers).toBe(0);
  });
});
