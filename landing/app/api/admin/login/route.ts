import { createAdminSessionCookie, safeAdminReturnTo, verifyAdminPassword } from "../../../admin-session";
import { getChatGPTUser } from "../../../chatgpt-auth";

export const dynamic = "force-dynamic";

function isSameOrigin(request: Request): boolean {
  const origin = request.headers.get("Origin");
  return origin === null || origin === new URL(request.url).origin;
}

export async function POST(request: Request) {
  if (!isSameOrigin(request)) return new Response("Forbidden", { status: 403 });
  const user = await getChatGPTUser();
  if (!user) return new Response("Unauthorized", { status: 401 });

  const form = await request.formData();
  const password = typeof form.get("password") === "string" ? String(form.get("password")) : "";
  const returnTo = safeAdminReturnTo(typeof form.get("returnTo") === "string" ? String(form.get("returnTo")) : null);
  if (!await verifyAdminPassword(password)) {
    return Response.redirect(new URL(`/admin/login?error=invalid&returnTo=${encodeURIComponent(returnTo)}`, request.url), 303);
  }

  const sessionCookie = await createAdminSessionCookie(user);
  if (!sessionCookie) return new Response("Admin authentication is not configured.", { status: 503 });
  return new Response(null, {
    status: 303,
    headers: {
      "Cache-Control": "private, no-store",
      Location: new URL(returnTo, request.url).toString(),
      "Set-Cookie": sessionCookie,
    },
  });
}
