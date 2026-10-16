import { env, reset } from "cloudflare:test";
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

  it("reports unavailable when the API key is not configured", async () => {
    const response = await handle(request({ name: "розы" }), testEnv({ JEV_API_KEY: undefined }), deps(fakeJev(jevReply("rose")).fetcher));
    expect(response.status).toBe(503);
    expect(await body(response)).toEqual({ error: "unavailable" });
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
    // 0.0005 USD a day; each call reserves 168 micro-dollars and really costs 2,500 × 0.042 = 105.
    const tight = testEnv({ DAILY_BUDGET_USD: "0.0005" });
    const jev = fakeJev(jevReply("rose", 0.9, 2_500));
    const statuses: number[] = [];
    for (const name of ["a1", "a2", "a3", "a4", "a5", "a6"]) {
      statuses.push((await handle(request({ name }), tight, deps(jev.fetcher))).status);
    }
    // 105 × 4 = 420 spent; a fifth reservation (420 + 168) would exceed 500.
    expect(statuses).toEqual([200, 200, 200, 200, 503, 503]);
    expect(jev.calls).toHaveLength(4);
    // Cached names stay free even when the budget is exhausted.
    expect((await handle(request({ name: "a1" }), tight, deps(jev.fetcher))).status).toBe(200);
  });

  it("enforces the monthly budget across days", async () => {
    const tight = testEnv({ MONTHLY_BUDGET_USD: "0.0002" });
    const jev = fakeJev(jevReply("rose", 0.9, 2_500));
    expect((await handle(request({ name: "b1" }), tight, deps(jev.fetcher))).status).toBe(200);
    expect((await handle(request({ name: "b2" }), tight, deps(jev.fetcher, NOW + 86_400_000))).status).toBe(503);
    expect((await handle(request({ name: "b3" }), tight, deps(jev.fetcher, Date.UTC(2026, 10, 1)))).status).toBe(200);
  });

  it("keeps failed calls charged at the reservation", async () => {
    const tight = testEnv({ DAILY_BUDGET_USD: "0.0004" });
    const failing = fakeJev(new Response("busy", { status: 500 }));
    expect((await handle(request({ name: "c1" }), tight, deps(failing.fetcher))).status).toBe(503);
    expect((await handle(request({ name: "c2" }), tight, deps(failing.fetcher))).status).toBe(503);
    // Two reservations (336) are charged; a third would exceed 400.
    const ok = fakeJev(jevReply("rose"));
    expect(await body(await handle(request({ name: "c3" }), tight, deps(ok.fetcher)))).toEqual({ error: "budget_exhausted" });
    expect(ok.calls).toHaveLength(0);
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
