import { env } from "cloudflare:workers";

export const USE_CASES = ["backups", "photo-video", "development", "general-storage", "other"] as const;

export type UseCase = (typeof USE_CASES)[number];

export type BetaSignup = {
  id: number;
  email: string;
  useCase: UseCase;
  source: string;
  createdAt: number;
  updatedAt: number;
};

export type SignupFilters = {
  query?: string;
  useCase?: UseCase;
};

export type SignupStats = {
  total: number;
  recent: number;
  latest: number | null;
  byUseCase: Record<UseCase, number>;
};

type D1Result<T> = { results?: T[] };

type D1PreparedStatement = {
  bind(...values: unknown[]): D1PreparedStatement;
  run(): Promise<unknown>;
  all<T>(): Promise<D1Result<T>>;
  first<T>(): Promise<T | null>;
};

type D1Like = {
  prepare(query: string): D1PreparedStatement;
};

type BetaSignupRow = {
  id: number;
  email: string;
  use_case: UseCase;
  source: string;
  created_at: number;
  updated_at: number;
};

const CREATE_TABLE_SQL =
  "CREATE TABLE IF NOT EXISTS beta_signups (id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT NOT NULL UNIQUE, use_case TEXT NOT NULL, source TEXT NOT NULL DEFAULT 'landing', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)";

function getDb(): D1Like {
  const db = (env as unknown as { DB?: D1Like }).DB;
  if (!db) throw new Error("Cloudflare D1 binding `DB` is unavailable.");
  return db;
}

export function isUseCase(value: string): value is UseCase {
  return (USE_CASES as readonly string[]).includes(value);
}

export async function ensureBetaSignupsTable(): Promise<void> {
  await getDb().prepare(CREATE_TABLE_SQL).run();
}

export async function upsertBetaSignup(email: string, useCase: UseCase): Promise<void> {
  const now = Date.now();
  await getDb()
    .prepare(
      "INSERT INTO beta_signups (email, use_case, source, created_at, updated_at) VALUES (?, ?, 'landing', ?, ?) ON CONFLICT(email) DO UPDATE SET use_case = excluded.use_case, updated_at = excluded.updated_at",
    )
    .bind(email, useCase, now, now)
    .run();
}

export async function listBetaSignups(filters: SignupFilters = {}, limit = 500): Promise<BetaSignup[]> {
  const conditions: string[] = [];
  const values: unknown[] = [];
  const normalizedQuery = filters.query?.trim().toLowerCase();

  if (normalizedQuery) {
    conditions.push("LOWER(email) LIKE ?");
    values.push(`%${normalizedQuery}%`);
  }
  if (filters.useCase) {
    conditions.push("use_case = ?");
    values.push(filters.useCase);
  }

  const where = conditions.length ? ` WHERE ${conditions.join(" AND ")}` : "";
  const safeLimit = Math.max(1, Math.min(Math.trunc(limit), 5000));
  const statement = getDb().prepare(
    `SELECT id, email, use_case, source, created_at, updated_at FROM beta_signups${where} ORDER BY created_at DESC LIMIT ?`,
  );
  const result = await statement.bind(...values, safeLimit).all<BetaSignupRow>();

  return (result.results ?? []).map((row) => ({
    id: row.id,
    email: row.email,
    useCase: row.use_case,
    source: row.source,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }));
}

export async function getBetaSignupStats(): Promise<SignupStats> {
  const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;
  const [summary, countsResult] = await Promise.all([
    getDb()
      .prepare(
        "SELECT COUNT(*) AS total, SUM(CASE WHEN created_at >= ? THEN 1 ELSE 0 END) AS recent, MAX(created_at) AS latest FROM beta_signups",
      )
      .bind(sevenDaysAgo)
      .first<{ total: number; recent: number | null; latest: number | null }>(),
    getDb()
      .prepare("SELECT use_case, COUNT(*) AS count FROM beta_signups GROUP BY use_case")
      .all<{ use_case: UseCase; count: number }>(),
  ]);

  const byUseCase = Object.fromEntries(USE_CASES.map((useCase) => [useCase, 0])) as Record<UseCase, number>;
  for (const row of countsResult.results ?? []) {
    if (isUseCase(row.use_case)) byUseCase[row.use_case] = Number(row.count);
  }

  return {
    total: Number(summary?.total ?? 0),
    recent: Number(summary?.recent ?? 0),
    latest: summary?.latest == null ? null : Number(summary.latest),
    byUseCase,
  };
}
