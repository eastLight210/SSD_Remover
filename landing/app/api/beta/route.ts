import { env } from "cloudflare:workers";

type D1Like = {
  prepare(query: string): {
    bind(...values: unknown[]): { run(): Promise<unknown> };
    run(): Promise<unknown>;
  };
};

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const allowedUseCases = new Set(["backups", "photo-video", "development", "general-storage", "other"]);

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as { email?: unknown; useCase?: unknown; company?: unknown };
    if (typeof body.company === "string" && body.company.trim()) {
      return Response.json({ message: "You’re on the private beta list." });
    }

    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const useCase = typeof body.useCase === "string" ? body.useCase.trim() : "";
    if (!emailPattern.test(email)) {
      return Response.json({ message: "Enter a valid email address." }, { status: 400 });
    }
    if (!allowedUseCases.has(useCase)) {
      return Response.json({ message: "Choose how you use external drives." }, { status: 400 });
    }

    const db = (env as unknown as { DB: D1Like }).DB;
    await db.prepare(
      "CREATE TABLE IF NOT EXISTS beta_signups (id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT NOT NULL UNIQUE, use_case TEXT NOT NULL, source TEXT NOT NULL DEFAULT 'landing', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
    ).run();

    const now = Date.now();
    await db.prepare(
      "INSERT INTO beta_signups (email, use_case, source, created_at, updated_at) VALUES (?, ?, 'landing', ?, ?) ON CONFLICT(email) DO UPDATE SET use_case = excluded.use_case, updated_at = excluded.updated_at"
    ).bind(email, useCase, now, now).run();

    return Response.json({ message: "You’re on the private beta list. I’ll be in touch." });
  } catch {
    return Response.json({ message: "Could not save your request. Please try again." }, { status: 500 });
  }
}
