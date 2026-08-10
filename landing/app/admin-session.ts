import { env } from "cloudflare:workers";
import { cookies } from "next/headers";
import type { ChatGPTUser } from "./chatgpt-auth";

const SESSION_COOKIE = "ssd_remover_admin";
const SESSION_TTL_SECONDS = 60 * 60 * 24 * 30;

type AdminEnv = {
  SSD_REMOVER_ADMIN_PASSWORD?: string;
  SSD_REMOVER_ADMIN_SESSION_SECRET?: string;
};

function adminEnv(): AdminEnv {
  return env as unknown as AdminEnv;
}

async function sha256(value: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
}

function constantTimeEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left[index] ^ right[index];
  return difference === 0;
}

async function signSession(userId: string, expiresAt: number): Promise<string | null> {
  const secret = adminEnv().SSD_REMOVER_ADMIN_SESSION_SECRET;
  if (!secret) return null;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${userId}:${expiresAt}`)),
  );
  return btoa(String.fromCharCode(...signature)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export async function verifyAdminPassword(candidate: string): Promise<boolean> {
  const password = adminEnv().SSD_REMOVER_ADMIN_PASSWORD;
  if (!password) return false;
  const [candidateDigest, passwordDigest] = await Promise.all([sha256(candidate), sha256(password)]);
  return constantTimeEqual(candidateDigest, passwordDigest);
}

export async function createAdminSessionCookie(user: ChatGPTUser): Promise<string | null> {
  const expiresAt = Math.floor(Date.now() / 1000) + SESSION_TTL_SECONDS;
  const signature = await signSession(user.userId, expiresAt);
  if (!signature) return null;

  return `${SESSION_COOKIE}=${expiresAt}.${signature}; Path=/; Max-Age=${SESSION_TTL_SECONDS}; HttpOnly; Secure; SameSite=Strict`;
}

export function clearAdminSessionCookie(): string {
  return `${SESSION_COOKIE}=; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Strict`;
}

export async function hasValidAdminSession(user: ChatGPTUser): Promise<boolean> {
  const cookieStore = await cookies();
  const session = cookieStore.get(SESSION_COOKIE)?.value;
  if (!session) return false;

  const [expiresAtText, signature] = session.split(".");
  const expiresAt = Number(expiresAtText);
  if (!signature || !Number.isInteger(expiresAt) || expiresAt <= Math.floor(Date.now() / 1000)) return false;

  const expected = await signSession(user.userId, expiresAt);
  if (!expected) return false;
  return constantTimeEqual(new TextEncoder().encode(signature), new TextEncoder().encode(expected));
}

export function safeAdminReturnTo(value: string | null | undefined): string {
  if (!value?.startsWith("/") || value.startsWith("//")) return "/admin";
  try {
    const url = new URL(value, "https://admin.local");
    if (url.origin !== "https://admin.local" || !url.pathname.startsWith("/admin")) return "/admin";
    return `${url.pathname}${url.search}${url.hash}`;
  } catch {
    return "/admin";
  }
}
