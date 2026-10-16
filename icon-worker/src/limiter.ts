import { DurableObject } from "cloudflare:workers";

/** Limits, in whole requests or micro-dollars (1 USD = 1_000_000). */
export interface Limits {
  monthlyBudgetMicros: number;
  dailyBudgetMicros: number;
  perInstallPerDay: number;
  perIpPerMinute: number;
  globalPerMinute: number;
  /** Charged up front for each provider call and corrected once real usage is known. */
  reservationMicros: number;
}

export type Admission =
  | { kind: "cached"; key: string | null; confidence: number }
  | { kind: "go"; reservationId: number }
  | { kind: "rate_limited"; retryAfterSeconds: number }
  | { kind: "budget_exhausted" };

export interface AdmitInput {
  cacheKey: string;
  installHash: string;
  ipHash: string;
  now: number;
  limits: Limits;
}

export interface SettleInput {
  reservationId: number;
  /** Actual cost, or null to keep the reservation (usage unknown). */
  costMicros: number | null;
  /** Present only when the provider answered; undefined leaves the cache untouched. */
  answer?: { cacheKey: string; key: string | null; confidence: number };
  now: number;
}

const CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const MAX_CACHE_ROWS = 20_000;

/**
 * The single global coordinator: exact budget accounting, per-install and per-IP
 * limits, and a cache of answers keyed by a hash of the normalized gift name.
 * Durable Object methods run one at a time, so check-and-increment is atomic.
 * Only hashes are stored; raw gift names, install IDs and IP addresses are not.
 */
export class IconLimiter extends DurableObject<unknown> {
  private readonly sql: SqlStorage;

  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS counters (scope TEXT NOT NULL, bucket TEXT NOT NULL, value INTEGER NOT NULL,
        PRIMARY KEY (scope, bucket));
      CREATE TABLE IF NOT EXISTS cache (hash TEXT PRIMARY KEY, icon TEXT, confidence REAL NOT NULL, created INTEGER NOT NULL);
      CREATE INDEX IF NOT EXISTS cache_created ON cache (created);
      CREATE TABLE IF NOT EXISTS reservations (id INTEGER PRIMARY KEY AUTOINCREMENT, micros INTEGER NOT NULL,
        day TEXT NOT NULL, month TEXT NOT NULL, created INTEGER NOT NULL);
    `);
  }

  admit(input: AdmitInput): Admission {
    const { now, limits } = input;
    const day = dayBucket(now);
    const month = day.slice(0, 7);
    const minute = minuteBucket(now);

    const cached = this.sql
      .exec<{ icon: string | null; confidence: number; created: number }>(
        "SELECT icon, confidence, created FROM cache WHERE hash = ?",
        input.cacheKey,
      )
      .toArray()[0];
    if (cached && now - cached.created < CACHE_TTL_MS) {
      return { kind: "cached", key: cached.icon, confidence: cached.confidence };
    }

    const retryAfterMinute = 60 - Math.floor((now / 1000) % 60);
    if (this.get(`ip:${input.ipHash}`, minute) >= limits.perIpPerMinute) {
      return { kind: "rate_limited", retryAfterSeconds: retryAfterMinute };
    }
    if (this.get("global", minute) >= limits.globalPerMinute) {
      return { kind: "rate_limited", retryAfterSeconds: retryAfterMinute };
    }
    if (this.get(`install:${input.installHash}`, day) >= limits.perInstallPerDay) {
      return { kind: "rate_limited", retryAfterSeconds: secondsUntilNextDay(now) };
    }
    const reserve = limits.reservationMicros;
    if (
      this.get("spend", month) + reserve > limits.monthlyBudgetMicros ||
      this.get("spend", day) + reserve > limits.dailyBudgetMicros
    ) {
      return { kind: "budget_exhausted" };
    }

    this.add(`ip:${input.ipHash}`, minute, 1);
    this.add("global", minute, 1);
    this.add(`install:${input.installHash}`, day, 1);
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

  settle(input: SettleInput): void {
    const reservation = this.sql
      .exec<{ micros: number; day: string; month: string }>(
        "DELETE FROM reservations WHERE id = ? RETURNING micros, day, month",
        input.reservationId,
      )
      .toArray()[0];
    if (reservation && input.costMicros !== null) {
      const delta = input.costMicros - reservation.micros;
      this.add("spend", reservation.month, delta);
      this.add("spend", reservation.day, delta);
    }
    if (input.answer) {
      this.sql.exec(
        "INSERT OR REPLACE INTO cache (hash, icon, confidence, created) VALUES (?, ?, ?, ?)",
        input.answer.cacheKey,
        input.answer.key,
        input.answer.confidence,
        input.now,
      );
    }
    this.prune(input.now);
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
    const day = dayBucket(now);
    const month = day.slice(0, 7);
    // Minute and day buckets for anything but spend are only needed while current.
    this.sql.exec(
      "DELETE FROM counters WHERE scope != 'spend' AND bucket != ? AND bucket != ?",
      minuteBucket(now),
      day,
    );
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

function previousMonth(month: string): string {
  const [year, value] = month.split("-").map(Number);
  const date = new Date(Date.UTC(year, value - 2, 1));
  return date.toISOString().slice(0, 7);
}

function secondsUntilNextDay(now: number): number {
  const next = new Date(now);
  next.setUTCHours(24, 0, 0, 0);
  return Math.max(1, Math.ceil((next.getTime() - now) / 1000));
}
