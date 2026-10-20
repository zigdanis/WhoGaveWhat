import { DurableObject } from "cloudflare:workers";

/** Limits, in whole requests or micro-dollars (1 USD = 1_000_000). */
export interface Limits {
  monthlyBudgetMicros: number;
  dailyBudgetMicros: number;
  perInstallPerDay: number;
  perIpPerMinute: number;
  globalPerMinute: number;
}

export type Admission =
  | { kind: "cached"; key: string | null; confidence: number; price: number | null; priceConfidence: number | null }
  | { kind: "go"; reservationId: number }
  | { kind: "rate_limited"; retryAfterSeconds: number }
  | { kind: "budget_exhausted"; retryAfterSeconds: number };

export interface AdmitInput {
  cacheKey: string;
  /** Used only to derive keyed hashes for rate limits; never stored. */
  installID: string;
  /** Used only to derive keyed hashes for rate limits; never stored. */
  ip: string;
  now: number;
  limits: Limits;
  /** Charged up front for the provider call and corrected once its real cost is known. */
  reservationMicros: number;
}

export interface SettleInput {
  reservationId: number;
  /** The call's actual (or conservatively estimated) cost, replacing the reservation. */
  costMicros: number;
  /** Present only when the provider answered; undefined leaves the cache untouched. */
  answer?: {
    cacheKey: string;
    key: string | null;
    confidence: number;
    /** The price bucket and its confidence; both null for requests without a currency. */
    price: number | null;
    priceConfidence: number | null;
  };
  now: number;
}

const DAY_MS = 24 * 60 * 60 * 1000;
const CACHE_TTL_MS = 30 * DAY_MS;
const MAX_CACHE_ROWS = 20_000;
/** While data remains, an alarm prunes at least this often, even without traffic. */
const PRUNE_INTERVAL_MS = 60 * 60 * 1000;

/**
 * The single global coordinator: exact budget accounting, per-install and per-IP
 * limits, and a cache of answers keyed by a hash of the normalized gift name.
 * Each check-and-increment runs synchronously, so it is atomic.
 * Raw gift names, install IDs and IP addresses are never stored. Install IDs and IP
 * addresses are counted under HMACs with a random key per UTC day, and each key is
 * deleted once the next day ends, along with its counters, so at most about two days later.
 */
export class IconLimiter extends DurableObject<unknown> {
  private readonly sql: SqlStorage;

  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS counters (scope TEXT NOT NULL, bucket TEXT NOT NULL, value INTEGER NOT NULL,
        PRIMARY KEY (scope, bucket));
      CREATE TABLE IF NOT EXISTS cache (hash TEXT PRIMARY KEY, icon TEXT, confidence REAL NOT NULL, created INTEGER NOT NULL,
        price REAL, price_confidence REAL);
      CREATE INDEX IF NOT EXISTS cache_created ON cache (created);
      CREATE TABLE IF NOT EXISTS reservations (id INTEGER PRIMARY KEY AUTOINCREMENT, micros INTEGER NOT NULL,
        day TEXT NOT NULL, month TEXT NOT NULL, created INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS hash_keys (day TEXT PRIMARY KEY, key BLOB NOT NULL);
    `);
    this.addMissingCacheColumns();
  }

  /** The cache table predates the price columns in production, and CREATE TABLE IF NOT EXISTS keeps it as it was. */
  private addMissingCacheColumns(): void {
    const existing = new Set(this.sql.exec<{ name: string }>("PRAGMA table_info(cache)").toArray().map((column) => column.name));
    for (const column of ["price", "price_confidence"]) {
      if (!existing.has(column)) this.sql.exec(`ALTER TABLE cache ADD COLUMN ${column} REAL`);
    }
  }

  async admit(input: AdmitInput): Promise<Admission> {
    const key = this.hashKey(dayBucket(input.now));
    const installHash = await hmac(key, `install\n${input.installID.toLowerCase()}`);
    const ipHash = await hmac(key, `ip\n${input.ip}`);
    this.prune(input.now);
    const admission = this.check(input, installHash, ipHash);
    await this.scheduleAlarm();
    return admission;
  }

  /** Synchronous, so no other request interleaves between a check and its increment. */
  private check(input: AdmitInput, installHash: string, ipHash: string): Admission {
    const { now, limits } = input;
    const day = dayBucket(now);
    const month = day.slice(0, 7);
    const minute = minuteBucket(now);

    const cached = this.sql
      .exec<{ icon: string | null; confidence: number; created: number; price: number | null; price_confidence: number | null }>(
        "SELECT icon, confidence, created, price, price_confidence FROM cache WHERE hash = ?",
        input.cacheKey,
      )
      .toArray()[0];
    if (cached && now - cached.created < CACHE_TTL_MS) {
      return {
        kind: "cached",
        key: cached.icon,
        confidence: cached.confidence,
        price: cached.price,
        priceConfidence: cached.price_confidence,
      };
    }

    const retryAfterMinute = 60 - Math.floor((now / 1000) % 60);
    if (this.get(`ip:${ipHash}`, minute) >= limits.perIpPerMinute) {
      return { kind: "rate_limited", retryAfterSeconds: retryAfterMinute };
    }
    if (this.get("global", minute) >= limits.globalPerMinute) {
      return { kind: "rate_limited", retryAfterSeconds: retryAfterMinute };
    }
    if (this.get(`install:${installHash}`, day) >= limits.perInstallPerDay) {
      return { kind: "rate_limited", retryAfterSeconds: secondsUntilNextDay(now) };
    }
    const reserve = input.reservationMicros;
    if (this.get("spend", month) + reserve > limits.monthlyBudgetMicros) {
      return { kind: "budget_exhausted", retryAfterSeconds: secondsUntilNextMonth(now) };
    }
    if (this.get("spend", day) + reserve > limits.dailyBudgetMicros) {
      return { kind: "budget_exhausted", retryAfterSeconds: secondsUntilNextDay(now) };
    }

    this.add(`ip:${ipHash}`, minute, 1);
    this.add("global", minute, 1);
    this.add(`install:${installHash}`, day, 1);
    this.add("spend", month, reserve);
    this.add("spend", day, reserve);
    const id = this.sql
      .exec<{ id: number }>(
        "INSERT INTO reservations (micros, day, month, created) VALUES (?, ?, ?, ?) RETURNING id",
        reserve,
        day,
        month,
        now,
      )
      .one().id;
    return { kind: "go", reservationId: id };
  }

  async settle(input: SettleInput): Promise<void> {
    const reservation = this.sql
      .exec<{ micros: number; day: string; month: string }>(
        "DELETE FROM reservations WHERE id = ? RETURNING micros, day, month",
        input.reservationId,
      )
      .toArray()[0];
    if (reservation) {
      const delta = input.costMicros - reservation.micros;
      this.add("spend", reservation.month, delta);
      this.add("spend", reservation.day, delta);
    }
    if (input.answer) {
      this.sql.exec(
        "INSERT OR REPLACE INTO cache (hash, icon, confidence, created, price, price_confidence) VALUES (?, ?, ?, ?, ?, ?)",
        input.answer.cacheKey,
        input.answer.key,
        input.answer.confidence,
        input.now,
        input.answer.price,
        input.answer.priceConfidence,
      );
    }
    this.prune(input.now);
    await this.scheduleAlarm();
  }

  /** Prunes without traffic, and keeps waking until nothing that expires is left. */
  async alarm(): Promise<void> {
    this.prune(Date.now());
    const remaining = this.sql
      .exec<{ n: number }>(
        `SELECT (SELECT COUNT(*) FROM counters WHERE scope != 'spend') + (SELECT COUNT(*) FROM cache)
           + (SELECT COUNT(*) FROM reservations) + (SELECT COUNT(*) FROM hash_keys) AS n`,
      )
      .one().n;
    if (remaining > 0) await this.ctx.storage.setAlarm(Date.now() + PRUNE_INTERVAL_MS);
  }

  /** Spend so far, in micro-dollars, for operational checks. */
  usage(now: number): { monthMicros: number; dayMicros: number; cachedAnswers: number } {
    const day = dayBucket(now);
    return {
      monthMicros: this.get("spend", day.slice(0, 7)),
      dayMicros: this.get("spend", day),
      cachedAnswers: this.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM cache").one().n,
    };
  }

  /** The random HMAC key for a UTC day, created on first use. */
  private hashKey(day: string): ArrayBuffer {
    const row = this.sql.exec<{ key: ArrayBuffer }>("SELECT key FROM hash_keys WHERE day = ?", day).toArray()[0];
    if (row) return row.key;
    const key = crypto.getRandomValues(new Uint8Array(32));
    this.sql.exec("INSERT INTO hash_keys (day, key) VALUES (?, ?)", day, key);
    return key.buffer;
  }

  /** Requests keep pushing the alarm back; they prune inline, so it only matters when idle. */
  private async scheduleAlarm(): Promise<void> {
    await this.ctx.storage.setAlarm(Date.now() + PRUNE_INTERVAL_MS);
  }

  private get(scope: string, bucket: string): number {
    const row = this.sql
      .exec<{ value: number }>("SELECT value FROM counters WHERE scope = ? AND bucket = ?", scope, bucket)
      .toArray()[0];
    return row?.value ?? 0;
  }

  private add(scope: string, bucket: string, amount: number): void {
    this.sql.exec(
      `INSERT INTO counters (scope, bucket, value) VALUES (?, ?, ?)
       ON CONFLICT (scope, bucket) DO UPDATE SET value = value + excluded.value`,
      scope,
      bucket,
      amount,
    );
  }

  /** Drops expired counters, stale reservations and old or excess cache rows. */
  private prune(now: number): void {
    const month = dayBucket(now).slice(0, 7);
    // Rate counters are only read for the current minute or day. Callers' clocks can differ
    // slightly, so only buckets well in the past are dropped, never a newer one.
    this.sql.exec(
      "DELETE FROM counters WHERE scope != 'spend' AND length(bucket) = 16 AND bucket < ?",
      minuteBucket(now - 5 * 60 * 1000),
    );
    this.sql.exec(
      "DELETE FROM counters WHERE scope != 'spend' AND length(bucket) = 10 AND bucket < ?",
      dayBucket(now - DAY_MS),
    );
    // Without its key, a counter's hash can no longer be checked against any address.
    this.sql.exec("DELETE FROM hash_keys WHERE day < ?", dayBucket(now - DAY_MS));
    // Keep this and last month's spend for inspection.
    this.sql.exec("DELETE FROM counters WHERE scope = 'spend' AND substr(bucket, 1, 7) < ?", previousMonth(month));
    // Reservations a crashed request never settled stay charged; just forget them.
    this.sql.exec("DELETE FROM reservations WHERE created < ?", now - 10 * 60 * 1000);
    this.sql.exec("DELETE FROM cache WHERE created < ?", now - CACHE_TTL_MS);
    this.sql.exec(
      "DELETE FROM cache WHERE hash IN (SELECT hash FROM cache ORDER BY created DESC LIMIT -1 OFFSET ?)",
      MAX_CACHE_ROWS,
    );
  }
}

export function dayBucket(now: number): string {
  return new Date(now).toISOString().slice(0, 10);
}

function minuteBucket(now: number): string {
  return new Date(now).toISOString().slice(0, 16);
}

async function hmac(key: ArrayBuffer, text: string): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey("raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(text));
  return [...new Uint8Array(signature)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function previousMonth(month: string): string {
  const [year, value] = month.split("-").map(Number);
  const date = new Date(Date.UTC(year, value - 2, 1));
  return date.toISOString().slice(0, 7);
}

function secondsUntilNextMonth(now: number): number {
  const date = new Date(now);
  const next = Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1);
  return Math.max(1, Math.ceil((next - now) / 1000));
}

function secondsUntilNextDay(now: number): number {
  const next = new Date(now);
  next.setUTCHours(24, 0, 0, 0);
  return Math.max(1, Math.ceil((next.getTime() - now) / 1000));
}
