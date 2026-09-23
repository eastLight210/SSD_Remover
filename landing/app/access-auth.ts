import { env } from "cloudflare:workers";
import { headers } from "next/headers";

// Admin routes sit behind a Cloudflare Access application. Access signs every
// request it lets through with a JWT; we verify it here so requests that reach
// the Worker another way (e.g. *.workers.dev) are still rejected.

export type AccessUser = {
  email: string;
};

type AccessEnv = {
  CF_ACCESS_TEAM_DOMAIN?: string;
  CF_ACCESS_AUD?: string;
  ADMIN_EMAILS?: string;
};

type Jwk = JsonWebKey & { kid?: string };

const JWT_HEADER = "cf-access-jwt-assertion";
const KEY_CACHE_TTL_MS = 60 * 60 * 1000;

let cachedKeys: { teamDomain: string; fetchedAt: number; keys: Map<string, CryptoKey> } | null = null;

function accessEnv(): AccessEnv {
  return env as unknown as AccessEnv;
}

function base64UrlDecode(value: string): Uint8Array<ArrayBuffer> {
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
}

function decodeJson<T>(segment: string): T | null {
  try {
    return JSON.parse(new TextDecoder().decode(base64UrlDecode(segment))) as T;
  } catch {
    return null;
  }
}

async function signingKeys(teamDomain: string, forceRefresh = false): Promise<Map<string, CryptoKey>> {
  if (!forceRefresh && cachedKeys?.teamDomain === teamDomain && Date.now() - cachedKeys.fetchedAt < KEY_CACHE_TTL_MS) {
    return cachedKeys.keys;
  }

  const response = await fetch(`https://${teamDomain}/cdn-cgi/access/certs`);
  if (!response.ok) throw new Error(`Could not load Access signing keys (${response.status})`);
  const { keys } = (await response.json()) as { keys: Jwk[] };

  const imported = new Map<string, CryptoKey>();
  for (const jwk of keys) {
    if (!jwk.kid) continue;
    imported.set(
      jwk.kid,
      await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]),
    );
  }
  cachedKeys = { teamDomain, fetchedAt: Date.now(), keys: imported };
  return imported;
}

async function verifyAccessJwt(token: string, teamDomain: string, audience: string): Promise<string | null> {
  const [headerSegment, payloadSegment, signatureSegment] = token.split(".");
  if (!headerSegment || !payloadSegment || !signatureSegment) return null;

  const header = decodeJson<{ alg?: string; kid?: string }>(headerSegment);
  if (header?.alg !== "RS256" || !header.kid) return null;

  let key = (await signingKeys(teamDomain)).get(header.kid);
  // Access rotates keys; refetch once when we see an unknown key id.
  if (!key) key = (await signingKeys(teamDomain, true)).get(header.kid);
  if (!key) return null;

  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    base64UrlDecode(signatureSegment),
    new TextEncoder().encode(`${headerSegment}.${payloadSegment}`),
  );
  if (!valid) return null;

  const payload = decodeJson<{ aud?: string | string[]; iss?: string; exp?: number; nbf?: number; email?: string }>(payloadSegment);
  if (!payload) return null;

  const now = Math.floor(Date.now() / 1000);
  const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!audiences.includes(audience)) return null;
  if (payload.iss !== `https://${teamDomain}`) return null;
  if (typeof payload.exp !== "number" || payload.exp <= now) return null;
  if (typeof payload.nbf === "number" && payload.nbf > now + 60) return null;
  return typeof payload.email === "string" ? payload.email.toLowerCase() : null;
}

export async function getAccessUser(): Promise<AccessUser | null> {
  const { CF_ACCESS_TEAM_DOMAIN: teamDomain, CF_ACCESS_AUD: audience, ADMIN_EMAILS: adminEmails } = accessEnv();
  // Fail closed until Access is configured.
  if (!teamDomain || !audience || !adminEmails) return null;

  const token = (await headers()).get(JWT_HEADER);
  if (!token) return null;

  const email = await verifyAccessJwt(token, teamDomain, audience).catch(() => null);
  if (!email) return null;

  const allowed = adminEmails.split(",").map((value) => value.trim().toLowerCase()).filter(Boolean);
  return allowed.includes(email) ? { email } : null;
}

export function accessLogoutPath(): string {
  return "/cdn-cgi/access/logout";
}
