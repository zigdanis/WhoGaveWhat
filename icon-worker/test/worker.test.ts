import { env, reset, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { handle, type Env } from "../src/index";
import { ICON_KEYS, ICONS, criteria } from "../src/icons";
import { JEV_URL, parseAnswer } from "../src/jev";

const INSTALL = "3f2b8c1e-4d5a-4e6f-8a9b-0c1d2e3f4a5b";
const NOW = Date.UTC(2026, 9, 16, 12, 0, 30);

afterEach(async () => {
  await reset();
});

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

function jevReply(choice: string, confidence = 0.9, inputTokens = 2_500, status = 200) {
  return new Response(
    JSON.stringify({
      model: "jev-1.13.0",
      answers: { icon: { type: "choice", choice, confidence, probabilities: {} } },
      usage: { input_tokens: inputTokens, output_tokens: 10 },
    }),
    { status, headers: { "Content-Type": "application/json" } },
  );
}

/** A fake Jev endpoint recording every call. */
function fakeJev(...replies: Array<Response | Error>) {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const fetcher = (async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    const reply = replies[Math.min(calls.length - 1, replies.length - 1)];
    if (reply instanceof Error) throw reply;
    return reply.clone();
  }) as unknown as typeof fetch;
  return { calls, fetcher };
}

function deps(fetcher: typeof fetch, now = NOW) {
  return { now: () => now, fetcher, sleep: async () => {} };
}

function testEnv(overrides: Partial<Env> = {}): Env {
  return { ...env, ...overrides };
}

/** One attempt reserved at the 65,536-token request ceiling: 2,753 micro-dollars. */
function attemptMicros(_name?: string) {
  return Math.ceil(65_536 * 0.042);
}

function usd(micros: number) {
  return String(micros / 1_000_000);
}

async function usage() {
  return env.LIMITER.get(env.LIMITER.idFromName("global")).usage(NOW);
}

async function body(response: Response) {
  return (await response.json()) as Record<string, unknown>;
}

describe("catalog", () => {
  it("fits one Jev choice question and every icon is a single emoji", () => {
    expect(ICON_KEYS.length).toBeGreaterThan(150);
    expect(ICON_KEYS.length).toBeLessThanOrEqual(255);
    const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
    for (const [key, icon] of Object.entries(ICONS)) {
      expect(key).toMatch(/^[a-z][a-z_]*$/);
      expect([...segmenter.segment(icon.emoji)].length, key).toBe(1);
      expect(icon.description.length, key).toBeGreaterThanOrEqual(3);
    }
  });

  it("adds Russian hints only when asked", () => {
    expect(criteria(false).guitar).toBe("Guitar or ukulele");
    expect(criteria(true).guitar).toBe("Guitar or ukulele (гитара, укулеле)");
  });
});

describe("gift icon endpoint", () => {
  it("asks Jev with only the gift name and returns the chosen emoji", async () => {
    const jev = fakeJev(jevReply("guitar", 0.82));
    const response = await handle(request({ name: "  электро\nгитара  " }), testEnv(), deps(jev.fetcher));

    expect(response.status).toBe(200);
    expect(await body(response)).toEqual({ emoji: "🎸", confidence: 0.82 });
    expect(jev.calls).toHaveLength(1);
    expect(jev.calls[0].url).toBe(JEV_URL);
    const headers = new Headers(jev.calls[0].init.headers);
    expect(headers.get("Authorization")).toBe("Bearer test-key");
    const sent = JSON.parse(jev.calls[0].init.body as string);
    expect(sent.state).toBe("электро гитара");
    expect(sent.model).toBe("jev-1.13.0");
    expect(sent.questions.icon.type).toBe("choice");
    expect(Object.keys(sent.questions.icon.criteria)).toEqual(ICON_KEYS);
    expect(JSON.stringify(sent)).not.toContain(INSTALL);
  });

  it("returns no emoji for the generic option or a low-confidence answer", async () => {
    const generic = await handle(request({ name: "что-то" }), testEnv(), deps(fakeJev(jevReply("generic_gift")).fetcher));
    expect(await body(generic)).toEqual({ emoji: null, confidence: 0.9 });

    const unsure = await handle(request({ name: "штука" }), testEnv(), deps(fakeJev(jevReply("guitar", 0.2)).fetcher));
    expect(await body(unsure)).toEqual({ emoji: null, confidence: 0.2 });
  });

  it("serves repeated names from the cache without calling Jev again", async () => {
    const jev = fakeJev(jevReply("rose"));
    await handle(request({ name: "Розы" }), testEnv(), deps(jev.fetcher));
    const second = await handle(request({ name: "розы", }, { install: "11111111-2222-4333-8444-555555555555" }), testEnv(), deps(jev.fetcher));

    expect(await body(second)).toEqual({ emoji: "🌹", confidence: 0.9 });
    expect(jev.calls).toHaveLength(1);
  });

  it("rejects malformed requests before spending anything", async () => {
    const jev = fakeJev(jevReply("rose"));
    const cases: Request[] = [
      request({ name: "a" }),
      request({ name: "x".repeat(81) }),
      request({ name: 42 }),
      request("not json"),
      request({ name: "розы" }, { install: "not-a-uuid" }),
      request({ name: "розы" }, { type: "text/plain" }),
      request({ name: "розы", pad: "x".repeat(5_000) }),
    ];
    for (const bad of cases) {
      const response = await handle(bad, testEnv(), deps(jev.fetcher));
      expect(response.status).toBe(400);
    }
    expect(jev.calls).toHaveLength(0);
  });

  it("counts length in characters, so 80 emoji-rich characters are accepted", async () => {
    const name = "👨‍👩‍👧".repeat(80);
    const response = await handle(request({ name }), testEnv(), deps(fakeJev(jevReply("party")).fetcher));
    expect(response.status).toBe(200);
  });

  it("only serves the gift icon route", async () => {
    const jev = fakeJev(jevReply("rose"));
    expect((await handle(new Request("https://icons.test/v1/systemone", { method: "POST" }), testEnv(), deps(jev.fetcher))).status).toBe(404);
    expect((await handle(request({}, { method: "GET" }), testEnv(), deps(jev.fetcher))).status).toBe(405);
    expect((await handle(new Request("https://icons.test/health"), testEnv(), deps(jev.fetcher))).status).toBe(200);
  });

  it("fails closed without an API key or with any invalid limit setting", async () => {
    const jev = fakeJev(jevReply("rose"));
    const broken: Partial<Env>[] = [
      { JEV_API_KEY: undefined },
      { JEV_MAX_REQUEST_TOKENS: "" },
      { JEV_MAX_REQUEST_TOKENS: "lots" },
      { JEV_PRICE_PER_MTOK_USD: "0" },
      { MIN_CONFIDENCE: "high" },
      { MONTHLY_BUDGET_USD: "" },
      { DAILY_BUDGET_USD: "-1" },
      { PER_INSTALL_PER_DAY: "1.5" },
      { PER_IP_PER_MINUTE: "many" },
      { GLOBAL_PER_MINUTE: undefined as unknown as string },
    ];
    for (const overrides of broken) {
      const response = await handle(request({ name: "розы" }), testEnv(overrides), deps(jev.fetcher));
      expect(response.status).toBe(503);
      expect(response.headers.get("Retry-After")).toBe("300");
      expect(await body(response)).toEqual({ error: "unavailable" });
    }
    expect(jev.calls).toHaveLength(0);
  });

  it("retries one overload, then succeeds", async () => {
    const jev = fakeJev(new Response("busy", { status: 529 }), jevReply("birthday_cake"));
    const response = await handle(request({ name: "торт" }), testEnv(), deps(jev.fetcher));
    expect(await body(response)).toEqual({ emoji: "🎂", confidence: 0.9 });
    expect(jev.calls).toHaveLength(2);
  });

  it("does not retry client errors and maps failures to 503", async () => {
    const jev = fakeJev(new Response("bad key", { status: 401 }));
    const response = await handle(request({ name: "торт" }), testEnv(), deps(jev.fetcher));
    expect(response.status).toBe(503);
    // A provider failure may pass quickly, so clients are asked to wait only briefly.
    expect(response.headers.get("Retry-After")).toBe("30");
    expect(jev.calls).toHaveLength(1);
  });

  it("gives up after two attempts on repeated timeouts", async () => {
    const timeout = Object.assign(new Error("timed out"), { name: "TimeoutError" });
    const jev = fakeJev(timeout);
    const response = await handle(request({ name: "торт" }), testEnv(), deps(jev.fetcher));
    expect(response.status).toBe(503);
    expect(jev.calls).toHaveLength(2);
  });

  it("rejects an answer outside the catalog and does not cache it", async () => {
    const jev = fakeJev(jevReply("__proto__"), jevReply("birthday_cake"));
    expect((await handle(request({ name: "торт" }), testEnv(), deps(jev.fetcher))).status).toBe(503);
    expect(await body(await handle(request({ name: "торт" }), testEnv(), deps(jev.fetcher)))).toEqual({ emoji: "🎂", confidence: 0.9 });
  });

  it("limits each install per day", async () => {
    const jev = fakeJev(jevReply("rose"));
    const limited = testEnv({ PER_INSTALL_PER_DAY: "2" });
    for (const name of ["розы", "тюльпаны"]) {
      expect((await handle(request({ name }), limited, deps(jev.fetcher))).status).toBe(200);
    }
    const third = await handle(request({ name: "ромашки" }), limited, deps(jev.fetcher));
    expect(third.status).toBe(429);
    expect(Number(third.headers.get("Retry-After"))).toBe(12 * 3600 - 30);
    // Another install is unaffected, and the next day the first one may ask again.
    const other = request({ name: "ромашки" }, { install: "11111111-2222-4333-8444-555555555555" });
    expect((await handle(other, limited, deps(jev.fetcher))).status).toBe(200);
    expect((await handle(request({ name: "лилии" }), limited, deps(jev.fetcher, NOW + 86_400_000))).status).toBe(200);
  });

  it("limits each IP per minute", async () => {
    const jev = fakeJev(jevReply("rose"));
    const limited = testEnv({ PER_IP_PER_MINUTE: "1" });
    expect((await handle(request({ name: "розы" }), limited, deps(jev.fetcher))).status).toBe(200);
    const second = await handle(request({ name: "тюльпаны" }), limited, deps(jev.fetcher));
    expect(second.status).toBe(429);
    expect(second.headers.get("Retry-After")).toBe("30");
    expect((await handle(request({ name: "тюльпаны" }, { ip: "198.51.100.1" }), limited, deps(jev.fetcher))).status).toBe(200);
  });

  it("stops calling Jev once the daily budget is spent, using real token usage", async () => {
    // Each call reserves two attempts at their upper bound and really costs 2,500 × 0.042 = 105.
    const reserve = 2 * attemptMicros("a1");
    const tight = testEnv({ DAILY_BUDGET_USD: usd(105 * 3 + reserve) });
    const jev = fakeJev(jevReply("rose", 0.9, 2_500));
    const statuses: number[] = [];
    for (const name of ["a1", "a2", "a3", "a4", "a5", "a6"]) {
      statuses.push((await handle(request({ name }), tight, deps(jev.fetcher))).status);
    }
    expect(statuses).toEqual([200, 200, 200, 200, 503, 503]);
    expect(jev.calls).toHaveLength(4);
    expect((await usage()).dayMicros).toBe(420);
    // Cached names stay free even when the budget is exhausted.
    expect((await handle(request({ name: "a1" }), tight, deps(jev.fetcher))).status).toBe(200);
    // A spent daily budget asks clients to wait until the next UTC day.
    const exhausted = await handle(request({ name: "a7" }), tight, deps(jev.fetcher));
    expect(exhausted.headers.get("Retry-After")).toBe(String(12 * 3600 - 30));
  });

  it("enforces the monthly budget across days", async () => {
    const tight = testEnv({ MONTHLY_BUDGET_USD: usd(2 * attemptMicros("b1") + 50) });
    const jev = fakeJev(jevReply("rose", 0.9, 2_500));
    expect((await handle(request({ name: "b1" }), tight, deps(jev.fetcher))).status).toBe(200);
    const exhausted = await handle(request({ name: "b2" }), tight, deps(jev.fetcher, NOW + 86_400_000));
    expect(exhausted.status).toBe(503);
    // A spent monthly budget asks clients to wait until the next UTC month.
    expect(exhausted.headers.get("Retry-After")).toBe(String((Date.UTC(2026, 10, 1) - NOW - 86_400_000) / 1000));
    expect((await handle(request({ name: "b3" }), tight, deps(jev.fetcher, Date.UTC(2026, 10, 1)))).status).toBe(200);
  });

  it("charges failed attempts that may have been billed at their upper bound", async () => {
    const reserve = 2 * attemptMicros("c1");
    const tight = testEnv({ DAILY_BUDGET_USD: usd(3 * reserve - 1) });
    const failing = fakeJev(new Response("boom", { status: 500 }));
    expect((await handle(request({ name: "c1" }), tight, deps(failing.fetcher))).status).toBe(503);
    expect((await handle(request({ name: "c2" }), tight, deps(failing.fetcher))).status).toBe(503);
    expect((await usage()).dayMicros).toBe(2 * reserve);
    const ok = fakeJev(jevReply("rose"));
    expect(await body(await handle(request({ name: "c3" }), tight, deps(ok.fetcher)))).toEqual({ error: "budget_exhausted" });
    expect(ok.calls).toHaveLength(0);
  });

  it("charges a timed-out attempt in addition to the successful retry", async () => {
    const timeout = Object.assign(new Error("timed out"), { name: "TimeoutError" });
    const jev = fakeJev(timeout, jevReply("rose", 0.9, 2_500));
    expect((await handle(request({ name: "d1" }), testEnv(), deps(jev.fetcher))).status).toBe(200);
    expect((await usage()).dayMicros).toBe(105 + attemptMicros("d1"));
  });

  it("does not charge rejected overload or client errors", async () => {
    const overloaded = fakeJev(new Response("busy", { status: 529 }), jevReply("rose", 0.9, 2_500));
    expect((await handle(request({ name: "e1" }), testEnv(), deps(overloaded.fetcher))).status).toBe(200);
    const rejected = fakeJev(new Response("bad key", { status: 401 }));
    expect((await handle(request({ name: "e2" }), testEnv(), deps(rejected.fetcher))).status).toBe(503);
    expect((await usage()).dayMicros).toBe(105);
  });

  it("retries when the reply body times out", async () => {
    const stalled = new Response(
      new ReadableStream({
        start(controller) {
          controller.error(Object.assign(new Error("timed out"), { name: "TimeoutError" }));
        },
      }),
      { status: 200 },
    );
    const jev = fakeJev(stalled, jevReply("rose"));
    expect(await body(await handle(request({ name: "f1" }), testEnv(), deps(jev.fetcher)))).toEqual({ emoji: "🌹", confidence: 0.9 });
    expect(jev.calls).toHaveLength(2);
  });

  it("rejects an oversized streamed body without a declared length", async () => {
    const chunk = new TextEncoder().encode("x".repeat(1_024));
    let pulled = 0;
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) {
        pulled += 1;
        if (pulled > 64) controller.close();
        else controller.enqueue(chunk);
      },
    });
    const streamed = new Request("https://icons.test/v1/gift-icon", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Install-ID": INSTALL },
      body: stream,
    });
    expect(streamed.headers.get("Content-Length")).toBeNull();
    expect((await handle(streamed, testEnv(), deps(fakeJev(jevReply("rose")).fetcher))).status).toBe(400);
    expect(pulled).toBeLessThan(10);
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
      counters: state.storage.sql.exec<{ scope: string; bucket: string }>("SELECT scope, bucket FROM counters").toArray(),
      cache: state.storage.sql.exec("SELECT hash FROM cache").toArray().length,
      reservations: state.storage.sql.exec("SELECT id FROM reservations").toArray().length,
      keys: state.storage.sql.exec("SELECT day FROM hash_keys").toArray().length,
      alarm: await state.storage.getAlarm(),
    }));
  }

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
        stub.admit({ cacheKey: `k${i}`, ...client, now: NOW, limits: { ...limits, perIpPerMinute: 3 }, reservationMicros: 10 }),
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
      answer: { cacheKey: "k1", key: "rose", confidence: 0.9 },
      now: Date.now() - 31 * 86_400_000,
    });
    await stub.admit({ cacheKey: "k2", ...client, now: old, limits: { ...limits, perIpPerMinute: 2 }, reservationMicros: 10 });
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

describe("Jev answer validation", () => {
  it("accepts a well-formed answer", () => {
    expect(parseAnswer(JSON.parse(JSON.stringify({
      model: "jev-1.13.0",
      answers: { icon: { choice: "rose", confidence: 0.5 } },
      usage: { input_tokens: 10 },
    })))).toEqual({ key: "rose", confidence: 0.5, inputTokens: 10, model: "jev-1.13.0" });
  });

  it.each([
    null,
    {},
    { answers: { icon: { choice: "rose", confidence: 2 } }, usage: { input_tokens: 1 } },
    { answers: { icon: { choice: "rose", confidence: 0.5 } }, usage: {} },
    { answers: { icon: { choice: "toString", confidence: 0.5 } }, usage: { input_tokens: 1 } },
  ])("rejects %j", (json) => {
    expect(() => parseAnswer(json)).toThrow();
  });
});

describe("evaluation cases", () => {
  it("only expect icons the catalog can return", async () => {
    const cases = (await import("../eval/cases.json")).default as Array<{ accept: Array<string | null> }>;
    const emoji = new Set(Object.values(ICONS).map((icon) => icon.emoji));
    const missing = cases.flatMap((item) => item.accept).filter((value) => value !== null && !emoji.has(value));
    expect(missing).toEqual([]);
  });
});
